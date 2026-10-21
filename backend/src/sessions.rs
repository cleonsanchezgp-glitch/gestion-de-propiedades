use std::{collections::HashMap,sync::Arc,time::{Duration,Instant}};
use axum::{extract::{State,rejection::JsonRejection},http::{HeaderMap,HeaderValue,StatusCode,header},response::{IntoResponse,Response},Json};
use serde::Deserialize;
use tokio::sync::Mutex;
use crate::{AppState,auth::{Auth,Principal},error::ApiError};

const COOKIE:&str="aelium_session";
pub const SESSION_SECONDS:u64=30*60;
#[derive(Clone,Default)]
pub struct Sessions {
    pub origin:String,
    client_id:String,
    client_secret:String,
    secure:bool,
    entries:Arc<Mutex<HashMap<String,Session>>>,
}
struct Session {access:String,refresh:String,expires:Instant,deadline:Instant}
#[derive(Deserialize)]
struct Tokens {access_token:String,refresh_token:String,expires_in:u64}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Credentials {username:String,password:String}
impl Sessions {
    pub fn from_env()->Result<Self,Box<dyn std::error::Error>> {
        let client_id=std::env::var("KEYCLOAK_LOGIN_CLIENT_ID").unwrap_or_default();
        if client_id.is_empty(){return Ok(Self::default());}
        let client_secret=std::env::var("KEYCLOAK_LOGIN_CLIENT_SECRET")?;
        let origin=std::env::var("PORTAL_ORIGIN")?;
        let parsed=reqwest::Url::parse(&origin)?;
        let secure=parsed.scheme()=="https";
        let local=matches!(parsed.host_str(),Some("localhost"|"127.0.0.1"|"[::1]"));
        if client_secret.is_empty() || (!secure && !(local && parsed.scheme()=="http")) || parsed.origin().ascii_serialization()!=origin {
            return Err("Invalid portal login configuration".into());
        }
        Ok(Self {origin,client_id,client_secret,secure,..Self::default()})
    }
    pub fn check_origin(&self,headers:&HeaderMap)->Result<(),ApiError>{
        if self.origin.is_empty() || headers.get(header::ORIGIN).and_then(|v|v.to_str().ok())!=Some(self.origin.as_str()) {return Err(ApiError::forbidden());}
        Ok(())
    }
    fn cookie(&self,id:&str,clear:bool)->String {
        format!("{COOKIE}={id}; Path=/api; HttpOnly; SameSite=Strict; Max-Age={}{}",if clear {0}else{SESSION_SECONDS},if self.secure {"; Secure"}else{""})
    }
    async fn tokens(&self,auth:&Auth,mut form:Vec<(&str,String)>)->Result<Tokens,ApiError>{
        if self.client_id.is_empty(){return Err(ApiError::unavailable());}
        form.push(("client_id",self.client_id.clone()));form.push(("client_secret",self.client_secret.clone()));
        let response=auth.client.post(format!("{}/protocol/openid-connect/token",auth.issuer.trim_end_matches('/'))).form(&form).send().await.map_err(|_|ApiError::unavailable())?;
        if response.status().is_client_error(){return Err(ApiError::unauthorized());}
        if !response.status().is_success(){return Err(ApiError::unavailable());}
        response.json().await.map_err(|_|ApiError::unavailable())
    }
    pub async fn principal(&self,auth:&Auth,headers:&HeaderMap)->Result<Principal,ApiError>{
        let id=session_id(headers).ok_or_else(ApiError::unauthorized)?;
        let mut entries=self.entries.lock().await;
        let now=Instant::now();entries.retain(|_,session|session.deadline>now);
        let session=entries.get_mut(&id).ok_or_else(ApiError::unauthorized)?;
        if session.expires<=now+Duration::from_secs(30){
            let tokens=match self.tokens(auth,vec![("grant_type","refresh_token".into()),("refresh_token",session.refresh.clone())]).await {
                Ok(tokens)=>tokens,Err(error)=>{entries.remove(&id);return Err(error);}
            };
            session.access=tokens.access_token;session.refresh=tokens.refresh_token;session.expires=now+Duration::from_secs(tokens.expires_in.min(SESSION_SECONDS));
        }
        let principal=auth.principal(&session.access).await?;auth.authorize(&principal)?;
        if session.deadline<=Instant::now(){entries.remove(&id);return Err(ApiError::unauthorized());}
        Ok(principal)
    }
}
pub fn session_id(headers:&HeaderMap)->Option<String>{
    headers.get(header::COOKIE)?.to_str().ok()?.split(';').find_map(|part|{
        let (name,value)=part.trim().split_once('=')?;
        if name==COOKIE && value.len()==64 && value.bytes().all(|c|c.is_ascii_hexdigit()){Some(value.to_owned())}else{None}
    })
}
fn response_cookie(status:StatusCode,value:serde_json::Value,cookie:String)->Response{
    let mut response=(status,Json(value)).into_response();
    if let Ok(cookie)=HeaderValue::from_str(&cookie){response.headers_mut().insert(header::SET_COOKIE,cookie);}
    response.headers_mut().insert(header::CACHE_CONTROL,HeaderValue::from_static("no-store"));response
}
pub async fn login(State(state):State<AppState>,headers:HeaderMap,input:Result<Json<Credentials>,JsonRejection>)->Result<Response,ApiError>{
    state.auth.sessions.check_origin(&headers)?;
    let Json(credentials)=input.map_err(|_|ApiError::invalid())?;
    if credentials.username.trim().is_empty() || credentials.username.len()>200 || credentials.password.is_empty() || credentials.password.len()>1024{return Err(ApiError::invalid());}
    let tokens=state.auth.sessions.tokens(&state.auth,vec![("grant_type","password".into()),("scope","openid".into()),("username",credentials.username),("password",credentials.password)]).await?;
    let principal=state.auth.principal(&tokens.access_token).await?;state.auth.authorize(&principal)?;
    let id=format!("{}{}",uuid::Uuid::new_v4().simple(),uuid::Uuid::new_v4().simple());
    let now=Instant::now();
    let mut entries=state.auth.sessions.entries.lock().await;entries.retain(|_,session|session.deadline>now);
    if let Some(previous)=session_id(&headers){entries.remove(&previous);}
    if entries.len()>=128{return Err(ApiError::unavailable());}
    entries.insert(id.clone(),Session{access:tokens.access_token,refresh:tokens.refresh_token,expires:now+Duration::from_secs(tokens.expires_in.min(SESSION_SECONDS)),deadline:now+Duration::from_secs(SESSION_SECONDS)});
    Ok(response_cookie(StatusCode::OK,serde_json::json!({"authenticated":true,"expiresIn":SESSION_SECONDS}),state.auth.sessions.cookie(&id,false)))
}
pub async fn logout(State(state):State<AppState>,headers:HeaderMap)->Result<Response,ApiError>{
    state.auth.sessions.check_origin(&headers)?;
    let session=if let Some(id)=session_id(&headers){state.auth.sessions.entries.lock().await.remove(&id)}else{None};
    if let Some(session)=session {
        let _=state.auth.client.post(format!("{}/protocol/openid-connect/logout",state.auth.issuer.trim_end_matches('/')))
            .form(&[("client_id",state.auth.sessions.client_id.as_str()),("client_secret",state.auth.sessions.client_secret.as_str()),("refresh_token",session.refresh.as_str())]).send().await;
    }
    Ok(response_cookie(StatusCode::OK,serde_json::json!({"authenticated":false}),state.auth.sessions.cookie("",true)))
}
#[cfg(test)]
mod tests {
    use super::*;
    #[tokio::test]async fn expired_session_is_rejected_before_token_refresh(){
        let sessions=Sessions::default();let id="a".repeat(64);
        let start=Instant::now()-Duration::from_secs(SESSION_SECONDS);
        sessions.entries.lock().await.insert(id.clone(),Session{access:"unused".into(),refresh:"unused".into(),expires:Instant::now()+Duration::from_secs(3600),deadline:start+Duration::from_secs(SESSION_SECONDS)});
        let mut headers=HeaderMap::new();headers.insert(header::COOKIE,HeaderValue::from_str(&format!("aelium_session={id}")).unwrap());
        let error=sessions.principal(&Auth::test_auth(),&headers).await.err().unwrap();
        assert_eq!(error.0,StatusCode::UNAUTHORIZED);
        assert!(sessions.entries.lock().await.is_empty());
    }
    #[test]fn session_cookie_and_origin_reject_untrusted_inputs(){
        let mut headers=HeaderMap::new();headers.insert(header::COOKIE,HeaderValue::from_static("aelium_session=../../other"));
        assert!(session_id(&headers).is_none());
        let sessions=Sessions{origin:"http://127.0.0.1:55173".into(),..Sessions::default()};
        assert!(sessions.check_origin(&headers).is_err());
        headers.insert(header::ORIGIN,HeaderValue::from_static("https://untrusted.example"));assert!(sessions.check_origin(&headers).is_err());
        headers.insert(header::ORIGIN,HeaderValue::from_static("http://127.0.0.1:55173"));assert!(sessions.check_origin(&headers).is_ok());
        assert!(sessions.cookie("test",false).contains("HttpOnly; SameSite=Strict"));
        assert!(sessions.cookie("test",false).contains("Max-Age=1800"));
        assert!(sessions.cookie("",true).contains("Max-Age=0"));
    }
}
