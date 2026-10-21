use axum::{Json, http::StatusCode, response::{IntoResponse, Response}};
use serde_json::json;

#[derive(Debug)]
pub struct ApiError(pub StatusCode, pub &'static str, pub &'static str);
impl ApiError {
    pub fn invalid() -> Self { Self(StatusCode::BAD_REQUEST, "VALIDATION_ERROR", "Datos no válidos") }
    pub fn unauthorized() -> Self { Self(StatusCode::UNAUTHORIZED, "UNAUTHORIZED", "Se requiere una sesión válida") }
    pub fn forbidden() -> Self { Self(StatusCode::FORBIDDEN, "FORBIDDEN", "Permiso insuficiente") }
    pub fn missing() -> Self { Self(StatusCode::NOT_FOUND, "NOT_FOUND", "Recurso no disponible") }
    pub fn conflict() -> Self { Self(StatusCode::CONFLICT, "CONFLICT", "El registro ha cambiado o tiene dependencias") }
    pub fn unavailable() -> Self { Self(StatusCode::SERVICE_UNAVAILABLE, "UNAVAILABLE", "Servicio temporalmente no disponible") }
    pub fn maintenance() -> Self { Self(StatusCode::SERVICE_UNAVAILABLE, "MAINTENANCE_IN_PROGRESS", "Mantenimiento en curso; conserva los cambios y espera a que termine") }
}
impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        (self.0, Json(json!({"error":{"code":self.1,"message":self.2,"requestId":uuid::Uuid::new_v4().to_string()}}))).into_response()
    }
}
impl From<sqlx::Error> for ApiError {
    fn from(error: sqlx::Error) -> Self {
        if let sqlx::Error::Database(ref db) = error {
            if matches!(db.code().as_deref(), Some("23503" | "23505" | "40001" | "40P01")) { return Self::conflict(); }
            if matches!(db.code().as_deref(), Some("23514" | "23502" | "22003")) { return Self::invalid(); }
        }
        // Never log SQL parameters, payloads, tokens or credentials.
        tracing::error!("Database operation failed");
        Self::unavailable()
    }
}
