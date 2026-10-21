use axum::{Router, Extension, Json, body::Bytes, http::{HeaderMap,header}, response::{IntoResponse,Response}, extract::{DefaultBodyLimit,Path, Query, State, rejection::JsonRejection}, routing::{get,put,post}};
use serde::Deserialize;
use serde_json::{Value,json};
use sqlx::{Row, Postgres, Transaction};
use crate::{AppState,auth::Principal,domain,error::ApiError,maintenance::{DiagnosticScope,Fixture},release};

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/api/v1/documentos/archivo",post(create_document_file).layer(DefaultBodyLimit::max(10*1024*1024)))
        .route("/api/v1/documentos/{id}/archivo",get(download_document_file).put(replace_document_file).layer(DefaultBodyLimit::max(10*1024*1024)))
        .route("/api/v1/me",get(me))
        .route("/api/v1/system/version",get(system_version))
        .route("/api/v1/dashboard",get(dashboard))
        .route("/api/v1/pagos",get(payments))
        .route("/api/v1/inquilinos/{id}/pagos/{mes}",put(set_payment))
        .route("/api/v1/{collection}",get(list).post(create))
        .route("/api/v1/{collection}/{id}",get(detail).patch(update).delete(archive))
}
type ResultJson=Result<Json<Value>,ApiError>;
#[derive(Deserialize)]
struct DocumentUpload { document:Value, filename:String, version:Option<i64> }
fn upload_metadata(headers:&HeaderMap) -> Result<DocumentUpload,ApiError> {
    let raw=headers.get("x-document-metadata").and_then(|v|v.to_str().ok()).filter(|s|s.len()<=16384).ok_or_else(ApiError::invalid)?;
    let mut upload:DocumentUpload=serde_json::from_str(raw).map_err(|_|ApiError::invalid())?;
    if upload.filename.trim().is_empty() || upload.filename.len()>200 || upload.filename.chars().any(|c|c.is_control() || matches!(c,'/'|'\\')) {return Err(ApiError::invalid());}
    domain::validate("documentos",&mut upload.document)?;
    Ok(upload)
}
async fn create_document_file(State(state):State<AppState>,Extension(user):Extension<Principal>,headers:HeaderMap,bytes:Bytes) -> ResultJson {
    save_document_file(&state,&user,None,headers,bytes).await
}
async fn replace_document_file(State(state):State<AppState>,Extension(user):Extension<Principal>,Path(id):Path<String>,headers:HeaderMap,bytes:Bytes) -> ResultJson {
    save_document_file(&state,&user,Some(id),headers,bytes).await
}
async fn save_document_file(state:&AppState,user:&Principal,id:Option<String>,headers:HeaderMap,bytes:Bytes) -> ResultJson {
    let upload=upload_metadata(&headers)?;
    if bytes.is_empty() || bytes.len()>10*1024*1024 {return Err(ApiError::invalid());}
    let mut tx=state.db.begin().await?;
    references(&mut tx,&upload.document).await?;
    let row=if let Some(id)=id {
        let expected=upload.version.filter(|v|*v>0).ok_or_else(ApiError::invalid)?;
        sqlx::query("UPDATE entities SET payload=$2,version=version+1,updated_at=now() WHERE kind='documentos' AND id=$1 AND NOT archived AND version=$3 RETURNING id,payload,version")
            .bind(id).bind(&upload.document).bind(expected).fetch_optional(&mut *tx).await?.ok_or_else(ApiError::conflict)?
    } else {
        sqlx::query("INSERT INTO entities(kind,id,payload) VALUES('documentos',$1,$2) RETURNING id,payload,version")
            .bind(uuid::Uuid::new_v4().to_string()).bind(&upload.document).fetch_one(&mut *tx).await?
    };
    let id:String=row.get("id");
    sqlx::query("INSERT INTO document_files(document_id,filename,content) VALUES($1,$2,$3) ON CONFLICT(document_id) DO UPDATE SET filename=EXCLUDED.filename,content=EXCLUDED.content,updated_at=now()")
        .bind(&id).bind(&upload.filename).bind(bytes.as_ref()).execute(&mut *tx).await?;
    audit(&mut tx,user,"save_file","documentos",&id).await?;
    tx.commit().await?;
    let mut result=record(&row);result["archivo"]=json!({"nombre":upload.filename,"size":bytes.len()});
    Ok(Json(result))
}
async fn download_document_file(State(state):State<AppState>,Path(id):Path<String>) -> Result<Response,ApiError> {
    let row=sqlx::query("SELECT f.filename,f.content FROM document_files f JOIN entities e ON e.kind='documentos' AND e.id=f.document_id WHERE e.id=$1 AND NOT e.archived")
        .bind(id).fetch_optional(&state.db).await?.ok_or_else(ApiError::missing)?;
    let filename:String=row.get("filename");
    let encoded=filename.as_bytes().iter().map(|b|format!("%{b:02X}")).collect::<String>();
    Ok(([(header::CONTENT_TYPE,"application/octet-stream".to_string()),(header::CONTENT_DISPOSITION,format!("attachment; filename=\"documento\"; filename*=UTF-8''{encoded}")),(header::CACHE_CONTROL,"no-store".to_string()),(header::X_CONTENT_TYPE_OPTIONS,"nosniff".to_string())],row.get::<Vec<u8>,_>("content")).into_response())
}
fn body(input: Result<Json<Value>,JsonRejection>) -> Result<Value,ApiError> {Ok(input.map_err(|_|ApiError::invalid())?.0)}
fn record(row: &sqlx::postgres::PgRow) -> Value {
    let mut value:Value=row.get("payload");
    value["id"]=json!(row.get::<String,_>("id"));
    value["version"]=json!(row.get::<i64,_>("version"));
    if let Ok(attachment)=row.try_get::<Value,_>("attachment") {value["archivo"]=attachment;}
    value
}
#[derive(Deserialize)]
struct Page { limit:Option<i64>,cursor:Option<String> }
async fn me(State(state):State<AppState>,Extension(user):Extension<Principal>) -> ResultJson {
    Ok(Json(json!({"sub":user.sub,"capabilities":{"read":true,"write":state.maintenance.operational()}})))
}
async fn system_version(State(state):State<AppState>) -> ResultJson {
    let op=state.maintenance.operation()?;
    let mut info=release::info();
    info["instanceId"]=json!(state.maintenance.instance_id);
    info["phase"]=json!(op.as_ref().map(|o|o.phase));
    info["operational"]=json!(state.maintenance.operational());
    info["capabilities"]=json!({"read":true,"write":state.maintenance.operational(),"maintenanceProtocol":1});
    Ok(Json(info))
}
fn diagnostic_references(state:&AppState,scope:Option<&DiagnosticScope>,value:&Value) -> Result<(),ApiError> {
    if let Some(scope)=scope {
        for (field,collection) in [("propiedadId","propiedades"),("inquilinoId","inquilinos"),("edificioId","edificios")] {
            if let Some(id)=value.get(field).and_then(Value::as_str).filter(|id|!id.is_empty()) {
                let fixture=Fixture {collection:collection.into(),id:id.into()};
                if !scope.allowed.contains(&fixture) || !state.maintenance.owns(&fixture) {return Err(ApiError::maintenance());}
            }
        }
    }
    Ok(())
}
async fn list(State(state):State<AppState>,Path(collection):Path<String>,Query(page):Query<Page>) -> ResultJson {
    domain::kind(&collection)?;
    let limit=page.limit.unwrap_or(50);
    if !(1..=200).contains(&limit) || page.cursor.as_ref().is_some_and(|v|v.len()>128) {return Err(ApiError::invalid());}
    let rows=sqlx::query("SELECT id,payload,version,COALESCE((SELECT jsonb_build_object('nombre',filename,'size',octet_length(content)) FROM document_files WHERE document_id=entities.id AND entities.kind='documentos'),'null'::jsonb) AS attachment FROM entities WHERE kind=$1 AND NOT archived AND id>$2 ORDER BY id LIMIT $3")
        .bind(&collection).bind(page.cursor.unwrap_or_default()).bind(limit+1).fetch_all(&state.db).await?;
    let more=rows.len()>limit as usize;
    let data:Vec<Value>=rows.iter().take(limit as usize).map(record).collect();
    let next=if more {data.last().map(|v|v["id"].clone())} else {None};
    Ok(Json(json!({"data":data,"nextCursor":next})))
}
async fn detail(State(state):State<AppState>,Path((collection,id)):Path<(String,String)>) -> ResultJson {
    domain::kind(&collection)?;
    let row=sqlx::query("SELECT id,payload,version,COALESCE((SELECT jsonb_build_object('nombre',filename,'size',octet_length(content)) FROM document_files WHERE document_id=entities.id AND entities.kind='documentos'),'null'::jsonb) AS attachment FROM entities WHERE kind=$1 AND id=$2 AND NOT archived").bind(collection).bind(id).fetch_optional(&state.db).await?.ok_or_else(ApiError::missing)?;
    Ok(Json(record(&row)))
}
async fn references(tx:&mut Transaction<'_,Postgres>,value:&Value) -> Result<(),ApiError> {
    if let Some(tenant)=value.get("inquilinoId").and_then(Value::as_str).filter(|id|!id.is_empty()) {
        let property=value.get("propiedadId").and_then(Value::as_str).ok_or_else(ApiError::invalid)?;
        let linked=sqlx::query("SELECT id FROM entities WHERE kind='inquilinos' AND id=$1 AND NOT archived AND COALESCE((payload->>'activo')::boolean,true) AND payload->>'propiedadId'=$2 FOR SHARE")
            .bind(tenant).bind(property).fetch_optional(&mut **tx).await?;
        if linked.is_none() {return Err(ApiError::invalid());}
    }
    for (field,kind) in [("propiedadId","propiedades"),("inquilinoId","inquilinos"),("edificioId","edificios")] {
        if let Some(id)=value.get(field).and_then(Value::as_str).filter(|id|!id.is_empty()) {
            let exists=sqlx::query("SELECT id FROM entities WHERE kind=$1 AND id=$2 AND NOT archived FOR SHARE").bind(kind).bind(id).fetch_optional(&mut **tx).await?;
            if exists.is_none() {return Err(ApiError::invalid());}
        }
    }
    Ok(())
}
async fn ensure_property_available(tx:&mut Transaction<'_,Postgres>,property_id:&str,tenant_id:Option<&str>,active:bool) -> Result<(),ApiError> {
    if !active {return Ok(())}
    let property=sqlx::query("SELECT id FROM entities WHERE kind='propiedades' AND id=$1 AND NOT archived FOR UPDATE")
        .bind(property_id).fetch_optional(&mut **tx).await?;
    if property.is_none() {return Err(ApiError::invalid())}
    let occupied=if let Some(tenant_id)=tenant_id {
        sqlx::query_scalar::<_,bool>("SELECT EXISTS(SELECT 1 FROM entities WHERE kind='inquilinos' AND id<>$2 AND NOT archived AND COALESCE((payload->>'activo')::boolean,true) AND payload->>'propiedadId'=$1)")
            .bind(property_id).bind(tenant_id).fetch_one(&mut **tx).await?
    } else {
        sqlx::query_scalar::<_,bool>("SELECT EXISTS(SELECT 1 FROM entities WHERE kind='inquilinos' AND NOT archived AND COALESCE((payload->>'activo')::boolean,true) AND payload->>'propiedadId'=$1)")
            .bind(property_id).fetch_one(&mut **tx).await?
    };
    if occupied {return Err(ApiError::conflict())}
    Ok(())
}
async fn audit(tx:&mut Transaction<'_,Postgres>,user:&Principal,action:&str,kind:&str,id:&str) -> Result<(),ApiError> {
    sqlx::query("INSERT INTO audit_events(actor,action,resource_kind,resource_id) VALUES($1,$2,$3,$4)").bind(&user.sub).bind(action).bind(kind).bind(id).execute(&mut **tx).await?;
    Ok(())
}
async fn create(State(state):State<AppState>,Extension(user):Extension<Principal>,Path(collection):Path<String>,scope:Option<Extension<DiagnosticScope>>,input:Result<Json<Value>,JsonRejection>) -> ResultJson {
    domain::kind(&collection)?;
    let mut value=body(input)?;
    if collection=="inquilinos" {domain::validate_new_tenant(&value)?;}
    domain::validate(&collection,&mut value)?;
    diagnostic_references(&state,scope.as_ref().map(|s|&s.0),&value)?;
    let mut tx=state.db.begin().await?;
    if collection=="inquilinos" {ensure_property_available(&mut tx,value["propiedadId"].as_str().unwrap_or_default(),None,value["activo"].as_bool().unwrap_or(true)).await?;}
    references(&mut tx,&value).await?;
    let id=scope.as_ref().map(|s|s.fixture.id.clone()).unwrap_or_else(||uuid::Uuid::new_v4().to_string());
    if scope.is_some() {
        let exists:bool=sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM audit_events WHERE resource_kind=$1 AND resource_id=$2)").bind(&collection).bind(&id).fetch_one(&mut *tx).await?;
        if exists {return Err(ApiError::conflict());}
    }
    let row=sqlx::query("INSERT INTO entities(kind,id,payload) VALUES($1,$2,$3) RETURNING id,payload,version").bind(&collection).bind(&id).bind(value).fetch_one(&mut *tx).await?;
    audit(&mut tx,&user,"create",&collection,&id).await?;
    tx.commit().await?;
    if let Some(scope)=scope {state.maintenance.remember(scope.fixture.clone())?;}
    Ok(Json(record(&row)))
}
async fn update(State(state):State<AppState>,Extension(user):Extension<Principal>,Path((collection,id)):Path<(String,String)>,scope:Option<Extension<DiagnosticScope>>,input:Result<Json<Value>,JsonRejection>) -> ResultJson {
    domain::kind(&collection)?;
    let mut patch=body(input)?;
    let expected=patch.get("version").and_then(Value::as_i64).filter(|v|*v>0).ok_or_else(ApiError::invalid)?;
    patch.as_object_mut().ok_or_else(ApiError::invalid)?.remove("version");
    let mut tx=state.db.begin().await?;
    let current=sqlx::query("SELECT payload,version FROM entities WHERE kind=$1 AND id=$2 AND NOT archived FOR UPDATE").bind(&collection).bind(&id).fetch_optional(&mut *tx).await?.ok_or_else(ApiError::missing)?;
    if current.get::<i64,_>("version")!=expected {return Err(ApiError::conflict());}
    let mut value:Value=current.get("payload");
    for (key,v) in patch.as_object().ok_or_else(ApiError::invalid)? {value[key]=v.clone();}
    domain::validate(&collection,&mut value)?;
    diagnostic_references(&state,scope.as_ref().map(|s|&s.0),&value)?;
    if collection=="inquilinos" {ensure_property_available(&mut tx,value["propiedadId"].as_str().unwrap_or_default(),Some(&id),value["activo"].as_bool().unwrap_or(true)).await?;}
    references(&mut tx,&value).await?;
    let row=sqlx::query("UPDATE entities SET payload=$3,version=version+1,updated_at=now() WHERE kind=$1 AND id=$2 RETURNING id,payload,version").bind(&collection).bind(&id).bind(value).fetch_one(&mut *tx).await?;
    audit(&mut tx,&user,"update",&collection,&id).await?;
    tx.commit().await?;
    Ok(Json(record(&row)))
}
#[derive(Deserialize)]
struct Version { version:i64 }
async fn archive(State(state):State<AppState>,Extension(user):Extension<Principal>,Path((collection,id)):Path<(String,String)>,scope:Option<Extension<DiagnosticScope>>,Query(expected):Query<Version>) -> ResultJson {
    domain::kind(&collection)?;
    let mut tx=state.db.begin().await?;
    let current=sqlx::query("SELECT version FROM entities WHERE kind=$1 AND id=$2 AND NOT archived FOR UPDATE").bind(&collection).bind(&id).fetch_optional(&mut *tx).await?.ok_or_else(ApiError::missing)?;
    if current.get::<i64,_>("version")!=expected.version {return Err(ApiError::conflict());}
    if let Some(scope)=scope {
        sqlx::query("DELETE FROM entities WHERE kind=$1 AND id=$2").bind(&collection).bind(&id).execute(&mut *tx).await?;
        sqlx::query("DELETE FROM audit_events WHERE resource_kind=$1 AND resource_id=$2 AND actor=$3").bind(&collection).bind(&id).bind(&user.sub).execute(&mut *tx).await?;
        tx.commit().await?;state.maintenance.forget(&scope.fixture)?;
        return Ok(Json(json!({"id":id,"deleted":true})));
    }
    if collection=="propiedades" {
        let count:i64=sqlx::query_scalar("SELECT count(*) FROM entities WHERE property_id=$1 AND NOT archived").bind(&id).fetch_one(&mut *tx).await?;
        if count>0 {return Err(ApiError::conflict());}
    }
    if collection=="edificios" {
        let count:i64=sqlx::query_scalar("SELECT count(*) FROM entities WHERE building_id=$1 AND NOT archived").bind(&id).fetch_one(&mut *tx).await?;
        if count>0 {return Err(ApiError::conflict());}
    }
    sqlx::query("UPDATE entities SET archived=true,version=version+1,updated_at=now() WHERE kind=$1 AND id=$2").bind(&collection).bind(&id).execute(&mut *tx).await?;
    audit(&mut tx,&user,"archive",&collection,&id).await?;
    tx.commit().await?;
    Ok(Json(json!({"id":id,"archived":true,"version":expected.version+1})))
}
#[derive(Deserialize)]
struct Month { mes:String }
async fn payment_rows(state:&AppState,month:&str) -> Result<Vec<Value>,ApiError> {
    let rows=sqlx::query("SELECT e.id AS tenant,e.payload,p.id AS payment_id,p.estado,p.nota,p.version,p.fecha::text AS fecha,COALESCE(p.amount_due::text,e.payload->>'renta') AS amount_due,p.amount_paid::text AS amount_paid FROM entities e LEFT JOIN pagos p ON p.inquilino_id=e.id AND p.mes=$1 WHERE e.kind='inquilinos' AND NOT e.archived AND COALESCE((e.payload->>'activo')::boolean,true) ORDER BY e.id")
        .bind(month).fetch_all(&state.db).await?;
    Ok(rows.iter().map(|row| {
        let payload:Value=row.get("payload");
        if !domain::contract_active_in_month(&payload,month)? {return Ok(None);}
        let due:Option<String>=row.get("amount_due");
        let paid:Option<String>=row.get("amount_paid");
        let amounts=domain::payment_amounts(due.as_deref(),paid.as_deref())?;
        let status=domain::payment_status(due.as_deref(),paid.as_deref())?;
        let mut result=json!({"id":row.get::<Option<String>,_>("payment_id"),"inquilinoId":row.get::<String,_>("tenant"),"nombre":payload["nombre"],"mes":month,"renta":payload["renta"],"estado":status,"nota":row.get::<Option<String>,_>("nota").unwrap_or_default(),"fecha":row.get::<Option<String>,_>("fecha"),"version":row.get::<Option<i64>,_>("version").unwrap_or(0),"importeAbonado":amounts["amountPaid"]});
        for (key,value) in amounts.as_object().ok_or_else(ApiError::invalid)? {result[key]=value.clone();}
        Ok(Some(result))
    }).collect::<Result<Vec<_>,ApiError>>()?.into_iter().flatten().collect())
}
async fn payments(State(state):State<AppState>,Query(query):Query<Month>) -> ResultJson {
    domain::month(&query.mes)?;
    Ok(Json(json!({"data":payment_rows(&state,&query.mes).await?})))
}
async fn dashboard(State(state):State<AppState>,Query(query):Query<Month>) -> ResultJson {
    domain::month(&query.mes)?;
    let payments=payment_rows(&state,&query.mes).await?;
    let mut due_total=0i64;
    let mut paid_total=0i64;
    let mut balance_total=0i64;
    let mut unknown_paid=0usize;
    let mut unknown_balance=0usize;
    let mut paid=0usize;
    let mut partial=0usize;
    for payment in &payments {
        if let Some(value)=payment["amountDue"].as_str() {due_total=due_total.checked_add(domain::cents(value)?).ok_or_else(ApiError::invalid)?;}
        if let Some(value)=payment["amountPaid"].as_str() {paid_total=paid_total.checked_add(domain::cents(value)?).ok_or_else(ApiError::invalid)?;} else {unknown_paid+=1;}
        if let (Some(due),Some(paid))=(payment["amountDue"].as_str(),payment["amountPaid"].as_str()) {
            balance_total=balance_total.checked_add(domain::cents(due)?-domain::cents(paid)?).ok_or_else(ApiError::invalid)?;
        } else {unknown_balance+=1;}
        match payment["estado"].as_str() {Some("pagado")=>paid+=1,Some("parcial")=>partial+=1,_=>{}}
    }
    Ok(Json(json!({"mes":query.mes,"moneda":"EUR","inquilinosActivos":payments.len(),"pagados":paid,"parciales":partial,"pendientes":payments.len()-paid-partial,
        "knownAmountDue":domain::money(due_total),"knownAmountPaid":domain::money(paid_total),"knownBalance":domain::money(balance_total),
        "unknownPaidCount":unknown_paid,"unknownBalanceCount":unknown_balance,"complete":unknown_paid==0 && unknown_balance==0,
        "cobradoReal":Value::Null,"limitacion":"Importes registrados; no conciliación bancaria. Totales limitados a cantidades conocidas."})))
}
async fn set_payment(State(state):State<AppState>,Extension(user):Extension<Principal>,Path((tenant,month)):Path<(String,String)>,input:Result<Json<Value>,JsonRejection>) -> ResultJson {
    domain::month(&month)?;
    let value=body(input)?;
    let object=value.as_object().ok_or_else(ApiError::invalid)?;
    if object.keys().any(|key|!matches!(key.as_str(),"estado"|"nota"|"version"|"amountDue"|"amountPaid")) {return Err(ApiError::invalid());}
    if let Some(status)=value.get("estado") {if !matches!(status.as_str(),Some("pagado"|"parcial"|"pendiente")) {return Err(ApiError::invalid());}}
    let note=match value.get("nota") {None=>"",Some(Value::String(s)) if s.len()<=5000=>s,_=>return Err(ApiError::invalid())};
    let due=domain::optional_amount(&value,"amountDue")?;
    let paid=domain::optional_amount(&value,"amountPaid")?;
    let expected=value["version"].as_i64().filter(|v|*v>=0).ok_or_else(ApiError::invalid)?;
    let mut tx=state.db.begin().await?;
    // Lock tenant to serialize creation of a previously absent tenant/month row.
    let active=sqlx::query("SELECT payload FROM entities WHERE kind='inquilinos' AND id=$1 AND NOT archived AND COALESCE((payload->>'activo')::boolean,true) FOR UPDATE").bind(&tenant).fetch_optional(&mut *tx).await?;
    if active.is_none() {return Err(ApiError::missing());}
    if !domain::contract_active_in_month(&active.as_ref().unwrap().get::<Value,_>("payload"),&month)? {return Err(ApiError::invalid());}
    let current=sqlx::query("SELECT id,version,amount_due::text AS amount_due,amount_paid::text AS amount_paid FROM pagos WHERE inquilino_id=$1 AND mes=$2 FOR UPDATE").bind(&tenant).bind(&month).fetch_optional(&mut *tx).await?;
    let version=current.as_ref().map(|r|r.get::<i64,_>("version")).unwrap_or(0);
    if expected!=version {return Err(ApiError::conflict());}
    let id=current.as_ref().map(|r|r.get::<String,_>("id")).unwrap_or_else(||uuid::Uuid::new_v4().to_string());
    let due=due.or_else(||current.as_ref().and_then(|r|r.get::<Option<String>,_>("amount_due"))).or_else(||active.as_ref().and_then(|r|r.get::<Value,_>("payload")["renta"].as_str().map(str::to_owned)));
    let paid=paid.or_else(||current.as_ref().and_then(|r|r.get::<Option<String>,_>("amount_paid")));
    let status=domain::payment_status(due.as_deref(),paid.as_deref())?;
    let amounts=domain::payment_amounts(due.as_deref(),paid.as_deref())?;
    sqlx::query("INSERT INTO pagos(id,inquilino_id,mes,estado,nota,amount_due,amount_paid) VALUES($1,$2,$3,$4,$5,$6::text::numeric,$7::text::numeric) ON CONFLICT(inquilino_id,mes) DO UPDATE SET estado=EXCLUDED.estado,nota=EXCLUDED.nota,amount_due=EXCLUDED.amount_due,amount_paid=EXCLUDED.amount_paid,version=pagos.version+1,fecha=CURRENT_DATE,updated_at=now()")
        .bind(&id).bind(&tenant).bind(&month).bind(status).bind(note).bind(&due).bind(&paid).execute(&mut *tx).await?;
    audit(&mut tx,&user,"set_payment","pagos",&id).await?;
    tx.commit().await?;
    let mut result=json!({"id":id,"inquilinoId":tenant,"mes":month,"estado":status,"nota":note,"version":version+1,"importeAbonado":amounts["amountPaid"]});
    for (key,value) in amounts.as_object().ok_or_else(ApiError::invalid)? {result[key]=value.clone();}
    Ok(Json(result))
}
