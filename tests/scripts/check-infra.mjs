import './prepare.mjs';
import { readFile, mkdir, writeFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
import { createPublicKey, verify } from 'node:crypto';
import { compose } from './compose.mjs';

const artifacts = new URL('../artifacts/', import.meta.url);
await mkdir(artifacts, { recursive: true });
const report = { scope: 'Infrastructure only; no application verification', generatedAt: new Date().toISOString(), checks: [] };
async function check(name, callback) {
  try { await callback(); report.checks.push({ name, status: 'PASS' }); }
  catch { report.checks.push({ name, status: 'FAIL' }); process.exitCode = 1; }
}
const base = 'http://127.0.0.1:58081/realms/propiedades-test';
async function fetchLocal(url, options = {}) {
  return fetch(url, { ...options, signal: AbortSignal.timeout(5000) });
}
async function ready() {
  const deadline = Date.now() + 120000;
  while (Date.now() < deadline) {
    try { const response = await fetchLocal(`${base}/.well-known/openid-configuration`); if (response.ok) return; } catch {}
    await new Promise(resolve => setTimeout(resolve, 1500));
  }
  throw new Error('Keycloak did not become ready.');
}
const settings = JSON.parse(await readFile(new URL('../.runtime/settings.json', import.meta.url), 'utf8'));
await check('Keycloak discovery and realm', async () => {
  await ready();
  const config = await (await fetchLocal(`${base}/.well-known/openid-configuration`)).json();
  assert.equal(config.issuer, base);
  assert.ok(config.code_challenge_methods_supported.includes('S256'));
});
await check('Keycloak issues signed service token for isolated probe', async () => {
  const response = await fetchLocal(`${base}/protocol/openid-connect/token`, {
    method: 'POST', body: new URLSearchParams({ grant_type: 'client_credentials', client_id: 'infra-probe', client_secret: settings.TEST_CLIENT_SECRET })
  });
  assert.equal(response.status, 200);
  const token = (await response.json()).access_token;
  assert.equal(token.split('.').length, 3);
  const claims = JSON.parse(Buffer.from(token.split('.')[1], 'base64url'));
  assert.equal(claims.iss, base);
  assert.ok(claims.exp > Math.floor(Date.now() / 1000));
  const keys = await (await fetchLocal(`${base}/protocol/openid-connect/certs`)).json();
  const [headerPart, payloadPart, signaturePart] = token.split('.');
  const header = JSON.parse(Buffer.from(headerPart, 'base64url'));
  assert.equal(header.alg, 'RS256');
  const jwk = keys.keys.find(key => key.kid === header.kid && key.use === 'sig');
  assert.ok(jwk);
  assert.ok(verify('RSA-SHA256', Buffer.from(`${headerPart}.${payloadPart}`), createPublicKey({ key: jwk, format: 'jwk' }), Buffer.from(signaturePart, 'base64url')));
  // This verifies the probe token, not a yet-unimplemented application validator.
});
await check('Keycloak rejects wrong client secret', async () => {
  const response = await fetchLocal(`${base}/protocol/openid-connect/token`, {
    method: 'POST', body: new URLSearchParams({ grant_type: 'client_credentials', client_id: 'infra-probe', client_secret: 'intentionally-invalid-test-secret' })
  });
  assert.equal(response.status, 401);
});
function sql(statement) {
  return compose(['exec', '-T', 'postgres', 'psql', '-X', '-v', 'ON_ERROR_STOP=1', '-U', 'propiedades_test', '-d', 'propiedades_tests', '-At', '-c', statement]);
}
await check('PostgreSQL synthetic fixtures and unknown partial amount', async () => {
  const result = sql("SELECT count(*) FROM test_fixtures.pagos; SELECT count(*) FROM test_fixtures.pagos WHERE estado='parcial' AND importe_abonado IS NULL;");
  assert.equal(result.status, 0);
  assert.equal(result.stdout.trim().replaceAll('\r', ''), '3\n1');
});
await check('PostgreSQL rejects missing tenant reference', async () => {
  const result = sql("BEGIN; INSERT INTO test_fixtures.pagos VALUES ('test-invalid', 'missing', '2026-04', 'pendiente', NULL); ROLLBACK;");
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /foreign key constraint/i);
});
await check('PostgreSQL rejects duplicate tenant/month', async () => {
  const result = sql("BEGIN; INSERT INTO test_fixtures.pagos VALUES ('test-duplicate', 'test-inq-001', '2026-01', 'pagado', 450.00); ROLLBACK;");
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /unique constraint/i);
});
const output = new URL(`infra-${report.generatedAt.replaceAll(':', '-')}.json`, artifacts);
await writeFile(output, JSON.stringify(report, null, 2));
for (const item of report.checks) console.log(`${item.status}: ${item.name}`);
console.log(`Infrastructure evidence: ${output.pathname}`);
