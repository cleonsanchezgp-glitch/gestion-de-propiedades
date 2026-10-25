import { randomBytes, randomUUID } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.dirname(fileURLToPath(import.meta.url));
const runtime = path.join(root, '.runtime');
const settingsFile = path.join(runtime, 'settings.json');
const envFile = path.join(runtime, '.env');
const composeFile = path.join(root, 'compose.yaml');
const action = process.argv[2] || 'up';
if (!['up', 'down', 'status'].includes(action)) throw new Error('Use up, down o status.');

function docker(...args) {
  const result = spawnSync('docker', args, { stdio: 'inherit', timeout: 600_000 });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`Docker terminó con código ${result.status}.`);
}
const compose = (...args) => docker('compose', '-p', 'propiedades-dev', '--env-file', envFile, '-f', composeFile, ...args);

async function settings() {
  await mkdir(path.join(runtime, 'realm'), { recursive: true });
  let value;
  try { value = JSON.parse(await readFile(settingsFile, 'utf8')); }
  catch (error) {
    if (error.code !== 'ENOENT') throw error;
    value = {
      dbPassword: randomBytes(32).toString('hex'),
      keycloakDbPassword: randomBytes(32).toString('hex'),
      adminPassword: randomBytes(32).toString('hex'),
      loginSecret: randomBytes(32).toString('hex'),
      ownerPassword: randomBytes(24).toString('hex'),
      ownerSubject: randomUUID(),
      keycloakPort: 58200,
      apiPort: 58201,
      postgresPort: 58202,
      frontendPort: 55173,
    };
    await writeFile(settingsFile, JSON.stringify(value, null, 2), { mode: 0o600, flag: 'wx' });
  }
  value.frontendPort ??= 55173;
  for (const key of ['dbPassword', 'keycloakDbPassword', 'adminPassword', 'loginSecret']) {
    if (!/^[a-f0-9]{64}$/.test(value[key])) throw new Error(`Configuración local inválida: ${key}`);
  }
  if (!/^[a-f0-9]{48}$/.test(value.ownerPassword) || !/^[a-f0-9-]{36}$/.test(value.ownerSubject)) throw new Error('Identidad local inválida.');
  const ports = [value.keycloakPort, value.apiPort, value.postgresPort, value.frontendPort];
  if (new Set(ports).size !== 4 || ports.some(port => !Number.isInteger(port) || port < 1024 || port > 65535)) throw new Error('Puertos de desarrollo inválidos.');
  const env = {
    DEV_DB_PASSWORD: value.dbPassword,
    DEV_KEYCLOAK_DB_PASSWORD: value.keycloakDbPassword,
    DEV_ADMIN_PASSWORD: value.adminPassword,
    DEV_LOGIN_SECRET: value.loginSecret,
    DEV_OWNER_SUBJECT: value.ownerSubject,
    DEV_KEYCLOAK_PORT: value.keycloakPort,
    DEV_API_PORT: value.apiPort,
    DEV_POSTGRES_PORT: value.postgresPort,
    DEV_FRONTEND_PORT: value.frontendPort,
  };
  await writeFile(envFile, Object.entries(env).map(([key, entry]) => `${key}=${entry}`).join('\n') + '\n', { mode: 0o600 });
  const realm = {
    realm: 'propiedades-dev', enabled: true, sslRequired: 'none', registrationAllowed: false,
    bruteForceProtected: true,
    users: [{ id: value.ownerSubject, username: 'dev-owner', firstName: 'Dev', lastName: 'Owner',
      email: 'dev-owner@example.test', enabled: true, emailVerified: true, requiredActions: [],
      credentials: [{ type: 'password', value: value.ownerPassword, temporary: false }] }],
    clients: [{ clientId: 'portal-login', enabled: true, publicClient: false,
      secret: value.loginSecret, standardFlowEnabled: false, directAccessGrantsEnabled: true,
      serviceAccountsEnabled: false,
      protocolMappers: [{ name: 'backend-audience', protocol: 'openid-connect', protocolMapper: 'oidc-audience-mapper',
        config: { 'included.custom.audience': 'propiedades-api', 'access.token.claim': 'true', 'id.token.claim': 'false' } }],
    }],
  };
  await writeFile(path.join(runtime, 'realm', 'propiedades-dev-realm.json'), JSON.stringify(realm, null, 2), { mode: 0o600 });
  await writeFile(path.join(runtime, 'access.txt'),
    `Acceso local de desarrollo (no producción)\nPortal: http://127.0.0.1:${value.frontendPort}\nUsuario: dev-owner\nContraseña: ${value.ownerPassword}\nKeycloak admin: dev-admin\nContraseña admin: ${value.adminPassword}\n`, { mode: 0o600 });
  return value;
}

async function waitFor(url, seconds) {
  const deadline = Date.now() + seconds * 1000;
  while (Date.now() < deadline) {
    try { const response = await fetch(url, { signal: AbortSignal.timeout(4000) }); if (response.ok) return response; }
    catch { /* El contenedor aún está arrancando. */ }
    await new Promise(resolve => setTimeout(resolve, 3000));
  }
  throw new Error(`El servicio no respondió: ${url}`);
}

async function ensureIdentity(value) {
  const base = `http://127.0.0.1:${value.keycloakPort}`;
  const tokenResponse = await fetch(`${base}/realms/master/protocol/openid-connect/token`, {
    method: 'POST', body: new URLSearchParams({ grant_type: 'password', client_id: 'admin-cli',
      username: 'dev-admin', password: value.adminPassword }), signal: AbortSignal.timeout(10000),
  });
  if (!tokenResponse.ok) throw new Error('No se pudo administrar el Keycloak local.');
  const { access_token } = await tokenResponse.json();
  async function admin(endpoint, options = {}) {
    const response = await fetch(`${base}/admin/realms/propiedades-dev${endpoint}`, {
      method: options.method || 'GET',
      headers: { Authorization: `Bearer ${access_token}`, ...(options.body ? { 'Content-Type': 'application/json' } : {}) },
      body: options.body ? JSON.stringify(options.body) : undefined, signal: AbortSignal.timeout(10000),
    });
    if (!response.ok) throw new Error(`No se pudo configurar la identidad local (${response.status}).`);
    return response.status === 204 ? null : response.json();
  }
  const users = await admin('/users?username=dev-owner&exact=true');
  if (users.length !== 1 || users[0].id !== value.ownerSubject) throw new Error('El usuario de desarrollo no coincide con la configuración local.');
  await admin(`/users/${users[0].id}`, { method: 'PUT', body: { ...users[0],
    firstName: 'Dev', lastName: 'Owner', email: 'dev-owner@example.test',
    emailVerified: true, requiredActions: [], enabled: true } });
}

const value = await settings();
if (action === 'down') {
  compose('down');
  console.log('Contenedores detenidos. Los volúmenes y credenciales se conservan.');
} else if (action === 'status') {
  compose('ps');
} else {
  compose('build', 'api');
  compose('build', 'frontend');
  compose('stop', 'frontend', 'api');
  compose('up', '-d', 'postgres', 'keycloak-db', 'keycloak');
  await waitFor(`http://127.0.0.1:${value.keycloakPort}/realms/propiedades-dev/.well-known/openid-configuration`, 180);
  await ensureIdentity(value);
  compose('run', '--rm', '--no-deps', 'api', '--container-migrate');
  compose('up', '-d', '--no-deps', 'api');
  await waitFor(`http://127.0.0.1:${value.apiPort}/health/live`, 90);
  compose('up', '-d', '--no-deps', 'frontend');
  const base = `http://127.0.0.1:${value.frontendPort}`;
  const page = await waitFor(base, 90);
  if (!(await page.text()).includes('<div id="app"')) throw new Error('El frontend no sirvió la aplicación.');
  await waitFor(`${base}/health/live`, 30);
  const login = await fetch(`${base}/api/v1/session/login`, { method: 'POST',
    headers: { Origin: base, 'Content-Type': 'application/json' },
    body: JSON.stringify({ username: 'dev-owner', password: value.ownerPassword }), signal: AbortSignal.timeout(10000) });
  if (!login.ok) throw new Error(`La API arrancó, pero el login de desarrollo falló (${login.status}).`);
  const cookie = login.headers.get('set-cookie')?.split(';')[0];
  if (!cookie) throw new Error('El login no entregó una sesión.');
  const me = await fetch(`${base}/api/v1/me`, { headers: { Cookie: cookie }, signal: AbortSignal.timeout(10000) });
  if (!me.ok) throw new Error(`La sesión de desarrollo falló (${me.status}).`);
  console.log(`Desarrollo listo: Portal ${base}, API http://127.0.0.1:${value.apiPort}, Keycloak http://127.0.0.1:${value.keycloakPort}`);
  console.log(`Credenciales locales: ${path.join(runtime, 'access.txt')}`);
  compose('ps');
}
