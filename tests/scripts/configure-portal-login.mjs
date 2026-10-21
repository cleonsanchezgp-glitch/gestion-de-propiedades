import {readFile,writeFile} from 'node:fs/promises';
import {randomBytes} from 'node:crypto';
const url=new URL('../.runtime/settings.json',import.meta.url);
const settings=JSON.parse(await readFile(url,'utf8'));
settings.TEST_LOGIN_SECRET??=randomBytes(32).toString('hex');
const base='http://127.0.0.1:58081';
const response=await fetch(`${base}/realms/master/protocol/openid-connect/token`,{method:'POST',body:new URLSearchParams({grant_type:'password',client_id:'admin-cli',username:'test_admin',password:settings.TEST_ADMIN_PASSWORD}),signal:AbortSignal.timeout(10000)});
if(!response.ok)throw new Error('Local Keycloak administration unavailable');
const {access_token}=await response.json();
async function admin(path,{method='GET',body}={}){
  const result=await fetch(`${base}/admin/realms/propiedades-test${path}`,{method,headers:{Authorization:`Bearer ${access_token}`,...(body?{'Content-Type':'application/json'}:{})},body:body?JSON.stringify(body):undefined,signal:AbortSignal.timeout(10000)});
  if(!result.ok)throw new Error(`Local login configuration failed (${result.status})`);
  return result.status===204||result.status===201?null:result.json();
}
const existing=await admin('/clients?clientId=portal-local-login');
if(existing.length>1)throw new Error('Ambiguous login client');
const client={...(existing[0]||{}),clientId:'portal-local-login',enabled:true,publicClient:false,secret:settings.TEST_LOGIN_SECRET,standardFlowEnabled:false,directAccessGrantsEnabled:true,serviceAccountsEnabled:false};
client.attributes={...client.attributes,'access.token.lifespan':'1800','client.session.idle.timeout':'1800','client.session.max.lifespan':'1800'};
if(existing.length)await admin(`/clients/${existing[0].id}`,{method:'PUT',body:client});else await admin('/clients',{method:'POST',body:client});
const [created]=await admin('/clients?clientId=portal-local-login');
const mappers=await admin(`/clients/${created.id}/protocol-mappers/models`);
if(!mappers.some(mapper=>mapper.name==='backend-audience'))await admin(`/clients/${created.id}/protocol-mappers/models`,{method:'POST',body:{name:'backend-audience',protocol:'openid-connect',protocolMapper:'oidc-audience-mapper',config:{'included.custom.audience':'propiedades-api','access.token.claim':'true','id.token.claim':'false'}}});
const realm=await admin('');await admin('',{method:'PUT',body:{...realm,bruteForceProtected:true}});
await writeFile(url,JSON.stringify(settings,null,2),{mode:0o600});
console.log('Portal form login configured locally. No user passwords changed or credentials printed.');
