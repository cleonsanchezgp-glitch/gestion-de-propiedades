use std::{collections::HashSet, fs, path::{Path, PathBuf}, sync::{Arc, Mutex}};
use axum::{extract::{Request, State}, http::Method, middleware::Next, response::Response};
use serde::{Deserialize, Serialize};
use crate::{AppState, error::ApiError, release};

#[derive(Clone, Copy, Debug, Deserialize, Serialize, PartialEq, Eq)]
pub enum Phase { Preflight, Quiescing, BackingUp, Applying, Verifying, Committing, Committed, Recovering, Recovered, RecoveryRequired }
#[derive(Clone, Deserialize, Serialize)]
#[serde(deny_unknown_fields, rename_all="camelCase")]
pub struct Operation {
    pub format: u32, pub operation_id: String, pub phase: Phase,
    pub source_release_id: String, pub target_release_id: String,
    pub backup_reference: Option<String>, pub checks_passed: bool,
    pub step: String, pub services: serde_json::Value,
}
#[derive(Clone, Deserialize, Serialize, PartialEq, Eq, Hash)]
#[serde(deny_unknown_fields)]
pub struct Fixture { pub collection: String, pub id: String }
#[derive(Deserialize)]
#[serde(deny_unknown_fields, rename_all="camelCase")]
struct Grant { format: u32, operation_id: String, instance_id: String, nonce: String, fixtures: Vec<Fixture> }
#[derive(Clone)]
pub struct DiagnosticScope { pub operation_id: String, pub fixture: Fixture, pub allowed: Vec<Fixture> }

#[derive(Clone)]
pub struct Maintenance {
    root: Option<PathBuf>, legacy:bool, pub instance_id: String,
    owned: Arc<Mutex<HashSet<Fixture>>>,
    grants: Arc<Mutex<GrantState>>,
}
#[derive(Default)]
struct GrantState { active:Option<String>, revoked:HashSet<String> }
pub fn valid_id(value: &str) -> bool {
    !value.is_empty() && value.len() <= 80 && value.bytes().all(|c| c.is_ascii_alphanumeric() || b"._-".contains(&c))
}
fn read_json<T: serde::de::DeserializeOwned>(path: &Path) -> Result<T, ApiError> {
    let mut current=Some(path);
    while let Some(p)=current {
        let meta=fs::symlink_metadata(p).map_err(|_|ApiError::maintenance())?;
        if meta.file_type().is_symlink() { return Err(ApiError::maintenance()); }
        #[cfg(windows)] {
            use std::os::windows::fs::MetadataExt;
            if meta.file_attributes() & 0x400 != 0 { return Err(ApiError::maintenance()); }
        }
        current=p.parent().filter(|p|!p.as_os_str().is_empty());
    }
    let file=fs::File::open(path).map_err(|_|ApiError::maintenance())?;
    if file.metadata().map_err(|_|ApiError::maintenance())?.len() > 65536 { return Err(ApiError::maintenance()); }
    use std::io::Read;
    let mut bytes=Vec::new();file.take(65537).read_to_end(&mut bytes).map_err(|_|ApiError::maintenance())?;
    if bytes.len() > 65536 { return Err(ApiError::maintenance()); }
    serde_json::from_slice(&bytes).map_err(|_|ApiError::maintenance())
}
impl Maintenance {
    pub fn unmanaged() -> Self { Self { root:None,legacy:false,instance_id:uuid::Uuid::new_v4().to_string(),owned:Arc::new(Mutex::new(HashSet::new())),grants:Arc::new(Mutex::new(GrantState::default())) } }
    pub fn initial_layout(root:PathBuf) -> Result<Self,ApiError> {
        if !root.is_absolute() {return Err(ApiError::maintenance());}
        // The API runs as LocalService and cannot read the installer-only
        // settings.json (which also contains administrative secrets). api.json
        // is its explicitly readable runtime configuration.
        let settings:serde_json::Value=read_json(&root.join("config/api.json"))?;
        if settings["OwnerSubject"].as_str().is_none_or(str::is_empty) || settings["ApiPort"].as_u64().is_none() {return Err(ApiError::maintenance());}
        let mut state=Self::unmanaged();state.root=Some(root);state.legacy=true;state.operation()?;Ok(state)
    }
    pub fn managed(root: PathBuf) -> Result<Self, ApiError> {
        if !root.is_absolute() { return Err(ApiError::maintenance()); }
        let mut state=Self::unmanaged();state.root=Some(root);state.operation()?;Ok(state)
    }
    pub fn operation(&self) -> Result<Option<Operation>, ApiError> {
        let result=self.read_operation();
        if !matches!(&result,Ok(Some(Operation {phase:Phase::Verifying,..}))) {
            if let Ok(mut state)=self.grants.lock() {
                if let Some(nonce)=state.active.take() {state.revoked.insert(nonce);}
                if let Some(root)=&self.root {
                    if let Ok(grant)=read_json::<Grant>(&root.join("maintenance/diagnostic.json")) {state.revoked.insert(grant.nonce);}
                }
            }
        }
        result
    }
    fn read_operation(&self) -> Result<Option<Operation>, ApiError> {
        let Some(root)=&self.root else { return Ok(None) };
        if self.legacy {
            if root.join("config/active-release.json").exists() {return Err(ApiError::maintenance());}
            if !root.join("maintenance").exists() {return Ok(None);}
        }
        let op:Operation=read_json(&root.join("maintenance/operation.json"))?;
        if op.format != 1 || !op.services.is_array() || !valid_id(&op.operation_id) || !valid_id(&op.target_release_id) || op.source_release_id.is_empty() || op.source_release_id.len()>160 || !valid_id(&op.step) { return Err(ApiError::maintenance()); }
        if matches!(op.phase,Phase::Committed|Phase::Recovered) && !op.checks_passed { return Err(ApiError::maintenance()); }
        if self.legacy && (!matches!(op.phase,Phase::Recovering|Phase::Recovered) || op.source_release_id!=release::RELEASE_ID) {return Err(ApiError::maintenance());}
        let expected=if matches!(op.phase,Phase::Recovering|Phase::Recovered) { &op.source_release_id } else { &op.target_release_id };
        if matches!(op.phase,Phase::Verifying|Phase::Committing|Phase::Committed|Phase::Recovering|Phase::Recovered) && expected != release::RELEASE_ID { return Err(ApiError::maintenance()); }
        Ok(Some(op))
    }
    pub fn operational(&self) -> bool { matches!(self.operation(),Ok(None)) || matches!(self.operation(),Ok(Some(Operation {phase:Phase::Committed|Phase::Recovered,checks_passed:true,..}))) }
    pub fn can_serve(&self) -> bool { self.operational() || matches!(self.operation(),Ok(Some(Operation {phase:Phase::Verifying|Phase::Committing|Phase::Recovering,..}))) }
    pub fn can_migrate(&self) -> bool { matches!(self.operation(),Ok(Some(Operation {phase:Phase::Applying,target_release_id,..})) if target_release_id==release::RELEASE_ID) }
    pub fn diagnostics(&self, method:&Method, path:&str, headers:&axum::http::HeaderMap) -> Result<DiagnosticScope,ApiError> {
        let root=self.root.as_ref().ok_or_else(ApiError::maintenance)?;
        let op=self.operation()?.ok_or_else(ApiError::maintenance)?;
        if op.phase != Phase::Verifying { return Err(ApiError::maintenance()); }
        let grant:Grant=read_json(&root.join("maintenance/diagnostic.json"))?;
        let operation=headers.get("x-aelium-operation").and_then(|v|v.to_str().ok()).ok_or_else(ApiError::maintenance)?;
        let nonce=headers.get("x-aelium-capability").and_then(|v|v.to_str().ok()).ok_or_else(ApiError::maintenance)?;
        if grant.format != 1 || grant.operation_id != op.operation_id || operation != op.operation_id || grant.instance_id != self.instance_id || grant.nonce.len()!=64 || !grant.nonce.bytes().all(|c|c.is_ascii_hexdigit()) || nonce != grant.nonce || grant.fixtures.is_empty() || grant.fixtures.len()>16 { return Err(ApiError::maintenance()); }
        {
            let mut state=self.grants.lock().map_err(|_|ApiError::maintenance())?;
            if state.revoked.contains(&grant.nonce) {return Err(ApiError::maintenance());}
            if state.active.as_ref()!=Some(&grant.nonce) {
                if let Some(previous)=state.active.replace(grant.nonce.clone()) {state.revoked.insert(previous);}
            }
        }
        let mut seen=HashSet::new();
        for fixture in &grant.fixtures {
            crate::domain::kind(&fixture.collection).map_err(|_|ApiError::maintenance())?;
            let prefix=format!("maintenance-{}-",op.operation_id);
            if !fixture.id.starts_with(&prefix) || fixture.id.len()>128 || !fixture.id.bytes().all(|c|c.is_ascii_alphanumeric() || b"._-".contains(&c)) || !seen.insert(fixture.clone()) { return Err(ApiError::maintenance()); }
        }
        let parts=path.trim_matches('/').split('/').collect::<Vec<_>>();
        let fixture=match (method,parts.as_slice()) {
            (&Method::POST,["api","v1",collection]) => Fixture {collection:(*collection).into(),id:headers.get("x-aelium-fixture").and_then(|v|v.to_str().ok()).ok_or_else(ApiError::maintenance)?.into()},
            (&Method::GET|&Method::PATCH|&Method::DELETE,["api","v1",collection,id]) => Fixture {collection:(*collection).into(),id:(*id).into()},
            _ => return Err(ApiError::maintenance()),
        };
        if !grant.fixtures.contains(&fixture) { return Err(ApiError::maintenance()); }
        if *method!=Method::POST && !self.owned.lock().map_err(|_|ApiError::maintenance())?.contains(&fixture) { return Err(ApiError::maintenance()); }
        Ok(DiagnosticScope {operation_id:op.operation_id,fixture,allowed:grant.fixtures})
    }
    pub fn remember(&self, fixture:Fixture) -> Result<(),ApiError> { self.owned.lock().map_err(|_|ApiError::maintenance())?.insert(fixture);Ok(()) }
    pub fn forget(&self, fixture:&Fixture) -> Result<(),ApiError> { self.owned.lock().map_err(|_|ApiError::maintenance())?.remove(fixture);Ok(()) }
    pub fn owns(&self,fixture:&Fixture) -> bool {self.owned.lock().is_ok_and(|owned|owned.contains(fixture))}
    pub fn write_permit(&self) -> Result<Option<fs::File>,ApiError> {
        let Some(root)=&self.root else {return Ok(None)};
        if self.legacy && self.operation()?.is_none() {return Ok(None);}
        let path=root.join("maintenance/write-gate.lock");
        let meta=fs::symlink_metadata(&path).map_err(|_|ApiError::maintenance())?;
        if meta.file_type().is_symlink() || !meta.is_file() {return Err(ApiError::maintenance());}
        #[cfg(windows)] {use std::os::windows::fs::MetadataExt;if meta.file_attributes() & 0x400 != 0 {return Err(ApiError::maintenance());}}
        let file=fs::File::open(path).map_err(|_|ApiError::maintenance())?;
        file.try_lock_shared().map_err(|_|ApiError::maintenance())?;
        Ok(Some(file))
    }
}
pub async fn guard(State(state):State<AppState>,mut request:Request,next:Next) -> Result<Response,ApiError> {
    let diagnostic=request.headers().contains_key("x-aelium-capability") || request.headers().contains_key("x-aelium-operation") || request.headers().contains_key("x-aelium-fixture");
    // Hold the shared native lock through transaction completion. Journal publishers
    // take an exclusive byte-range lock before switching phases, draining admitted writes.
    let _permit=if diagnostic || !matches!(*request.method(),Method::GET|Method::HEAD|Method::OPTIONS) {state.maintenance.write_permit()?} else {None};
    if diagnostic {
        let scope=state.maintenance.diagnostics(request.method(),request.uri().path(),request.headers())?;
        request.extensions_mut().insert(scope);
    } else if !matches!(*request.method(),Method::GET|Method::HEAD|Method::OPTIONS) && !state.maintenance.operational() { return Err(ApiError::maintenance()); }
    Ok(next.run(request).await)
}

#[cfg(test)]
mod tests {
    use super::*;
    fn dir()->PathBuf {let p=std::env::temp_dir().join(format!("aelium-maintenance-{}",uuid::Uuid::new_v4()));fs::create_dir_all(p.join("maintenance")).unwrap();fs::write(p.join("maintenance/write-gate.lock"),[]).unwrap();p}
    fn write(p:&Path,phase:Phase,checks:bool) {let op=Operation {format:1,operation_id:"operation".into(),phase,source_release_id:release::RELEASE_ID.into(),target_release_id:release::RELEASE_ID.into(),backup_reference:None,checks_passed:checks,step:"test".into(),services:serde_json::json!([])};fs::write(p.join("maintenance/operation.json"),serde_json::to_vec(&op).unwrap()).unwrap();}
    #[test] fn missing_invalid_intermediate_and_unverified_terminal_states_block_writes() {
        let p=dir();assert!(Maintenance::managed(p.clone()).is_err());
        write(&p,Phase::Committed,true);let m=Maintenance::managed(p.clone()).unwrap();assert!(m.operational());
        for phase in [Phase::Preflight,Phase::Quiescing,Phase::BackingUp,Phase::Applying,Phase::Verifying,Phase::Committing,Phase::Recovering,Phase::RecoveryRequired] {write(&p,phase,false);assert!(!m.operational());}
        write(&p,Phase::Committed,false);assert!(!m.operational());fs::write(p.join("maintenance/operation.json"),b"broken").unwrap();assert!(!m.operational());
        fs::remove_file(p.join("maintenance/operation.json")).unwrap();assert!(!m.operational());
    }
    #[test] fn initial_layout_cannot_bypass_a_protocol_introduced_later() {
        let p=std::env::temp_dir().join(format!("aelium-initial-{}",uuid::Uuid::new_v4()));fs::create_dir_all(p.join("config")).unwrap();fs::write(p.join("config/api.json"),br#"{"OwnerSubject":"owner","ApiPort":58090}"#).unwrap();
        let m=Maintenance::initial_layout(p.clone()).unwrap();assert!(m.operational());fs::create_dir(p.join("maintenance")).unwrap();assert!(!m.operational());assert!(Maintenance::initial_layout(p.clone()).is_err());
        write(&p,Phase::Recovering,false);assert!(!m.operational());assert!(m.can_serve());assert!(Maintenance::initial_layout(p.clone()).is_ok());
        write(&p,Phase::Recovered,true);assert!(m.operational());assert!(Maintenance::initial_layout(p).is_ok());
    }
    #[test] fn diagnostic_capability_requires_phase_instance_operation_and_exact_owned_fixture() {
        let p=dir();write(&p,Phase::Verifying,false);let m=Maintenance::managed(p.clone()).unwrap();
        let fixture=Fixture {collection:"propiedades".into(),id:"maintenance-operation-property".into()};
        let grant=serde_json::json!({"format":1,"operationId":"operation","instanceId":m.instance_id,"nonce":"a".repeat(64),"fixtures":[fixture]});fs::write(p.join("maintenance/diagnostic.json"),serde_json::to_vec(&grant).unwrap()).unwrap();
        let mut h=axum::http::HeaderMap::new();h.insert("x-aelium-operation","operation".parse().unwrap());h.insert("x-aelium-capability","a".repeat(64).parse().unwrap());h.insert("x-aelium-fixture",fixture.id.parse().unwrap());
        assert!(m.diagnostics(&Method::POST,"/api/v1/propiedades",&h).is_ok());
        let path=format!("/api/v1/propiedades/{}",fixture.id);assert!(m.diagnostics(&Method::PATCH,&path,&h).is_err());m.remember(fixture).unwrap();assert!(m.diagnostics(&Method::PATCH,&path,&h).is_ok());
        assert!(m.diagnostics(&Method::PATCH,"/api/v1/propiedades/real-record",&h).is_err());
        assert!(m.diagnostics(&Method::PUT,"/api/v1/inquilinos/x/pagos/2026-10",&h).is_err());
        let restarted=Maintenance::managed(p.clone()).unwrap();assert!(restarted.diagnostics(&Method::POST,"/api/v1/propiedades",&h).is_err());
        fs::write(p.join("maintenance/operation.json"),b"invalid").unwrap();assert!(!m.operational());write(&p,Phase::Verifying,false);
        assert!(m.diagnostics(&Method::POST,"/api/v1/propiedades",&h).is_err());
        write(&p,Phase::Committed,true);assert!(m.diagnostics(&Method::POST,"/api/v1/propiedades",&h).is_err());
    }
}
