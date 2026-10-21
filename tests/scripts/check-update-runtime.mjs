import { spawn, spawnSync } from 'node:child_process';
import { writeFileSync } from 'node:fs';
import { mkdir, readFile, writeFile, copyFile, access } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import http from 'node:http';
import net from 'node:net';
import { generateKeyPairSync, sign, randomUUID, randomBytes, createHash } from 'node:crypto';
import os from 'node:os';
import assert from 'node:assert/strict';

const repo=fileURLToPath(new URL('../../',import.meta.url));
const runId=`runtime-${new Date().toISOString().replaceAll(/[:.]/g,'-')}-${randomUUID().slice(0,8)}`;
const run=path.join(repo,'tests/artifacts/updates',runId);
await mkdir(run,{recursive:true});
const report={runId,createdUtc:new Date().toISOString(),scope:'WP-007 isolated native PostgreSQL and local signed identity fixture',tests:['TEST-025','TEST-029','TEST-032','TEST-033'],familyStatus:'Not Run - partial execution, no service/reboot/portal acceptance',results:[]};
function native(executable,args,env={}) {
  const background=path.basename(executable)==='pg_ctl.exe' && args.includes('start');
  const result=spawnSync(executable,args,{cwd:repo,encoding:'utf8',timeout:60000,windowsHide:true,stdio:background?'ignore':'pipe',env:{...process.env,...env}});
  if(result.error || result.status!==0) {
    report.failedCommand=path.basename(executable);
    writeFileSync(path.join(run,'native-failure.private.log'),`${result.error?.code||''}\n${result.stdout||''}\n${result.stderr||''}`);
    throw new Error(`Native test command failed: ${path.basename(executable)}`);
  }
  return result.stdout?.trim()??'';
}
function ps(script,args=[]) {return native('powershell.exe',['-NoProfile','-ExecutionPolicy','Bypass','-File',path.join(repo,'tests/scripts',script),...args]);}
function check(name,action){return Promise.resolve().then(action).then(()=>report.results.push({variant:name,status:'PASS'})).catch(async error=>{report.results.push({variant:name,status:'FAIL'});report.status='FAIL';await writeFile(path.join(run,'report.json'),JSON.stringify(report,null,2));throw error;});}
async function freePort() {const s=net.createServer();await new Promise(r=>s.listen(0,'127.0.0.1',r));const p=s.address().port;await new Promise(r=>s.close(r));return p;}
const binary=path.join(run,'propiedades-backend.exe');
await copyFile(path.join(repo,'backend/target/debug/propiedades-backend.exe'),binary);
const info=JSON.parse(native(binary,['--release-info'],{DATABASE_URL:'invalid-no-connection-expected',KEYCLOAK_ISSUER:'invalid'}));
report.releaseInfo=info;
report.executableSha256=createHash('sha256').update(await readFile(binary)).digest('hex');
await check('release-info works without database or authentication configuration',()=>{assert.equal(info.product,'aelium-propiedades');assert.ok(info.releaseId);assert.deepEqual(info.migrations.map(m=>m.version),['1','2','3','4']);});
const initial=path.join(run,'installation');await mkdir(path.join(initial,'config'),{recursive:true});
await writeFile(path.join(initial,'config/settings.json'),JSON.stringify({Format:1,Complete:false}));
await check('real compiled candidate metadata is checked by update package builder',async()=>{
  const definition={format:2,kind:'application-update',product:'aelium-propiedades',platform:'windows-x64',releaseId:info.releaseId,buildId:info.buildId,apiContract:info.apiContract,
    acceptedSources:[{sourceId:'fixture-original',evidence:'fixture-review'}],files:[{path:'bin/propiedades-backend.exe',target:'release'}],
    dependencies:['postgresql','keycloak','java','winsw','cloudflared','vc-runtime'].map(id=>({id,version:'synthetic-declaration',files:[{path:'dependencies/'+id+'.fixture',sha256:'0'.repeat(64)}]})),
    schemaBefore:info.migrations,schemaAfter:info.migrations,migrations:[],supportedFrontends:[{id:'fixture-web',apiContract:info.apiContract,evidence:'fixture-contract'}],
    recovery:{sourceIds:['fixture-original'],schema:info.migrations,checks:['version','identity','read','write','frontend','cleanup'],preserve:['application','schema','data','identity','config','attachments','services']}};
  const content=path.join(run,'package-content');await mkdir(path.join(content,'bin'),{recursive:true});await copyFile(binary,path.join(content,'bin/propiedades-backend.exe'));
  const definitionPath=path.join(run,'real-definition.json');await writeFile(definitionPath,JSON.stringify(definition));
  native('powershell.exe',['-NoProfile','-ExecutionPolicy','Bypass','-File',path.join(repo,'deploy/windows/Build-UpdatePackage.ps1'),'-ContentRoot',content,'-DefinitionPath',definitionPath,'-OutputArchive',path.join(run,'real-candidate.zip')]);
});
const postgresBin=ps('prepare-native-update-test.ps1',['-RunDirectory',run]);
const cluster=path.join(run,'cluster');const pgPort=await freePort();const apiPort=await freePort();
report.environment={os:process.platform,osRelease:os.release(),architecture:process.arch,postgresPort:pgPort,apiPort,postgres:'conserved native PostgreSQL ZIP, isolated cluster',identity:'in-memory RSA signed local fixture; no real Keycloak'};
const pgctl=path.join(postgresBin,'pg_ctl.exe');const psql=path.join(postgresBin,'psql.exe');
let postgresStarted=false;let api;
const {privateKey,publicKey}=generateKeyPairSync('rsa',{modulusLength:2048});
const jwk={...publicKey.export({format:'jwk'}),kid:'update-test',use:'sig',alg:'RS256'};
const issuerServer=http.createServer((req,res)=>{res.setHeader('content-type','application/json');res.end(JSON.stringify({keys:[jwk]}));});
await new Promise(r=>issuerServer.listen(0,'127.0.0.1',r));
const issuer=`http://127.0.0.1:${issuerServer.address().port}/realms/update-test`;
function token(sub) {const head=Buffer.from(JSON.stringify({alg:'RS256',kid:'update-test'})).toString('base64url');const body=Buffer.from(JSON.stringify({iss:issuer,aud:'propiedades-api',sub,exp:Math.floor(Date.now()/1000)+3600})).toString('base64url');const input=`${head}.${body}`;return `${input}.${sign('RSA-SHA256',Buffer.from(input),privateKey).toString('base64url')}`;}
const owner=token('synthetic-owner');const other=token('synthetic-other');
const env={DATABASE_URL:`postgres://wp007_test@127.0.0.1:${pgPort}/postgres`,KEYCLOAK_ISSUER:issuer,KEYCLOAK_AUDIENCE:'propiedades-api',KEYCLOAK_ALLOWED_SUBJECT:'synthetic-owner',KEYCLOAK_LOGIN_CLIENT_ID:'',BACKEND_BIND:`127.0.0.1:${apiPort}`};
function sql(statement){return native(psql,['-X','-h','127.0.0.1','-p',String(pgPort),'-U','wp007_test','-d','postgres','-v','ON_ERROR_STOP=1','-At','-c',statement]);}
async function stopApi() {if(api && api.exitCode===null){api.kill();await new Promise(r=>api.once('exit',r));}api=undefined;}
async function startApi(args=['--serve','--no-migrate','--install-root',initial]) {
  api=spawn(binary,args,{cwd:repo,env:{...process.env,...env},windowsHide:true,stdio:['ignore','pipe','pipe']});
  let error=false;api.on('error',()=>{error=true;});
  for(let i=0;i<80;i++){if(error || api.exitCode!==null) throw new Error('Isolated API failed to start');try{const r=await fetch(`http://127.0.0.1:${apiPort}/health/live`,{signal:AbortSignal.timeout(300)});if(r.ok)return;}catch{}await new Promise(r=>setTimeout(r,100));}
  throw new Error('Isolated API readiness timed out');
}
async function request(method,url,body,headers={},bearer=owner){return fetch(`http://127.0.0.1:${apiPort}${url}`,{method,headers:{authorization:`Bearer ${bearer}`,...(body?{'content-type':'application/json'}:{}),...headers},...(body?{body:JSON.stringify(body)}:{}),signal:AbortSignal.timeout(3000)});}
const op={format:1,operationId:'runtime-operation',phase:'Preflight',sourceReleaseId:info.releaseId,targetReleaseId:info.releaseId,backupReference:null,checksPassed:false,step:'test',services:[]};
async function publish(phase,checks=false) {op.phase=phase;op.checksPassed=checks;const input=path.join(run,'operation-input.json');await writeFile(input,JSON.stringify(op));ps('publish-update-test-operation.ps1',['-InstallationRoot',initial,'-RecordPath',input]);}
try {
  native(path.join(postgresBin,'initdb.exe'),['-D',cluster,'-U','wp007_test','--auth-local=trust','--auth-host=trust','--encoding=UTF8']);
  postgresStarted=true;
  native(pgctl,['-D',cluster,'-l',path.join(run,'postgres-private.log'),'-o',`-h 127.0.0.1 -p ${pgPort}`,'-w','start']);
  await check('serve with missing history fails without creating migrations table',async()=>{const r=spawnSync(binary,['--serve','--no-migrate','--initial-layout','--install-root',initial],{cwd:repo,env:{...process.env,...env},encoding:'utf8',timeout:10000,windowsHide:true});assert.notEqual(r.status,0);assert.equal(sql("SELECT to_regclass('public._sqlx_migrations') IS NULL"),'t');});
  await check('explicit initial bootstrap creates expected embedded schema',()=>{native(binary,['--migrate-only','--bootstrap','--install-root',initial],env);assert.equal(sql('SELECT count(*) FROM _sqlx_migrations WHERE success'),String(info.migrations.length));});
  await writeFile(path.join(initial,'config/settings.json'),JSON.stringify({Format:1,Complete:true}));
  await check('bootstrap rejects a completed installation',()=>{const r=spawnSync(binary,['--migrate-only','--bootstrap','--install-root',initial],{env:{...process.env,...env},encoding:'utf8',timeout:10000,windowsHide:true});assert.notEqual(r.status,0);});
  await publish('Preflight');await publish('Quiescing');await publish('BackingUp');await publish('Applying');
  await check('explicit maintenance migration checks history and exits without serving',()=>{native(binary,['--migrate-only','--install-root',initial],env);assert.equal(sql('SELECT count(*) FROM _sqlx_migrations'),String(info.migrations.length));});
  await publish('Verifying');await startApi();
  await check('version endpoint requires authentication',async()=>{const r=await fetch(`http://127.0.0.1:${apiPort}/api/v1/system/version`);assert.equal(r.status,401);});
  await check('diagnostic headers never authorize another signed identity',async()=>{const r=await request('POST','/api/v1/propiedades',{nombre:'deny'},{'x-aelium-capability':'a'.repeat(64)},other);assert.equal(r.status,403);});
  const version=await (await request('GET','/api/v1/system/version')).json();
  await check('protected metadata describes actual build and blocked writes',()=>{assert.equal(version.releaseId,info.releaseId);assert.equal(version.operational,false);assert.equal(version.capabilities.write,false);assert.equal(version.phase,'Verifying');});
  await check('all ordinary write routes return maintenance before persistence',async()=>{for(const [method,url,body] of [['POST','/api/v1/propiedades',{nombre:'blocked',recinto:'Synthetic complex'}],['PATCH','/api/v1/propiedades/real',{nombre:'blocked',recinto:'Synthetic complex',version:1}],['DELETE','/api/v1/propiedades/real?version=1'],['PUT','/api/v1/inquilinos/real/pagos/2026-10',{estado:'pagado'}]]){const r=await request(method,url,body);assert.equal(r.status,503);assert.equal((await r.json()).error.code,'MAINTENANCE_IN_PROGRESS');}assert.equal(sql('SELECT count(*) FROM entities'),'0');});
  const buildingFixture={collection:'edificios',id:'maintenance-runtime-operation-building'};
  const propertyFixture={collection:'propiedades',id:'maintenance-runtime-operation-property'};
  const fixtures=[buildingFixture,propertyFixture];
  const nonce=randomBytes(32).toString('hex');
  await writeFile(path.join(initial,'maintenance/diagnostic.json'),JSON.stringify({format:1,operationId:op.operationId,instanceId:version.instanceId,nonce,fixtures}));
  const cap={'x-aelium-operation':op.operationId,'x-aelium-capability':nonce,'x-aelium-fixture':buildingFixture.id};
  await check('capability creates a building before its property and updates the synthetic record',async()=>{let r=await request('POST','/api/v1/edificios',{nombre:'Synthetic maintenance building'},cap);assert.equal(r.status,200);assert.equal((await r.json()).id,buildingFixture.id);cap['x-aelium-fixture']=propertyFixture.id;r=await request('POST','/api/v1/propiedades',{nombre:'Synthetic maintenance home',edificioId:buildingFixture.id},cap);assert.equal(r.status,200);assert.equal((await r.json()).id,propertyFixture.id);r=await request('GET',`/api/v1/propiedades/${propertyFixture.id}`,null,cap);assert.equal(r.status,200);r=await request('PATCH',`/api/v1/propiedades/${propertyFixture.id}`,{nombre:'Updated synthetic home',version:1},cap);assert.equal(r.status,200);});
  await check('capability cannot affect real ID wrong operation or missing nonce',async()=>{for(const headers of [{...cap,'x-aelium-operation':'other'},{...cap,'x-aelium-capability':'b'.repeat(64)},{'x-aelium-operation':op.operationId}])assert.equal((await request('POST','/api/v1/propiedades',{nombre:'deny'},headers)).status,503);assert.equal((await request('PATCH','/api/v1/propiedades/real',{nombre:'deny',version:1},cap)).status,503);});
  await check('diagnostic cleanup removes home and building entities plus audit residues',async()=>{let r=await request('DELETE',`/api/v1/propiedades/${propertyFixture.id}?version=2`,null,cap);assert.equal(r.status,200);cap['x-aelium-fixture']=buildingFixture.id;r=await request('DELETE',`/api/v1/edificios/${buildingFixture.id}?version=1`,null,cap);assert.equal(r.status,200);assert.equal(sql('SELECT count(*) FROM entities'),'0');assert.equal(sql('SELECT count(*) FROM audit_events'),'0');});
  await check('invalid persistent record blocks API and revokes active diagnostic capability',async()=>{const opPath=path.join(initial,'maintenance/operation.json');const saved=await readFile(opPath);await writeFile(opPath,'invalid');assert.equal((await request('POST','/api/v1/propiedades',{nombre:'deny'})).status,503);await writeFile(opPath,saved);assert.equal((await request('POST','/api/v1/propiedades',{nombre:'deny'},cap)).status,503);assert.equal(sql('SELECT count(*) FROM entities'),'0');});
  await stopApi();await startApi();
  await check('API restart invalidates old diagnostic capability',async()=>{assert.equal((await request('POST','/api/v1/propiedades',{nombre:'deny'},cap)).status,503);});
  await publish('Committing',true);await publish('Committed',true);
  await check('verified committed state reopens normal authenticated writes',async()=>{const building=await request('POST','/api/v1/edificios',{nombre:'Synthetic normal building'});assert.equal(building.status,200);const r=await request('POST','/api/v1/propiedades',{nombre:'Synthetic normal fixture',edificioId:(await building.json()).id});assert.equal(r.status,200);assert.equal((await (await request('GET','/api/v1/system/version')).json()).operational,true);});
  await check('native PowerShell exclusive gate blocks Rust HTTP writes without persistence',async()=>{
    const holder=spawn('powershell.exe',['-NoProfile','-ExecutionPolicy','Bypass','-File',path.join(repo,'tests/scripts/hold-update-test-gate.ps1'),'-InstallationRoot',initial],{windowsHide:true,stdio:'ignore'});
    const exited=new Promise(resolve=>holder.once('exit',resolve));
    try {
      let ready=false;
      for(let i=0;i<100;i++){try{await access(path.join(initial,'maintenance/gate-ready.fixture'));ready=true;break;}catch{}if(holder.exitCode!==null)break;await new Promise(r=>setTimeout(r,50));}
      assert.ok(ready);assert.equal((await request('POST','/api/v1/propiedades',{nombre:'blocked by native gate'})).status,503);assert.equal(sql('SELECT count(*) FROM entities'),'2');
    }finally{await writeFile(path.join(initial,'maintenance/gate-release.fixture'),'release');await exited;}
  });
  await stopApi();sql("UPDATE _sqlx_migrations SET checksum=decode(repeat('00',48),'hex') WHERE version=1");
  await check('wrong schema checksum prevents startup without altering history',()=>{const r=spawnSync(binary,['--serve','--no-migrate','--install-root',initial],{env:{...process.env,...env},encoding:'utf8',timeout:10000,windowsHide:true});assert.notEqual(r.status,0);assert.equal(sql("SELECT encode(checksum,'hex')=repeat('00',48) FROM _sqlx_migrations WHERE version=1"),'t');});
  report.status='PASS - partial scope';
} catch {report.status='FAIL';process.exitCode=1;console.error('Isolated update runtime checks failed; inspect sanitized report and local fixtures.');}
finally {
  await stopApi();await new Promise(r=>issuerServer.close(r));
  if(postgresStarted){try{assert.ok(cluster.startsWith(path.join(repo,'tests/artifacts/updates')+path.sep));native(pgctl,['-D',cluster,'-m','fast','-w','stop']);}catch{report.cleanup='Owned PostgreSQL shutdown failed';process.exitCode=1;}}
  report.finishedUtc=new Date().toISOString();report.limitations=['Mock signed identity, not real Keycloak or portal','No client services modified; no OS reboot or backup/recovery acceptance','Cluster and diagnostic fixture files are private synthetic artifacts; publish only sanitized report'];
  await writeFile(path.join(run,'report.json'),JSON.stringify(report,null,2));
  console.log(`${report.results.length} runtime checks PASS; result: ${report.status}; evidence: tests/artifacts/updates/${runId}/report.json`);
}
