import assert from 'node:assert/strict';
import { readFile, mkdir, writeFile } from 'node:fs/promises';
import { startTestBackend } from './backend-process.mjs';

const base='http://127.0.0.1:58080';
const artifacts=new URL('../artifacts/',import.meta.url);
await mkdir(artifacts,{recursive:true});
const report={scope:'Backend integration with synthetic data; no frontend acceptance',generatedAt:new Date().toISOString(),checks:[]};
const settings=JSON.parse(await readFile(new URL('../.runtime/settings.json',import.meta.url),'utf8'));
try { await fetch(`${base}/health/live`,{signal:AbortSignal.timeout(500)}); throw new Error('Port 58080 is occupied; will not test an existing backend.'); }
catch(error) {if(error.message.startsWith('Port 58080'))throw error;}
const child=await startTestBackend();
let startupError=false;
child.on('error',()=>{startupError=true;});
// Drain output but never capture tokens/configuration in artifacts.
child.stdout.resume(); child.stderr.resume();
async function request(path,{token,method='GET',body}={}) {
  const response=await fetch(`${base}${path}`,{method,headers:{...(token?{Authorization:`Bearer ${token}`} : {}),...(body?{'Content-Type':'application/json'}:{})},body:body?JSON.stringify(body):undefined,signal:AbortSignal.timeout(10000)});
  return {status:response.status,body:await response.json()};
}
async function token(client) {
  const response=await fetch('http://127.0.0.1:58081/realms/propiedades-test/protocol/openid-connect/token',{
    method:'POST',body:new URLSearchParams({grant_type:'client_credentials',client_id:client,client_secret:settings.TEST_CLIENT_SECRET}),signal:AbortSignal.timeout(5000)
  });
  assert.equal(response.status,200);return (await response.json()).access_token;
}
async function check(name,callback) {
  try {await callback();report.checks.push({name,status:'PASS'});}
  catch(error) {report.checks.push({name,status:'FAIL',reason:error.code==='ERR_ASSERTION'?'Assertion failed':error.name});process.exitCode=1;}
}
try {
  let ready=false;
  for(let attempt=0;attempt<100;attempt++) {
    if(startupError || child.exitCode!==null) throw new Error('Backend startup failed. Check build, database and environment privately.');
    try {ready=(await request('/health/live')).status===200;}catch{}
    if(ready)break;
    await new Promise(resolve=>setTimeout(resolve,300));
  }
  assert.ok(ready,'Backend not ready');
  const writer=await token('infra-probe');
  const reader=await token('infra-reader');
  const denied=await token('infra-denied');
  const wrongAudience=await token('infra-wrong-audience');
  await check('API rejects absent, malformed and tampered tokens',async()=>{
    assert.equal((await request('/api/v1/me')).status,401);
    assert.equal((await request('/api/v1/me',{token:'not-a-jwt'})).status,401);
    const pieces=writer.split('.');
    pieces[1]=Buffer.from(JSON.stringify({sub:'forged',iss:'wrong',exp:9999999999,aud:'propiedades-api'})).toString('base64url');
    assert.equal((await request('/api/v1/me',{token:pieces.join('.')})).status,401);
  });
  await check('API verifies audience and rejects other authenticated subjects',async()=>{
    assert.equal((await request('/api/v1/me',{token:wrongAudience})).status,401);
    assert.equal((await request('/api/v1/me',{token:denied})).status,403);
    assert.equal((await request('/api/v1/me',{token:reader})).status,403);
    assert.equal((await request('/api/v1/propiedades',{token:reader,method:'POST',body:{nombre:'No permitido'}})).status,403);
  });
  let building,property,property2,tenant,tenant2;
  await check('Backend creates building before its properties and tenants',async()=>{
    assert.equal((await request('/api/v1/propiedades',{token:writer,method:'POST',body:{nombre:'Vivienda sin edificio'}})).status,400);
    assert.equal((await request('/api/v1/propiedades',{token:writer,method:'POST',body:{nombre:'Vivienda API',edificioId:'missing'}})).status,400);
    const createdBuilding=await request('/api/v1/edificios',{token:writer,method:'POST',body:{nombre:'Residencial API'}});
    assert.equal(createdBuilding.status,200);building=createdBuilding.body;
    const result=await request('/api/v1/propiedades',{token:writer,method:'POST',body:{nombre:'Vivienda sintética API',edificioId:building.id}});
    assert.equal(result.status,200);property=result.body;
    const created=await request('/api/v1/inquilinos',{token:writer,method:'POST',body:{nombre:'Persona sintética API',propiedadId:property.id,renta:'450.1',dni:'PRUEBA',fianza:'0.00',inicio:'2020-01-01'}});
    assert.equal(created.status,200);tenant=created.body;assert.equal(tenant.renta,'450.10');
    assert.equal((await request(`/api/v1/inquilinos/${tenant.id}`,{token:writer})).body.renta,'450.10');
  });
  await check('Backend rejects invalid money and missing property references',async()=>{
    assert.equal((await request('/api/v1/inquilinos',{token:writer,method:'POST',body:{nombre:'Inválido',propiedadId:property.id,renta:'0.001'}})).status,400);
    assert.equal((await request('/api/v1/inquilinos',{token:writer,method:'POST',body:{nombre:'Inválido',propiedadId:'missing'}})).status,400);
    assert.equal((await request('/api/v1/inquilinos',{token:writer,method:'POST',body:{nombre:'Segundo inquilino',propiedadId:property.id,dni:'PRUEBA',renta:'0.00',fianza:'0.00',inicio:'2020-01-01'}})).status,409);
    property2=(await request('/api/v1/propiedades',{token:writer,method:'POST',body:{nombre:'Vivienda secundaria API',edificioId:building.id}})).body;
    tenant2=(await request('/api/v1/inquilinos',{token:writer,method:'POST',body:{nombre:'Persona secundaria API',propiedadId:property2.id,renta:'600.00',dni:'PRUEBA',fianza:'0.00',inicio:'2020-01-01'}})).body;
    assert.equal((await request(`/api/v1/inquilinos/${tenant2.id}`,{token:writer,method:'PATCH',body:{version:tenant2.version,propiedadId:property.id}})).status,409);
  });
  await check('Concurrent versions reject stale changes and preserve accepted change',async()=>{
    const updated=await request(`/api/v1/propiedades/${property.id}`,{token:writer,method:'PATCH',body:{version:property.version,nombre:'Actualizado'}});
    assert.equal(updated.status,200);assert.equal(updated.body.version,2);
    assert.equal((await request(`/api/v1/propiedades/${property.id}`,{token:writer,method:'PATCH',body:{version:property.version,nombre:'Obsoleto'}})).status,409);
    assert.equal((await request(`/api/v1/propiedades/${property.id}`,{token:writer})).body.nombre,'Actualizado');
  });
  await check('Payment state is derived from due and paid amounts',async()=>{
    let list=await request('/api/v1/pagos?mes=2026-02',{token:writer});
    const initialPayment=list.body.data.find(item=>item.inquilinoId===tenant.id);
    assert.equal(initialPayment.estado,'pendiente');assert.equal(initialPayment.amountDue,'450.10');assert.equal(initialPayment.amountPaid,null);
    const unpaid=await request(`/api/v1/inquilinos/${tenant.id}/pagos/2026-02`,{token:writer,method:'PUT',body:{estado:'pagado',amountPaid:'0.00',version:0}});
    assert.equal(unpaid.status,200);assert.equal(unpaid.body.estado,'pendiente');assert.equal(unpaid.body.amountDue,'450.10');
    const payment=await request(`/api/v1/inquilinos/${tenant.id}/pagos/2026-02`,{token:writer,method:'PUT',body:{estado:'pendiente',amountPaid:'200.00',nota:'Sintético',version:1}});
    assert.equal(payment.status,200);assert.equal(payment.body.estado,'parcial');assert.equal(payment.body.amountDue,'450.10');assert.equal(payment.body.amountPaid,'200.00');
    const settled=await request(`/api/v1/inquilinos/${tenant2.id}/pagos/2026-02`,{token:writer,method:'PUT',body:{estado:'pendiente',amountDue:'600.00',amountPaid:'600.00',version:0}});
    assert.equal(settled.status,200);assert.equal(settled.body.estado,'pagado');
    assert.equal((await request(`/api/v1/inquilinos/${tenant.id}/pagos/2026-02`,{token:writer,method:'PUT',body:{estado:'pagado',version:0}})).status,409);
    list=await request('/api/v1/pagos?mes=2026-02',{token:writer});
    assert.equal(list.body.data.find(item=>item.inquilinoId===tenant.id).estado,'parcial');
    const summary=await request('/api/v1/dashboard?mes=2026-02',{token:writer});
    assert.equal(summary.status,200);assert.equal(summary.body.cobradoReal,null);assert.ok(summary.body.parciales>=1);
  });
  await check('Payment amounts persist exactly and summaries separate unknowns',async()=>{
    const path=`/api/v1/inquilinos/${tenant.id}/pagos/2026-03`;
    let saved=await request(path,{token:writer,method:'PUT',body:{estado:'parcial',amountDue:'600.00',amountPaid:'250.00',version:0}});
    assert.equal(saved.status,200);assert.equal(saved.body.balance,'350.00');
    const version=saved.body.version;
    const list=await request('/api/v1/pagos?mes=2026-03',{token:writer});
    assert.equal(list.body.data.find(p=>p.inquilinoId===tenant.id).amountPaid,'250.00');
    saved=await request(path,{token:writer,method:'PUT',body:{estado:'parcial',amountDue:'600.00',amountPaid:'250.00',version}});
    assert.equal(saved.status,200);assert.equal(saved.body.amountPaid,'250.00');
    assert.equal((await request(path,{token:writer,method:'PUT',body:{estado:'parcial',amountPaid:'250.00',version:0}})).status,409);
    assert.equal((await request(path,{token:writer,method:'PUT',body:{estado:'parcial',balance:'0.00',version:saved.body.version}})).status,400);
    assert.equal((await request(path,{token:writer,method:'PUT',body:{estado:'parcial',amountPaid:250,version:saved.body.version}})).status,400);
    const summary=await request('/api/v1/dashboard?mes=2026-03',{token:writer});
    assert.equal(summary.body.knownAmountPaid,'250.00');
    const monthly=await request('/api/v1/pagos?mes=2026-03',{token:writer});
    assert.equal(summary.body.knownBalance,(monthly.body.data.reduce((total,p)=>total+Math.round(Number(p.balance)*100),0)/100).toFixed(2));
    assert.equal(summary.body.unknownPaidCount,0);assert.equal(summary.body.complete,true);
    const historical=await request('/api/v1/pagos?mes=2026-02',{token:writer});
    assert.equal(historical.body.data.find(p=>p.inquilinoId===tenant.id).balance,'250.10');
    const decimal=await request(`/api/v1/inquilinos/${tenant.id}/pagos/2026-04`,{token:writer,method:'PUT',body:{estado:'parcial',amountDue:'0.30',amountPaid:'0.10',version:0}});
    assert.equal(decimal.body.balance,'0.20');
    assert.equal((await request(`/api/v1/inquilinos/${tenant2.id}?version=1`,{token:writer,method:'DELETE'})).status,200);
  });
  await check('Other authenticated subject cannot read or mutate business resources',async()=>{
    for(const path of ['/api/v1/me','/api/v1/propiedades','/api/v1/dashboard?mes=2026-03','/api/v1/pagos?mes=2026-03',`/api/v1/inquilinos/${tenant.id}`]) assert.equal((await request(path,{token:reader})).status,403);
    assert.equal((await request(`/api/v1/inquilinos/${tenant.id}/pagos/2026-03`,{token:reader,method:'PUT',body:{estado:'pagado',version:2}})).status,403);
    assert.equal((await request('/api/v1/pagos?mes=2026-03',{token:writer})).body.data.find(p=>p.inquilinoId===tenant.id).amountPaid,'250.00');
  });
  await check('Archive protects active property dependencies and preserves tenant history',async()=>{
    assert.equal((await request(`/api/v1/propiedades/${property.id}?version=2`,{token:writer,method:'DELETE'})).status,409);
    assert.equal((await request(`/api/v1/inquilinos/${tenant.id}?version=1`,{token:writer,method:'DELETE'})).status,200);
    assert.equal((await request(`/api/v1/inquilinos/${tenant.id}`,{token:writer})).status,404);
    assert.equal((await request(`/api/v1/propiedades/${property.id}?version=2`,{token:writer,method:'DELETE'})).status,200);
    assert.equal((await request(`/api/v1/propiedades/${property2.id}?version=1`,{token:writer,method:'DELETE'})).status,200);
    assert.equal((await request(`/api/v1/edificios/${building.id}?version=1`,{token:writer,method:'DELETE'})).status,200);
  });
} catch(error) {
  report.checks.push({name:'Integration setup',status:'FAIL',reason:error.message==='Backend startup failed. Check build, database and environment privately.'?error.message:error.name});process.exitCode=1;
} finally {
  child.kill();
  await writeFile(new URL(`api-${report.generatedAt.replaceAll(':','-')}.json`,artifacts),JSON.stringify(report,null,2));
  for(const result of report.checks)console.log(`${result.status}: ${result.name}`);
}
