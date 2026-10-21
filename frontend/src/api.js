export class ApiError extends Error {
  constructor(status,message,code){super(message);this.status=status;this.code=code;}
}
export function createApi(identity,onDenied) {
  return async function request(path,{method='GET',body,signal,file,metadata}={}) {
    if(!identity.authenticated) throw new ApiError(401,'Inicia sesión para continuar.');
    const headers=file?{'Content-Type':'application/octet-stream','X-Document-Metadata':JSON.stringify(metadata).replace(/[\u007f-\uffff]/g,char=>'\\u'+char.charCodeAt(0).toString(16).padStart(4,'0'))}:body===undefined?{}:{'Content-Type':'application/json'};
    const response=await fetch(`/api/v1${path}`,{method,signal,credentials:'same-origin',cache:'no-store',headers,body:file||(body===undefined?undefined:JSON.stringify(body))});
    if(response.status===401||response.status===403){identity.clearToken();onDenied();throw new ApiError(response.status,response.status===403?'Esta cuenta no tiene acceso al portal.':'Tu sesión ha caducado.');}
    const result=await response.json().catch(()=>({error:{message:response.status===413?'El archivo supera el máximo de 10 MB.':'No se pudo completar la operación.'}}));
    if(!response.ok) throw new ApiError(response.status,result.error?.code==='MAINTENANCE_IN_PROGRESS'?'El programa se está actualizando. Conserva este formulario y vuelve a guardar cuando termine.':response.status===409?'El registro ha cambiado. Recarga antes de guardar.':result.error?.message||'No se pudo completar la operación.',result.error?.code);
    return result;
  };
}
