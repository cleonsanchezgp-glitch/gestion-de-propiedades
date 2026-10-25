use propiedades_backend::{AppState, auth::Auth, maintenance::Maintenance, release};
use sqlx::postgres::PgPoolOptions;
use std::{path::PathBuf,time::Duration};

#[derive(Debug,PartialEq)]
enum Mode { Info, Serve, InitialServe, Develop, Migrate, Bootstrap, ContainerServe, ContainerMigrate }
fn arguments(args:&[String]) -> Result<(Mode,Option<PathBuf>), &'static str> {
    if args == ["--release-info"] { return Ok((Mode::Info,None)); }
    let mut words=args.to_vec();let mut root=None;
    if let Some(i)=words.iter().position(|v|v=="--install-root") {
        if i+1>=words.len() {return Err("Missing installation root");}
        root=Some(PathBuf::from(words.remove(i+1)));words.remove(i);
    }
    let mode=match words.iter().map(String::as_str).collect::<Vec<_>>().as_slice() {
        [] | ["--serve","--no-migrate"] => Mode::Serve,
        ["--serve","--no-migrate","--initial-layout"] if root.is_some() => Mode::InitialServe,
        ["--dev","--migrate"] => Mode::Develop,
        ["--container-serve"] => Mode::ContainerServe,
        ["--container-migrate"] => Mode::ContainerMigrate,
        ["--migrate-only"] if root.is_some() => Mode::Migrate,
        ["--migrate-only","--bootstrap"] if root.is_some() => Mode::Bootstrap,
        _ => return Err("Use --release-info, --serve --no-migrate, --dev --migrate, or --migrate-only --install-root PATH (initial install: --bootstrap)"),
    };
    if matches!(mode,Mode::Develop|Mode::ContainerServe|Mode::ContainerMigrate) && root.is_some() {return Err("This mode cannot use a managed installation");}
    Ok((mode,root))
}

#[tokio::main]
async fn main() -> Result<(),Box<dyn std::error::Error>> {
    let (mode,root)=arguments(&std::env::args().skip(1).collect::<Vec<_>>())?;
    if mode==Mode::Info { println!("{}",release::info());return Ok(()); }
    if matches!(mode,Mode::Migrate|Mode::Bootstrap|Mode::ContainerMigrate) && release::MIGRATOR.iter().any(|m|m.no_tx) {return Err("Nontransactional migrations require a separate maintenance plan".into());}
    tracing_subscriber::fmt().with_env_filter("propiedades_backend=info").init();
    let maintenance=if mode==Mode::Bootstrap {
        let root=root.as_ref().ok_or("Initial installation root is required")?;
        if !root.is_absolute() || root.join("config/active-release.json").exists() || root.join("maintenance").exists() {return Err("Not a fresh installation layout".into());}
        let settings:serde_json::Value=serde_json::from_slice(&std::fs::read(root.join("config/settings.json")).map_err(|_|"Initial installation configuration missing")?).map_err(|_|"Initial installation configuration invalid")?;
        if settings["Format"]!=1 || settings["Complete"]!=false {return Err("Bootstrap requires an incomplete initial installation".into());}
        Maintenance::unmanaged()
    } else if mode==Mode::InitialServe {Maintenance::initial_layout(root.ok_or("Initial installation root required")?).map_err(|_|"Initial layout is invalid or update protocol already introduced")?}
    else if let Some(root)=root { Maintenance::managed(root).map_err(|_|"Maintenance record missing or invalid")? }
    else if matches!(mode,Mode::Develop|Mode::ContainerServe|Mode::ContainerMigrate) { Maintenance::unmanaged() }
    else {return Err("Operational startup requires --install-root; development requires --dev --migrate".into());};
    if mode==Mode::Migrate && !maintenance.can_migrate() {return Err("Migration requires Applying phase for this release".into());}
    if matches!(mode,Mode::Serve|Mode::InitialServe|Mode::ContainerServe) && !maintenance.can_serve() {return Err("Installation cannot serve in this maintenance phase".into());}
    let auth=if matches!(mode,Mode::Serve|Mode::InitialServe|Mode::Develop|Mode::ContainerServe) {Some(Auth::from_env()?)} else {None};
    let database=std::env::var("DATABASE_URL").map_err(|_|"DATABASE_URL is required")?;
    let db=PgPoolOptions::new().max_connections(5).acquire_timeout(Duration::from_secs(5)).connect(&database).await.map_err(|_|"Database connection failed; inspect configuration privately")?;
    if matches!(mode,Mode::Develop|Mode::Migrate|Mode::Bootstrap|Mode::ContainerMigrate) {
        release::check_schema(&db,true).await?;
        release::MIGRATOR.run(&db).await.map_err(|_|"Database migration failed")?;
    }
    release::check_schema(&db,false).await?;
    if matches!(mode,Mode::Migrate|Mode::Bootstrap|Mode::ContainerMigrate) { println!("{}",serde_json::json!({"status":"SchemaVerified","releaseId":release::RELEASE_ID}));db.close().await;return Ok(()); }
    let address=std::env::var("BACKEND_BIND").unwrap_or_else(|_|"127.0.0.1:58080".to_owned());
    let listener=tokio::net::TcpListener::bind(&address).await?;
    tracing::info!("Backend listening at {address}");
    axum::serve(listener,propiedades_backend::app(AppState{db,auth:auth.ok_or("Authentication missing")?,maintenance})).with_graceful_shutdown(async {let _=tokio::signal::ctrl_c().await;}).await?;
    Ok(())
}
#[cfg(test)]
mod tests {
    use super::*;
    fn args(words:&[&str])->Vec<String>{words.iter().map(|s|s.to_string()).collect()}
    #[test] fn migration_is_always_explicit_and_unknown_flags_fail() {
        assert_eq!(arguments(&args(&[])).unwrap().0,Mode::Serve);
        assert_eq!(arguments(&args(&["--release-info"])).unwrap().0,Mode::Info);
        assert_eq!(arguments(&args(&["--dev","--migrate"])).unwrap().0,Mode::Develop);
        assert_eq!(arguments(&args(&["--container-serve"])).unwrap().0,Mode::ContainerServe);
        assert_eq!(arguments(&args(&["--container-migrate"])).unwrap().0,Mode::ContainerMigrate);
        assert!(arguments(&args(&["--migrate-only"])).is_err());
        assert!(arguments(&args(&["--serve","--migrate"])).is_err());
        assert!(arguments(&args(&["--dev","--migrate","--install-root","C:/managed"])).is_err());
    }
}
