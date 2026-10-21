use std::{collections::HashSet, sync::Arc, time::{Duration, Instant}};
use axum::{extract::{Request, State}, middleware::Next, response::Response};
use jsonwebtoken::{Algorithm, DecodingKey, Validation, decode, decode_header, jwk::JwkSet};
use serde::{Deserialize, Serialize};
use tokio::sync::Mutex;
use crate::{AppState, error::ApiError};

#[derive(Clone)]
pub struct Auth {
    pub issuer: String,
    pub audience: String,
    pub allowed_subject: String,
    pub jwks_url: String,
    pub client: reqwest::Client,
    pub sessions:crate::sessions::Sessions,
    cache: Arc<Mutex<Option<(Instant,JwkSet)>>>,
}
#[derive(Clone, Deserialize, Serialize)]
pub struct Roles { #[serde(default)] pub roles: Vec<String> }
#[derive(Clone, Deserialize, Serialize)]
pub struct Principal {
    pub sub: String,
    pub iss: String,
    pub exp: usize,
    #[serde(default)] pub realm_access: Option<Roles>,
}
impl Auth {
    #[cfg(test)]
    pub(crate) fn test_auth()->Self {
        Self {issuer:"http://127.0.0.1:1/realm".into(),audience:"api".into(),allowed_subject:"owner".into(),jwks_url:String::new(),client:reqwest::Client::new(),sessions:crate::sessions::Sessions::default(),cache:Arc::new(Mutex::new(None))}
    }
    pub fn from_env() -> Result<Self,Box<dyn std::error::Error>> {
        fn required(name: &str) -> Result<String,Box<dyn std::error::Error>> {
            let value=std::env::var(name)?;
            if value.trim().is_empty() { return Err(format!("Empty configuration: {name}").into()); }
            Ok(value)
        }
        let issuer=required("KEYCLOAK_ISSUER")?;
        let parsed=reqwest::Url::parse(&issuer)?;
        let local=matches!(parsed.host_str(),Some("127.0.0.1"|"localhost"|"[::1]"));
        if parsed.scheme()!="https" && !(local && parsed.scheme()=="http") {return Err("Issuer requires HTTPS except for loopback tests".into());}
        let client=reqwest::Client::builder().timeout(Duration::from_secs(5)).redirect(reqwest::redirect::Policy::none()).build()?;
        Ok(Self {jwks_url:format!("{}/protocol/openid-connect/certs",issuer.trim_end_matches('/')),issuer,
            audience:required("KEYCLOAK_AUDIENCE")?,allowed_subject:required("KEYCLOAK_ALLOWED_SUBJECT")?,client,sessions:crate::sessions::Sessions::from_env()?,cache:Arc::new(Mutex::new(None))})
    }
    pub fn authorize(&self, principal: &Principal) -> Result<(), ApiError> {
        if self.allowed_subject.trim().is_empty() || principal.iss != self.issuer || principal.sub != self.allowed_subject {
            return Err(ApiError::forbidden());
        }
        Ok(())
    }
    pub async fn principal(&self, token: &str) -> Result<Principal,ApiError> {
        if token.len()>16384 {return Err(ApiError::unauthorized());}
        let header=decode_header(token).map_err(|_|ApiError::unauthorized())?;
        if header.alg!=Algorithm::RS256 {return Err(ApiError::unauthorized());}
        let kid=header.kid.ok_or_else(ApiError::unauthorized)?;
        let mut cache=self.cache.lock().await;
        if cache.as_ref().is_none_or(|(at,_)|at.elapsed()>Duration::from_secs(60)) {
            let response=self.client.get(&self.jwks_url).send().await.map_err(|_|ApiError::unavailable())?;
            let set=response.error_for_status().map_err(|_|ApiError::unavailable())?.json::<JwkSet>().await.map_err(|_|ApiError::unavailable())?;
            *cache=Some((Instant::now(),set));
        }
        let key=cache.as_ref().and_then(|(_,set)|set.find(&kid)).ok_or_else(ApiError::unauthorized)?;
        let decoding=DecodingKey::from_jwk(key).map_err(|_|ApiError::unauthorized())?;
        drop(cache);
        let mut validation=Validation::new(Algorithm::RS256);
        validation.set_issuer(&[&self.issuer]);
        validation.set_audience(&[&self.audience]);
        validation.required_spec_claims=HashSet::from_iter(["exp","iss","aud","sub"].map(String::from));
        validation.leeway=0;
        validation.validate_nbf=true;
        let principal=decode::<Principal>(token,&decoding,&validation).map_err(|_|ApiError::unauthorized())?.claims;
        if principal.sub.trim().is_empty() {return Err(ApiError::unauthorized());}
        Ok(principal)
    }
}
pub async fn authenticate(State(state): State<AppState>, mut request: Request, next: Next) -> Result<Response,ApiError> {
    let principal=if let Some(authorization)=request.headers().get("authorization") {
        let token=authorization.to_str().ok().and_then(|v|v.strip_prefix("Bearer ")).ok_or_else(ApiError::unauthorized)?;
        state.auth.principal(token).await?
    } else {
        if !matches!(*request.method(),axum::http::Method::GET|axum::http::Method::HEAD){state.auth.sessions.check_origin(request.headers())?;}
        state.auth.sessions.principal(&state.auth,request.headers()).await?
    };
    state.auth.authorize(&principal)?;
    request.extensions_mut().insert(principal);
    let mut response=next.run(request).await;
    response.headers_mut().insert(axum::http::header::CACHE_CONTROL,axum::http::HeaderValue::from_static("no-store"));
    Ok(response)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn exclusive_identity_denies_other_subjects_issuers_and_missing_configuration() {
        let mut auth=Auth {issuer:"https://identity.example/realm".into(),audience:"api".into(),allowed_subject:"owner".into(),jwks_url:String::new(),client:reqwest::Client::new(),sessions:crate::sessions::Sessions::default(),cache:Arc::new(Mutex::new(None))};
        let mut principal=Principal {sub:"owner".into(),iss:auth.issuer.clone(),exp:0,realm_access:None};
        assert!(auth.authorize(&principal).is_ok());
        principal.sub="other".into();
        assert!(auth.authorize(&principal).is_err());
        principal.sub="owner".into();principal.iss="https://other.example".into();
        assert!(auth.authorize(&principal).is_err());
        principal.iss=auth.issuer.clone();auth.allowed_subject.clear();
        assert!(auth.authorize(&principal).is_err());
    }
}
