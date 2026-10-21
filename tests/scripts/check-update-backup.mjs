import {spawnSync} from 'node:child_process';
import {mkdir,writeFile,readFile,cp} from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {randomUUID,createHash} from 'node:crypto';
import net from 'node:net';
import assert from 'node:assert/strict';
const repo=fileURLToPath(new URL('../../',import.meta.url));
const runId=`backup-${new Date().toISOString().replaceAll(/[:.]/g,'-')}-${randomUUID().slice(0,8)}`;
const run=path.join(repo,'tests/artifacts/updates',runId);await mkdir(run,{recursive:true});
const report={runId,createdUtc:new Date().toISOString(),scope:'WP-008 native isolated backup/recovery; synthetic identity data, no client services',results:[]};
function native(exe,args,{expectFailure=false,background=false}={}){const r=spawnSync(exe,args,{cwd:repo,encoding:'utf8',timeout:90000,windowsHide:true,stdio:background?'ignore':'pipe'});if(r.error||(!expectFailure&&r.status!==0)){writeFile(path.join(run,'failure.private.log'),`${r.error?.message??''}\n${r.stdout??''}\n${r.stderr??''}`);throw new Error(`Native fixture failed: ${path.basename(exe)}`);}return r;}
function ps(script,args=[],options){return native('powershell.exe',['-NoProfile','-ExecutionPolicy','Bypass','-File',path.join(repo,'tests/scripts',script),...args],options);}
async function check(name,action){try{await action();report.results.push({variant:name,status:'PASS'});}catch(e){report.results.push({variant:name,status:'FAIL'});throw e;}}
async function port(){const s=net.createServer();await new Promise(r=>s.listen(0,'127.0.0.1',r));const p=s.address().port;await new Promise(r=>s.close(r));return p;}
const pgPort=await port(),verifyPort=await port();let started=false;let pg;
const installation=path.join(run,'installation');const cluster=path.join(run,'cluster');
const op={format:1,operationId:'backup-test-operation',phase:'Preflight',sourceReleaseId:'fixture-original',targetReleaseId:'fixture-new',backupReference:null,checksPassed:false,step:'test',services:[]};
async function publish(phase){op.phase=phase;const opPath=path.join(installation,'maintenance/operation.json');try{op.backupReference=JSON.parse(await readFile(opPath)).backupReference;}catch{}const input=path.join(run,'operation-input.json');await writeFile(input,JSON.stringify(op));ps('publish-update-test-operation.ps1',['-InstallationRoot',installation,'-RecordPath',input]);}
function exercise(action,options){return ps('exercise-update-backup.ps1',['-InstallationRoot',installation,'-Action',action,'-VerificationPort',String(verifyPort)],options);}
function sql(statement,db='postgres'){return native(path.join(pg,'psql.exe'),['-X','-h','127.0.0.1','-p',String(pgPort),'-U','postgres','-d',db,'-At','-v','ON_ERROR_STOP=1','-c',statement]).stdout.trim();}
const backup=path.join(installation,'backups',op.operationId);
try{
  const sourceBin=ps('prepare-native-update-test.ps1',['-RunDirectory',run]).stdout.trim();
  await mkdir(installation,{recursive:true});await cp(path.dirname(sourceBin),path.join(installation,'postgresql'),{recursive:true});pg=path.join(installation,'postgresql/bin');
  for(const d of ['config','scripts','bin','services','keycloak/conf','attachments/documents'])await mkdir(path.join(installation,d),{recursive:true});
  await writeFile(path.join(installation,'config/settings.json'),JSON.stringify({Format:1,Complete:true,PgPort:pgPort,PostgresPassword:''}));
  for(const [f,data] of [['config/api.json','private-fixture-config'],['config/tunnel-token.txt','synthetic-token'],['scripts/run-api.ps1','previous-launcher'],['bin/propiedades-backend.exe','previous-app-fixture'],['services/AeliumAPI.xml','previous-service-fixture'],['keycloak/conf/keycloak.conf','previous-identity-config'],['attachments/documents/fixture.bin',Buffer.from([0,1,255,0,42])]])await writeFile(path.join(installation,f),data);
  native(path.join(pg,'initdb.exe'),['-D',cluster,'-U','postgres','--auth-local=trust','--auth-host=trust','--encoding=UTF8']);started=true;
  native(path.join(pg,'pg_ctl.exe'),['-D',cluster,'-l',path.join(run,'postgres.private.log'),'-o',`-h 127.0.0.1 -p ${pgPort}`,'-w','start'],{background:true});
  sql("CREATE ROLE propiedades LOGIN; CREATE ROLE keycloak LOGIN;");
  sql('CREATE DATABASE propiedades OWNER propiedades');sql('CREATE DATABASE keycloak OWNER keycloak');
  sql("CREATE TABLE synthetic_property(id text PRIMARY KEY, amount numeric, attachment bytea); CREATE TABLE synthetic_tenant(id text PRIMARY KEY, property_id text REFERENCES synthetic_property(id)); INSERT INTO synthetic_property VALUES('known',123.45,decode('0001ff002a','hex')),('historic-null',NULL,NULL); INSERT INTO synthetic_tenant VALUES('tenant','known'); ALTER TABLE synthetic_property OWNER TO propiedades; ALTER TABLE synthetic_tenant OWNER TO propiedades; CREATE SEQUENCE synthetic_sequence; SELECT nextval('synthetic_sequence');",'propiedades');
  sql("CREATE TABLE synthetic_identity(id text PRIMARY KEY, subject text, password_hash text); INSERT INTO synthetic_identity VALUES('user','unchanged-owner','private-synthetic-hash'); ALTER TABLE synthetic_identity OWNER TO keycloak;",'keycloak');
  sql("CREATE TABLE synthetic_column_history(id text PRIMARY KEY, obsolete text, retained text NOT NULL); ALTER TABLE synthetic_column_history DROP COLUMN obsolete; INSERT INTO synthetic_column_history VALUES('history','preserved'); ALTER TABLE synthetic_column_history OWNER TO keycloak;",'keycloak');
  await publish('Preflight');await publish('Quiescing');await publish('BackingUp');
  await check('captures both databases configuration application attachment and ACL inventory',()=>{const result=JSON.parse(exercise('capture').stdout.trim());assert.equal(result.status,'BackupCaptured');});
  await check('existing backup cannot be overwritten',()=>assert.notEqual(exercise('capture',{expectFailure:true}).status,0));
  await check('captured backup is not considered restored verification',()=>{const result=JSON.parse(exercise('inspect').stdout.trim());assert.equal(result.verified,false);assert.equal(result.databases.length,2);assert.ok(result.files>=10);});
  await publish('Recovering');
  await check('unverified backup cannot restore live databases',()=>assert.notEqual(exercise('restore',{expectFailure:true}).status,0));
  // Test a new operation phase record on the same fixture after this guarded
  // refusal; production transition backwards is intentionally unavailable.
  op.phase='BackingUp';await writeFile(path.join(installation,'maintenance/operation.json'),JSON.stringify(op));
  await check('fingerprint mismatch stays blocked and exports metadata counts without private values',async()=>{
    const manifestPath=path.join(backup,'backup.private.json');const original=await readFile(manifestPath);
    try{
      // Preserve PostgreSQL int64 sequence limits; a JS JSON round trip would
      // round them and introduce an unrelated sequence discrepancy.
      const modified=original.toString().replace(/("structure"\s*:\s*")[a-f0-9]+"/,'$1deliberately-invalid"');
      assert.notEqual(modified,original.toString());await writeFile(manifestPath,modified);
      assert.notEqual(exercise('verify',{expectFailure:true}).status,0);
      const diagnosis=JSON.parse(await readFile(path.join(installation,'maintenance/backup-validation.json')));
      assert.equal(diagnosis.stage,'compare-fingerprint');assert.equal(diagnosis.comparison.structureEqual,false);
      assert.equal(diagnosis.comparison.structureDetails.missingCount,0);
      assert.deepEqual(diagnosis.comparison.structureDetails.changedFields,[]);
      assert.equal(diagnosis.comparison.columnDetails.missingCount,0);
      assert.deepEqual(diagnosis.comparison.columnDetails.changedFields,[]);
      assert.equal(JSON.parse(await readFile(manifestPath)).verified,false);
      assert.ok(!JSON.stringify(diagnosis).includes('private-synthetic-hash'));
    }finally{await writeFile(manifestPath,original);}
  });
  await check('isolated full restore checks rows nulls relationships sequences identity and roles',()=>{const result=JSON.parse(exercise('verify').stdout.trim());assert.equal(result.status,'BackupRestoreVerified');});
  await check('logical restore accepts historical dropped-column gaps without changing live column positions',()=>{
    assert.equal(sql("SELECT attnum FROM pg_attribute WHERE attrelid='synthetic_column_history'::regclass AND attname='retained'",'keycloak'),'3');
    assert.equal(sql('SELECT retained FROM synthetic_column_history','keycloak'),'preserved');
  });
  await check('logical column fingerprint still rejects a real nullability change',()=>assert.equal(JSON.parse(exercise('column-check').stdout.trim()).status,'ColumnConstraintChangeDetected'));
  await check('verification does not change live data or roles',()=>{assert.equal(sql('SELECT amount::text FROM synthetic_property WHERE id=\'known\'','propiedades'),'123.45');assert.equal(sql('SELECT subject FROM synthetic_identity','keycloak'),'unchanged-owner');assert.equal(sql("SELECT count(*) FROM pg_roles WHERE rolname='aelium_verifier'"),'0');});
  const originalDump=await readFile(path.join(backup,'propiedades.dump'));
  await writeFile(path.join(backup,'propiedades.dump'),Buffer.from('corrupt'));
  await check('corrupt dump is rejected before recovery changes',()=>assert.notEqual(exercise('inspect',{expectFailure:true}).status,0));
  await writeFile(path.join(backup,'propiedades.dump'),originalDump);
  const originalCfg=await readFile(path.join(backup,'files/config/api.json'));await writeFile(path.join(backup,'files/config/api.json'),'altered');
  await check('altered configuration backup is rejected',()=>assert.notEqual(exercise('inspect',{expectFailure:true}).status,0));await writeFile(path.join(backup,'files/config/api.json'),originalCfg);
  await publish('Applying');
  sql("ALTER TABLE synthetic_property ADD COLUMN new_schema text; UPDATE synthetic_property SET amount=999 WHERE id='known'",'propiedades');sql("UPDATE synthetic_identity SET subject='damaged'",'keycloak');
  await writeFile(path.join(installation,'config/api.json'),'candidate-config');await writeFile(path.join(installation,'scripts/run-api.ps1'),'candidate-launcher');await writeFile(path.join(installation,'config/active-release.json'),'candidate-selector');await writeFile(path.join(installation,'attachments/documents/fixture.bin'),'damaged');
  await publish('Recovering');
  await check('role drift blocks automatic recovery without rewriting global roles',()=>{sql('ALTER ROLE propiedades CREATEDB');assert.notEqual(exercise('restore',{expectFailure:true}).status,0);assert.equal(sql("SELECT rolcreatedb FROM pg_roles WHERE rolname='propiedades'"),'t');sql('ALTER ROLE propiedades NOCREATEDB');});
  await check('interruption after first quarantine rename retains blocked intermediate state',()=>{assert.notEqual(exercise('interrupt-restore',{expectFailure:true}).status,0);assert.equal(sql("SELECT count(*) FROM pg_database WHERE datname='propiedades'"),'0');assert.equal(sql("SELECT count(*) FROM pg_database WHERE datname LIKE 'aelium_failed_%' AND NOT datallowconn"),'1');assert.equal(JSON.parse(requireReadOperation()).phase,'Recovering');});
  await check('repeated recovery completes interrupted swap using recorded OIDs',()=>{const result=JSON.parse(exercise('restore').stdout.trim());assert.equal(result.status,'RecoveryBaselineVerified');assert.equal(result.updateSucceeded,false);});
  await check('known amount null historical rows relationships and schema are restored',()=>{assert.equal(sql("SELECT amount::text FROM synthetic_property WHERE id='known'",'propiedades'),'123.45');assert.equal(sql("SELECT amount IS NULL FROM synthetic_property WHERE id='historic-null'",'propiedades'),'t');assert.equal(sql('SELECT property_id FROM synthetic_tenant','propiedades'),'known');assert.equal(sql("SELECT count(*) FROM information_schema.columns WHERE table_name='synthetic_property' AND column_name='new_schema'",'propiedades'),'0');assert.equal(sql("SELECT encode(attachment,'hex') FROM synthetic_property WHERE id='known'",'propiedades'),'0001ff002a');});
  await check('identity configuration launcher external attachment and absent old selector restored',async()=>{assert.equal(sql('SELECT subject FROM synthetic_identity','keycloak'),'unchanged-owner');assert.equal((await readFile(path.join(installation,'config/api.json'))).toString(),'private-fixture-config');assert.equal((await readFile(path.join(installation,'scripts/run-api.ps1'))).toString(),'previous-launcher');assert.deepEqual(await readFile(path.join(installation,'attachments/documents/fixture.bin')),Buffer.from([0,1,255,0,42]));await assert.rejects(readFile(path.join(installation,'config/active-release.json')));});
  await check('failed databases retained and deny connections without automatic deletion',()=>{assert.equal(sql("SELECT count(*) FROM pg_database WHERE datname LIKE 'aelium_failed_%' AND NOT datallowconn"),'2');});
  await check('recovery is idempotent before restoring services',()=>{assert.equal(JSON.parse(exercise('restore').stdout.trim()).status,'RecoveryBaselineVerified');assert.equal(sql("SELECT count(*) FROM pg_database WHERE datname LIKE 'aelium_failed_%'"),'2');});
  report.status='PASS - partial scope';
}catch(e){report.status='FAIL';process.exitCode=1;console.error(e.message);}
finally{if(started){try{native(path.join(pg,'pg_ctl.exe'),['-D',cluster,'-m','fast','-w','stop']);}catch{report.cleanup='Owned PostgreSQL shutdown failed';process.exitCode=1;}}report.finishedUtc=new Date().toISOString();report.limitations=['No real Keycloak, services, portal or client data','Private dumps/configuration remain local; export sanitized report only','No requirement/family acceptance or independent review'];await writeFile(path.join(run,'report.json'),JSON.stringify(report,null,2));console.log(`${report.results.filter(x=>x.status==='PASS').length} backup checks PASS; result: ${report.status}; evidence: tests/artifacts/updates/${runId}/report.json`);}
function requireReadOperation(){return native('powershell.exe',['-NoProfile','-Command',`Get-Content -LiteralPath '${path.join(installation,'maintenance/operation.json').replaceAll("'","''")}' -Raw`]).stdout.trim();}
