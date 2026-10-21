import { readFile } from 'node:fs/promises';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';

export async function startTestBackend({owner=false}={}) {
  const settings=JSON.parse(await readFile(new URL('../.runtime/settings.json',import.meta.url),'utf8'));
  // Resolve only the synthetic test account; production identity must be configured explicitly.
  const response=await fetch('http://127.0.0.1:58081/realms/propiedades-test/protocol/openid-connect/token',{
    method:'POST',body:new URLSearchParams({grant_type:'client_credentials',client_id:'infra-probe',client_secret:settings.TEST_CLIENT_SECRET}),signal:AbortSignal.timeout(5000)
  });
  if(!response.ok) throw new Error('Synthetic identity discovery failed');
  const {access_token}=await response.json();
  const {sub}=JSON.parse(Buffer.from(access_token.split('.')[1],'base64url').toString());
  if(typeof sub!=='string'||!sub) throw new Error('Synthetic subject unavailable');
  const executable=fileURLToPath(new URL(`../../backend/target/debug/propiedades-backend${process.platform==='win32'?'.exe':''}`,import.meta.url));
  const child=spawn(executable,['--dev','--migrate'],{
    cwd:fileURLToPath(new URL('../../',import.meta.url)),windowsHide:true,
    env:{...process.env,DATABASE_URL:`postgres://propiedades_test:${settings.TEST_DB_PASSWORD}@127.0.0.1:55432/propiedades_tests`,
      KEYCLOAK_ISSUER:'http://127.0.0.1:58081/realms/propiedades-test',KEYCLOAK_AUDIENCE:'propiedades-api',
      KEYCLOAK_ALLOWED_SUBJECT:owner?(settings.TEST_OWNER_SUB||''):sub,
      ...(owner?{KEYCLOAK_LOGIN_CLIENT_ID:'portal-local-login',KEYCLOAK_LOGIN_CLIENT_SECRET:settings.TEST_LOGIN_SECRET||'',PORTAL_ORIGIN:'http://127.0.0.1:55173'}:{}),
      BACKEND_BIND:'127.0.0.1:58080'}
  });
  return child;
}
