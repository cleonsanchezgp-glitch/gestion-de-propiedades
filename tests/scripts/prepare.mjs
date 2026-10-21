import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { randomBytes } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const runtime = fileURLToPath(new URL('../.runtime/', import.meta.url));
await mkdir(path.join(runtime, 'realm'), { recursive: true });
let settings;
try { settings = JSON.parse(await readFile(path.join(runtime, 'settings.json'), 'utf8')); }
catch (error) {
  if (error.code !== 'ENOENT') throw error;
  settings = Object.fromEntries(['TEST_DB_PASSWORD', 'TEST_ADMIN_PASSWORD', 'TEST_CLIENT_SECRET'].map(key => [key, randomBytes(32).toString('hex')]));
  await writeFile(path.join(runtime, 'settings.json'), JSON.stringify(settings), { mode: 0o600 });
}
for (const key of ['TEST_DB_PASSWORD', 'TEST_ADMIN_PASSWORD', 'TEST_CLIENT_SECRET']) {
  if (!/^[a-f0-9]{64}$/.test(settings[key])) throw new Error('Invalid local test settings; do not overwrite existing credentials.');
}
await writeFile(path.join(runtime, '.env'), Object.entries(settings).map(([key, value]) => `${key}=${value}`).join('\n') + '\n', { mode: 0o600 });
const realm = {
  realm: 'propiedades-test', enabled: true, sslRequired: 'none', registrationAllowed: false,
  accessTokenLifespan: 60,
  roles: { realm: [{name:'infra-read'},{name:'infra-write'}] },
  users: [
    { username:'service-account-infra-probe', enabled:true, serviceAccountClientId:'infra-probe', realmRoles:['infra-read','infra-write'] },
    { username:'service-account-infra-reader', enabled:true, serviceAccountClientId:'infra-reader', realmRoles:['infra-read'] }
  ],
  clients: [
    { clientId: 'propiedades-frontend-test', enabled: true, publicClient: true, standardFlowEnabled: true,
      directAccessGrantsEnabled: false, implicitFlowEnabled: false,
      redirectUris: ['http://127.0.0.1:55173/*'], webOrigins: ['http://127.0.0.1:55173'],
      attributes: { 'pkce.code.challenge.method': 'S256' } },
    ...['infra-probe','infra-reader','infra-denied','infra-wrong-audience'].map(clientId => ({
      clientId, enabled:true, publicClient:false, secret:settings.TEST_CLIENT_SECRET,
      serviceAccountsEnabled:true, standardFlowEnabled:false, directAccessGrantsEnabled:false,
      protocolMappers:[{ name:'backend-audience', protocol:'openid-connect', protocolMapper:'oidc-audience-mapper',
        config:{'included.custom.audience':clientId==='infra-wrong-audience'?'other-api':'propiedades-api','access.token.claim':'true','id.token.claim':'false'} }]
    }))
  ]
};
await writeFile(path.join(runtime, 'realm', 'propiedades-test-realm.json'), JSON.stringify(realm, null, 2), { mode: 0o600 });
console.log('Local test settings prepared; no credentials printed.');
