pub mod auth;
pub mod domain;
pub mod error;
mod routes;
pub mod sessions;
pub mod release;
pub mod maintenance;

use axum::{Router, extract::DefaultBodyLimit, middleware, routing::get};
use sqlx::PgPool;

#[derive(Clone)]
pub struct AppState { pub db: PgPool, pub auth: auth::Auth, pub maintenance: maintenance::Maintenance }
pub fn app(state: AppState) -> Router {
    let protected=routes::router()
        .route_layer(middleware::from_fn_with_state(state.clone(),maintenance::guard))
        .route_layer(middleware::from_fn_with_state(state.clone(),auth::authenticate));
    Router::new().route("/health/live",get(||async{axum::Json(serde_json::json!({"status":"ok"}))}))
        .route("/api/v1/session/login",axum::routing::post(sessions::login))
        .route("/api/v1/session/logout",axum::routing::post(sessions::logout))
        .merge(protected).layer(DefaultBodyLimit::max(64*1024)).fallback(||async{error::ApiError::missing()}).with_state(state)
}
