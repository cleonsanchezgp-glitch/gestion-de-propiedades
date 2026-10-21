use serde::{Deserialize, Serialize};
use sqlx::{PgPool, Row};

include!(concat!(env!("OUT_DIR"), "/release_metadata.rs"));
pub static MIGRATOR: sqlx::migrate::Migrator = sqlx::migrate!();

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct MigrationInfo { pub version: String, pub checksum: String }

pub fn migrations() -> Vec<MigrationInfo> {
    MIGRATOR.iter().filter(|m| m.migration_type.is_up_migration()).map(|m| MigrationInfo {
        version: m.version.to_string(), checksum: m.checksum.iter().map(|b| format!("{b:02x}")).collect(),
    }).collect()
}
pub fn info() -> serde_json::Value {
    serde_json::json!({"format":1,"product":"aelium-propiedades","releaseId":RELEASE_ID,"buildId":BUILD_ID,"apiContract":API_CONTRACT,"migrations":migrations(),"transactionalMigrations":MIGRATOR.iter().all(|m|!m.no_tx)})
}
pub fn history_matches(history: &[(String,String,bool)], expected: &[MigrationInfo], prefix: bool) -> bool {
    if history.len() > expected.len() || (!prefix && history.len() != expected.len()) { return false; }
    history.iter().zip(expected).all(|((version,checksum,success),m)| *success && version == &m.version && checksum == &m.checksum)
}
pub async fn check_schema(db: &PgPool, prefix: bool) -> Result<(), &'static str> {
    // Read-only: never call Migrator::run to inspect history.
    let exists: bool = sqlx::query_scalar("SELECT to_regclass('public._sqlx_migrations') IS NOT NULL").fetch_one(db).await.map_err(|_| "Schema inspection failed")?;
    if !exists { return if prefix { Ok(()) } else { Err("Migration history is missing") }; }
    let rows = sqlx::query("SELECT version::text, encode(checksum,'hex') AS checksum, success FROM public._sqlx_migrations ORDER BY version").fetch_all(db).await.map_err(|_| "Schema inspection failed")?;
    let history = rows.iter().map(|r| (r.get("version"),r.get("checksum"),r.get("success"))).collect::<Vec<_>>();
    if history_matches(&history, &migrations(), prefix) { Ok(()) } else { Err("Migration history is incomplete or incompatible") }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test] fn serving_requires_exact_successful_embedded_history() {
        let expected=migrations();
        assert!(!expected.is_empty());
        let mut history=expected.iter().map(|m|(m.version.clone(),m.checksum.clone(),true)).collect::<Vec<_>>();
        assert!(history_matches(&history,&expected,false));
        history.pop(); assert!(!history_matches(&history,&expected,false)); assert!(history_matches(&history,&expected,true));
        history[0].2=false; assert!(!history_matches(&history,&expected,true));
        history[0].2=true;history[0].1="changed".into();assert!(!history_matches(&history,&expected,false));
        history[0].1=expected[0].checksum.clone();history.push(("999".into(),"unknown".into(),true));assert!(!history_matches(&history,&expected,true));
    }
}
