import {spawnSync} from 'node:child_process';
import {mkdir,writeFile} from 'node:fs/promises';
import {writeFileSync} from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import net from 'node:net';
import assert from 'node:assert/strict';
const repo=fileURLToPath(new URL('../../',import.meta.url));
const runId=`identity-policy-${new Date().toISOString().replaceAll(/[:.]/g,'-')}`;
const run=path.join(repo,'tests/artifacts/updates',runId);
await mkdir(run,{recursive:true});
await mkdir(path.join(run,'maintenance'));
const report={scope:'Native PostgreSQL conservation projection; synthetic rows, fixture profile admission, no real Keycloak/SCM or production acceptance',results:[],productionAccepted:false};
function native(exe,args,{background=false}={}){const r=spawnSync(exe,args,{cwd:repo,encoding:'utf8',timeout:90000,windowsHide:true,stdio:background?'ignore':'pipe'});if(r.error)throw r.error;return r;}
function ps(file,args=[]){const r=native('powershell.exe',['-NoProfile','-ExecutionPolicy','Bypass','-File',path.join(repo,'tests/scripts',file),...args]);if(r.status!==0)writeFileSync(path.join(run,'failure.private.log'),`${r.stdout??''}\n${r.stderr??''}`);return r;}
const server=net.createServer();await new Promise(r=>server.listen(0,'127.0.0.1',r));const port=server.address().port;await new Promise(r=>server.close(r));
let bin,started=false;
function sql(statement,database='keycloak'){const r=native(path.join(bin,'psql.exe'),['-X','-h','127.0.0.1','-p',String(port),'-U','postgres','-d',database,'-v','ON_ERROR_STOP=1','-At','-c',statement]);assert.equal(r.status,0,'Fixture SQL failed');return r.stdout.trim();}
function exercise(action){return ps('exercise-local-identity-policy.ps1',['-RunDirectory',run,'-PgBin',bin,'-PgPort',String(port),'-Action',action]);}
function check(name,mutate,expectedPass=true,restore,action='Compare'){
  try{if(mutate)sql(mutate);const r=exercise(action);assert.equal(r.status===0,expectedPass,'Unexpected conservation decision');report.results.push({name,status:'PASS'});}finally{if(restore)sql(restore);}
}
try{
  const prep=ps('prepare-native-update-test.ps1',['-RunDirectory',run]);assert.equal(prep.status,0,'Native fixture preparation failed');bin=prep.stdout.trim();
  const cluster=path.join(run,'cluster');
  assert.equal(native(path.join(bin,'initdb.exe'),['-D',cluster,'-U','postgres','--auth-local=trust','--auth-host=trust','--encoding=UTF8','--locale=C']).status,0,'initdb failed');
  assert.equal(native(path.join(bin,'pg_ctl.exe'),['-D',cluster,'-l',path.join(run,'postgres.private.log'),'-o',`-p ${port} -h 127.0.0.1`,'-w','start'],{background:true}).status,0,'Owned PostgreSQL failed to start');started=true;
  sql('CREATE DATABASE propiedades','postgres');sql('CREATE DATABASE keycloak','postgres');
  sql("CREATE TABLE entities(id text PRIMARY KEY, amount numeric); INSERT INTO entities VALUES('property',600),('historic',NULL)",'propiedades');
  sql("CREATE TABLE offline_user_session(id text PRIMARY KEY, offline_flag varchar(4), data text); CREATE TABLE offline_client_session(id text PRIMARY KEY, offline_flag varchar(4), data text); CREATE TABLE server_config(server_config_key text PRIMARY KEY,value text,version integer NOT NULL); CREATE TABLE jgroups_ping(address text PRIMARY KEY, last_update bigint); CREATE TABLE user_entity(id text PRIMARY KEY,credential text); INSERT INTO user_entity VALUES('owner','synthetic-credential'); INSERT INTO offline_user_session VALUES('online','0','runtime'),('offline','1','durable'); INSERT INTO offline_client_session SELECT * FROM offline_user_session; INSERT INTO server_config VALUES('JGROUPS_ADDRESS_SEQUENCE','10',1),('crt_jgroups','synthetic-private-certificate',0),('other','protected-config',0); INSERT INTO jgroups_ping VALUES('old-node',1)");
  assert.equal(exercise('Capture').status,0,'Baseline capture failed');
  check('unchanged full baseline passes',null);
  check('online sessions can change',"UPDATE offline_user_session SET data='new-runtime' WHERE offline_flag='0'; INSERT INTO offline_client_session VALUES('another-online','0','runtime')");
  check('discovery and monotonic node counter can change',"UPDATE jgroups_ping SET address='new-node',last_update=2; UPDATE server_config SET value='11',version=2 WHERE server_config_key='JGROUPS_ADDRESS_SEQUENCE'");
  check('production retains strict rejection',null,false,null,'ProductionCompare');
  check('offline user deletion rejected',"DELETE FROM offline_user_session WHERE id='offline'",false,"INSERT INTO offline_user_session VALUES('offline','1','durable')");
  check('offline client modification rejected',"UPDATE offline_client_session SET data='changed' WHERE id='offline'",false,"UPDATE offline_client_session SET data='durable' WHERE id='offline'");
  check('certificate modification rejected',"UPDATE server_config SET value='changed' WHERE server_config_key='crt_jgroups'",false,"UPDATE server_config SET value='synthetic-private-certificate' WHERE server_config_key='crt_jgroups'");
  check('other configuration modification rejected',"UPDATE server_config SET value='changed' WHERE server_config_key='other'",false,"UPDATE server_config SET value='protected-config' WHERE server_config_key='other'");
  check('unknown session category rejected',"INSERT INTO offline_user_session VALUES('unknown','2','unknown')",false,"DELETE FROM offline_user_session WHERE id='unknown'");
  check('counter regression rejected',"UPDATE server_config SET value='9' WHERE server_config_key='JGROUPS_ADDRESS_SEQUENCE'",false,"UPDATE server_config SET value='11' WHERE server_config_key='JGROUPS_ADDRESS_SEQUENCE'");
  check('counter deletion rejected',"DELETE FROM server_config WHERE server_config_key='JGROUPS_ADDRESS_SEQUENCE'",false,"INSERT INTO server_config VALUES('JGROUPS_ADDRESS_SEQUENCE','11',2)");
  check('protected user credential modification rejected',"UPDATE user_entity SET credential='changed'",false,"UPDATE user_entity SET credential='synthetic-credential'");
  check('runtime table schema modification rejected',"ALTER TABLE jgroups_ping ADD COLUMN unexpected text",false);
  report.status='PASS';
}catch(e){report.status='FAIL';report.failure=e.message;process.exitCode=1;}
finally{
  if(started){const r=native(path.join(bin,'pg_ctl.exe'),['-D',path.join(run,'cluster'),'-m','fast','-w','stop']);if(r.status!==0){report.cleanup='Owned PostgreSQL shutdown failed';process.exitCode=1;}}
  await writeFile(path.join(run,'report.json'),JSON.stringify(report,null,2));
  console.log(`${report.results.length} identity-policy checks PASS; ${report.status}; tests/artifacts/updates/${runId}/report.json`);
}
