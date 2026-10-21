use crate::error::ApiError;
use chrono::NaiveDate;
use serde_json::{Value, json};

pub fn kind(value: &str) -> Result<&str, ApiError> {
    match value { "edificios" | "propiedades" | "inquilinos" | "incidencias" | "documentos" => Ok(value), _ => Err(ApiError::missing()) }
}
pub fn month(value: &str) -> Result<(), ApiError> {
    if value.len() != 7 || !value.is_ascii() || &value[4..5] != "-" || !value[..4].bytes().all(|v|v.is_ascii_digit()) {
        return Err(ApiError::invalid());
    }
    let year = value[..4].parse::<u32>().map_err(|_|ApiError::invalid())?;
    let number = value[5..].parse::<u32>().map_err(|_|ApiError::invalid())?;
    if !(1..=9999).contains(&year) || !(1..=12).contains(&number) { return Err(ApiError::invalid()); }
    Ok(())
}
pub fn contract_active_in_month(value: &Value, period: &str) -> Result<bool, ApiError> {
    month(period)?;
    let start=value.get("inicio").and_then(Value::as_str).filter(|s|!s.is_empty());
    let end=value.get("fin").and_then(Value::as_str).filter(|s|!s.is_empty());
    // ISO dates sort chronologically; any day of overlap includes the contract.
    Ok(!start.is_some_and(|s|s.get(..7).is_some_and(|m|m>period))
        && !end.is_some_and(|s|s.get(..7).is_some_and(|m|m<period)))
}

#[cfg(test)]
mod contract_tests {
    use super::*;
    #[test]
    fn includes_only_months_overlapping_contract() {
        let tenant=json!({"inicio":"2026-03-31","fin":"2026-05-01"});
        for (period,expected) in [("2026-02",false),("2026-03",true),("2026-04",true),("2026-05",true),("2026-06",false)] {
            assert_eq!(contract_active_in_month(&tenant,period).unwrap(),expected);
        }
        assert!(contract_active_in_month(&json!({"inicio":"","fin":""}),"2026-01").unwrap());
        assert!(contract_active_in_month(&json!({"inicio":"2025-12-31"}),"2026-01").unwrap());
        assert!(!contract_active_in_month(&json!({"fin":"2025-12-31"}),"2026-01").unwrap());
        assert!(contract_active_in_month(&tenant,"2026-13").is_err());
    }
}

pub fn cents(value: &str) -> Result<i64, ApiError> {
    let parts: Vec<_> = value.split('.').collect();
    if parts.len() > 2 || parts[0].is_empty() || parts[0].len() > 10 || !parts[0].bytes().all(|v|v.is_ascii_digit()) { return Err(ApiError::invalid()); }
    let fraction = parts.get(1).copied().unwrap_or("00");
    if fraction.is_empty() || fraction.len() > 2 || !fraction.bytes().all(|v|v.is_ascii_digit()) { return Err(ApiError::invalid()); }
    let whole = parts[0].parse::<i64>().map_err(|_|ApiError::invalid())?;
    let decimal = fraction.parse::<i64>().map_err(|_|ApiError::invalid())? * if fraction.len() == 1 {10} else {1};
    Ok(whole * 100 + decimal)
}
pub fn money(value: i64) -> String {
    let magnitude=value.unsigned_abs();
    format!("{}{}.{:02}",if value<0 {"-"} else {""},magnitude/100,magnitude%100)
}
pub fn optional_amount(value: &Value, field: &str) -> Result<Option<String>,ApiError> {
    match value.get(field) {
        None | Some(Value::Null) => Ok(None),
        Some(Value::String(s)) => Ok(Some(money(cents(s)?))),
        _ => Err(ApiError::invalid())
    }
}
pub fn payment_amounts(due: Option<&str>, paid: Option<&str>) -> Result<Value,ApiError> {
    let due=due.map(cents).transpose()?;
    let paid=Some(paid.map(cents).transpose()?.unwrap_or(0));
    let balance=match (due,paid) {(Some(d),Some(p))=>Some(money(d-p)),_=>None};
    Ok(json!({"amountDue":due.map(money),"amountPaid":paid.map(money),"balance":balance,
        "amountUnknownReason":if due.is_none() || paid.is_none() {Some("amounts_missing")} else {None}}))
}
pub fn payment_status(due: Option<&str>, paid: Option<&str>) -> Result<&'static str,ApiError> {
    let paid=paid.map(cents).transpose()?.unwrap_or(0);
    if paid==0 {return Ok("pendiente")}
    if let Some(due)=due {
        if paid>=cents(due)? {return Ok("pagado")}
    }
    Ok("parcial")
}
fn text(value: &Value, field: &str, required: bool, limit: usize) -> Result<(), ApiError> {
    match value.get(field) {
        None if !required => Ok(()),
        Some(Value::String(s)) if s.len() <= limit && (!required || !s.trim().is_empty()) => Ok(()),
        _ => Err(ApiError::invalid())
    }
}
pub fn validate_new_tenant(value:&Value) -> Result<(),ApiError> {
    for field in ["dni","renta","fianza","inicio"] {text(value,field,true,200)?;}
    Ok(())
}
pub fn validate(kind: &str, value: &mut Value) -> Result<(), ApiError> {
    let object = value.as_object().ok_or_else(ApiError::invalid)?;
    let fields: &[&str] = match kind {
        "edificios" => &["nombre","direccion","notas"],
        "propiedades" => &["nombre","edificioId","referencia","direccion","superficie","habitaciones","ocupada","anyo","notas"],
        "inquilinos" => &["nombre","dni","telefono","email","renta","fianza","inicio","fin","propiedadId","activo","notas"],
        "incidencias" => &["titulo","propiedadId","prioridad","estado","descripcion","fecha"],
        "documentos" => &["nombre","tipo","propiedadId","inquilinoId","fecha","notas"],
        _ => return Err(ApiError::missing())
    };
    if object.keys().any(|key| !fields.contains(&key.as_str())) { return Err(ApiError::invalid()); }
    text(value, if kind=="incidencias" {"titulo"} else {"nombre"}, true, 200)?;
    for field in fields {
        if matches!(*field, "ocupada" | "activo") {
            if value.get(*field).is_some_and(|v|!v.is_boolean()) { return Err(ApiError::invalid()); }
        } else if matches!(*field,"renta"|"fianza") {
            if let Some(v) = value.get(*field) { let amount=cents(v.as_str().ok_or_else(ApiError::invalid)?)?; value[*field]=json!(money(amount)); }
        } else { text(value, field, false, if matches!(*field,"notas"|"descripcion") {5000} else {200})?; }
    }
    for field in ["inicio","fin","fecha"] {
        if let Some(v)=value.get(field).and_then(Value::as_str).filter(|v|!v.is_empty()) {
            if v.len()!=10 || NaiveDate::parse_from_str(v,"%Y-%m-%d").is_err() { return Err(ApiError::invalid()); }
        }
    }
    if let (Some(start),Some(end))=(value.get("inicio").and_then(Value::as_str),value.get("fin").and_then(Value::as_str)) {
        if !start.is_empty() && !end.is_empty() && end<start { return Err(ApiError::invalid()); }
    }
    if kind=="inquilinos" {
        text(value,"propiedadId",true,128)?;
        for field in ["renta","fianza"] { if value.get(field).is_none() { value[field]=json!("0.00"); } }
        if value.get("activo").is_none() { value["activo"]=json!(true); }
    }
    if kind=="propiedades" { text(value,"edificioId",true,128)?; }
    if kind=="propiedades" && value.get("ocupada").is_none() { value["ocupada"]=json!(false); }
    if kind=="incidencias" {
        if value.get("estado").is_none() {value["estado"]=json!("abierta");}
        if value.get("prioridad").is_none() {value["prioridad"]=json!("media");}
        if !matches!(value["estado"].as_str(),Some("abierta"|"en_curso"|"resuelta")) || !matches!(value["prioridad"].as_str(),Some("baja"|"media"|"alta")) {return Err(ApiError::invalid());}
    }
    if kind=="documentos" && !matches!(value["tipo"].as_str(),Some("contrato"|"fianza"|"carta"|"otro")) {return Err(ApiError::invalid());}
    if kind=="documentos" {
        text(value,"propiedadId",true,128)?;
        text(value,"inquilinoId",true,128)?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test] fn new_tenant_requires_contract_details_without_replacing_missing_amounts() {
        let valid=json!({"nombre":"Prueba","propiedadId":"x","dni":"PRUEBA","renta":"0.00","fianza":"0.00","inicio":"2024-02-29"});
        assert!(validate_new_tenant(&valid).is_ok());
        for field in ["dni","renta","fianza","inicio"] {
            let mut missing=valid.clone();missing.as_object_mut().unwrap().remove(field);
            assert!(validate_new_tenant(&missing).is_err());
            missing[field]=json!("   ");assert!(validate_new_tenant(&missing).is_err());
        }
    }
    #[test] fn decimal_money_is_exact_and_rejects_ambiguous_values() {
        assert_eq!(cents("0.10").unwrap_or(-1)+cents("0.20").unwrap_or(-1),30);
        for invalid in ["-1","NaN","1,23","1.234","1.","1e3","99999999999"] {assert!(cents(invalid).is_err());}
    }
    #[test] fn balances_are_exact_and_unknowns_are_preserved() {
        let amounts=payment_amounts(Some("600.00"),Some("250.00")).unwrap_or(Value::Null);
        assert_eq!(amounts["balance"],"350.00");
        assert_eq!(payment_amounts(Some("0.30"),Some("0.10")).unwrap_or(Value::Null)["balance"],"0.20");
        assert_eq!(payment_amounts(Some("600"),None).unwrap_or(Value::Null)["balance"],"600.00");
        assert_eq!(payment_amounts(Some("600"),None).unwrap_or(Value::Null)["amountPaid"],"0.00");
        assert!(payment_amounts(None,Some("250")).unwrap_or(Value::Null)["balance"].is_null());
        assert_eq!(money(-10),"-0.10");
        assert!(optional_amount(&json!({"amountPaid":250}),"amountPaid").is_err());
    }
    #[test] fn payment_status_is_derived_from_due_and_paid_amounts() {
        assert_eq!(payment_status(Some("450.00"),Some("0.00")).unwrap_or("invalid"),"pendiente");
        assert_eq!(payment_status(Some("450.00"),Some("200.00")).unwrap_or("invalid"),"parcial");
        assert_eq!(payment_status(Some("450.00"),Some("450.00")).unwrap_or("invalid"),"pagado");
        assert_eq!(payment_status(Some("450.00"),Some("500.00")).unwrap_or("invalid"),"pagado");
        assert_eq!(payment_status(None,None).unwrap_or("invalid"),"pendiente");
        assert_eq!(payment_status(None,Some("1.00")).unwrap_or("invalid"),"parcial");
    }
    #[test] fn months_reject_invalid_and_non_ascii_input_without_panicking() {
        for invalid in ["2026-00","2026-13","2026-1","0000-01","ééé-01","2026-1x"] {assert!(month(invalid).is_err());}
        assert!(month("2026-01").is_ok());
    }
    #[test] fn backend_rejects_reserved_fields_and_invalid_tenant_data() {
        assert!(validate("propiedades", &mut json!({"nombre":"Prueba","id":"injected"})).is_err());
        assert!(validate("inquilinos", &mut json!({"nombre":"Prueba","propiedadId":"x","renta":3.14})).is_err());
        assert!(validate("inquilinos", &mut json!({"nombre":"Prueba","propiedadId":"x","inicio":"2026-02-01","fin":"2026-01-01"})).is_err());
    }
    #[test] fn property_requires_a_building_reference_and_building_requires_a_name() {
        assert!(validate("propiedades", &mut json!({"nombre":"Piso 2A"})).is_err());
        assert!(validate("propiedades", &mut json!({"nombre":"Piso 2A","edificioId":"  "})).is_err());
        assert!(validate("propiedades", &mut json!({"nombre":"Piso 2A","edificioId":"building-1"})).is_ok());
        assert!(validate("edificios", &mut json!({"nombre":"  "})).is_err());
        assert!(validate("edificios", &mut json!({"nombre":"Residencial Los Olmos"})).is_ok());
    }
}
