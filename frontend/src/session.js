export function createSession(){
  let authenticated=false;
  return {
    get authenticated(){return authenticated;},
    clearToken(){authenticated=false;},
    async init(){
      const response=await fetch('/api/v1/me',{credentials:'same-origin',cache:'no-store'});
      if(response.status===401||response.status===403)return false;
      if(!response.ok)throw new Error('No se puede comprobar la sesión. Comprueba que el servicio esté disponible.');
      authenticated=true;return true;
    },
    async login(credentials){
      const response=await fetch('/api/v1/session/login',{method:'POST',credentials:'same-origin',headers:{'Content-Type':'application/json'},body:JSON.stringify(credentials)});
      if(!response.ok)throw new Error(response.status===401?'Usuario o contraseña incorrectos.':response.status===403?'Esta cuenta no tiene acceso al portal.':'No se puede iniciar sesión en este momento.');
      authenticated=true;
    },
    async logout(){
      const response=await fetch('/api/v1/session/logout',{method:'POST',credentials:'same-origin'});
      if(!response.ok)throw new Error('No se pudo cerrar la sesión. Inténtalo de nuevo.');
      authenticated=false;
    }
  };
}
