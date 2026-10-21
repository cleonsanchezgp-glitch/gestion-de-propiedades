import {readFile,writeFile} from 'node:fs/promises';
import {randomBytes} from 'node:crypto';
const base='http://127.0.0.1:58081';
const settingsUrl=new URL('../.runtime/settings.json',import.meta.url);
const settings=JSON.parse(await readFile(settingsUrl,'utf8'));
const response=await fetch(`${base}/realms/master/protocol/openid-connect/token`,{method:'POST',body:new URLSearchParams({grant_type:'password',client_id:'admin-cli',username:'test_admin',password:settings.TEST_ADMIN_PASSWORD}),signal:AbortSignal.timeout(10000)});
if(!response.ok)throw new Error('Local Keycloak administration unavailable. Start and check test infrastructure first.');
const {access_token}=await response.json();
async function admin(path,{method='GET',body}={}){
  const result=await fetch(`${base}/admin/realms/propiedades-test${path}`,{method,headers:{Authorization:`Bearer ${access_token}`,...(body?{'Content-Type':'application/json'}:{})},body:body?JSON.stringify(body):undefined,signal:AbortSignal.timeout(10000)});
  if(!result.ok)throw new Error(`Local identity configuration failed (${result.status})`);
  return result.status===204||result.status===201?null:result.json();
}
for(const [username,prefix] of [['gestor-local','TEST_OWNER'],['sin-acceso-local','TEST_OTHER']]){
  let users=await admin(`/users?username=${username}&exact=true`);
  if(!users.length){await admin('/users',{method:'POST',body:{username,enabled:true,emailVerified:true,firstName:'Gestor',lastName:'Local',email:`${username}@example.test`,requiredActions:[]}});users=await admin(`/users?username=${username}&exact=true`);}
  if(users.length!==1)throw new Error('Ambiguous synthetic identity');
  settings[`${prefix}_SUB`]=users[0].id;
  settings[`${prefix}_PASSWORD`]??=randomBytes(24).toString('hex');
  await admin(`/users/${users[0].id}/reset-password`,{method:'PUT',body:{type:'password',value:settings[`${prefix}_PASSWORD`],temporary:false}});
}
const clients=await admin('/clients?clientId=propiedades-frontend-test');
if(clients.length!==1)throw new Error('Synthetic frontend client unavailable');
const client=clients[0];
await admin(`/clients/${client.id}`,{method:'PUT',body:{...client,publicClient:true,standardFlowEnabled:true,directAccessGrantsEnabled:false,redirectUris:['http://127.0.0.1:55173/*'],webOrigins:['http://127.0.0.1:55173'],attributes:{...client.attributes,'pkce.code.challenge.method':'S256'}}});
const mappers=await admin(`/clients/${client.id}/protocol-mappers/models`);
if(!mappers.some(m=>m.name==='backend-audience'))await admin(`/clients/${client.id}/protocol-mappers/models`,{method:'POST',body:{name:'backend-audience',protocol:'openid-connect',protocolMapper:'oidc-audience-mapper',config:{'included.custom.audience':'propiedades-api','access.token.claim':'true','id.token.claim':'false'}}});
await writeFile(settingsUrl,JSON.stringify(settings,null,2),{mode:0o600});
await writeFile(new URL('../.runtime/local-access.txt',import.meta.url),`Acceso local de pruebas (no producción)\nPortal: http://127.0.0.1:55173\nUsuario: gestor-local\nContraseña: ${settings.TEST_OWNER_PASSWORD}\n`,{mode:0o600});
await writeFile(new URL('../../frontend/.env.local',import.meta.url),'VITE_KEYCLOAK_URL=http://127.0.0.1:58081\nVITE_KEYCLOAK_REALM=propiedades-test\nVITE_KEYCLOAK_CLIENT_ID=propiedades-frontend-test\n');
console.log('Local identities and frontend configured. Credentials saved to tests/.runtime/local-access.txt; no passwords printed.');
