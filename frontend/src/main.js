import {frontendRelease} from './release.js';
import {createSession} from './session.js';
import {createApi} from './api.js';
import './style.css';

const root=document.querySelector('#app');
const escape=value=>String(value??'').replace(/[&<>"']/g,char=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[char]));
const money=value=>value===null||value===undefined?'Sin dato':new Intl.NumberFormat('es-ES',{style:'currency',currency:'EUR'}).format(value);
const now=new Date();
const state={view:'resumen',month:`${now.getFullYear()}-${String(now.getMonth()+1).padStart(2,'0')}`,data:[],summary:null,properties:[],buildings:[],selectedBuildingId:null,tenants:[],loading:false,error:'',notice:'',search:'',epoch:0,authorized:false};
const labels={resumen:'Resumen',propiedades:'Propiedades',inquilinos:'Inquilinos',pagos:'Pagos',incidencias:'Incidencias',documentos:'Documentos'};
let identity,api;
let maintenance=false;
let compatibilityBlocked=false;
async function refreshCapabilities(){
  if(!state.authorized)return;
  const epoch=state.epoch;
  try{const version=await api('/system/version');if(epoch!==state.epoch||!state.authorized)return;compatibilityBlocked=!frontendRelease.compatibleApiContracts.includes(version.apiContract);maintenance=version.capabilities?.write!==true||compatibilityBlocked;}
  catch(error){if(epoch!==state.epoch||!state.authorized)return;if(error.status===404){compatibilityBlocked=true;maintenance=true;}else if(error.status!==401&&error.status!==403)maintenance=true;}
  showMaintenance();
}
function showMaintenance(){
  const status=root.querySelector('#status');
  if(status&&!status.querySelector('[data-maintenance]'))status.insertAdjacentHTML('afterbegin','<div class="notice" data-maintenance role="status" hidden></div>');
  const banner=status?.querySelector('[data-maintenance]');if(banner){banner.hidden=!maintenance;banner.textContent=compatibilityBlocked?'Esta interfaz necesita servicios actualizados antes de guardar. Puedes seguir consultando la cartera.':'El programa se está actualizando. Puedes consultar y conservar tus formularios; espera para guardar.';}
  root.querySelectorAll('#new-record,[data-payment],[data-archive],#editor [type=submit]').forEach(button=>{button.disabled=maintenance||state.loading;});
}
setInterval(()=>{if(state.authorized)refreshCapabilities();},15000);
const skyline=`<svg viewBox="0 0 480 100" aria-hidden="true"><path d="M0 93H480M25 93V72H90V93M122 93V42H151V93M130 42V24H143V42M135 24V10M175 93V54H291V93M188 54V30H212V54M190 30Q200 9 210 30M251 54V30H275V54M253 30Q263 9 273 30M223 54V38Q233 14 243 38V54M314 93V44H335V93M318 44V26H331V44M324 26V12M361 93V69H417V93" fill="none" stroke="currentColor" stroke-width="2"/><path d="M0 99Q55 77 110 99T220 99T330 99T440 99" fill="none" stroke="currentColor"/></svg>`;
function gate(message='',pending=false){
  state.authorized=false;state.epoch++;state.data=[];state.summary=null;state.properties=[];state.buildings=[];state.selectedBuildingId=null;state.tenants=[];
  document.querySelector('dialog')?.close();
  root.innerHTML=`<main class="entry"><div class="entry-art"><div class="brand-lockup"><span class="brand-mark"><img src="/images/promalza-mark.png" alt=""></span><span class="brand-name">PROMALZA<small>PROPIEDADES</small></span></div><div><p class="eyebrow">ZARAGOZA · GESTIÓN INMOBILIARIA</p><h1>Un lugar para<br>tenerlo todo<br>en orden.</h1><p>Inmuebles, personas y cobros.<br>Tu gestión, desde cualquier dispositivo.</p></div>${skyline}</div><section class="entry-panel"><p class="eyebrow">TU ESPACIO DE GESTIÓN</p><h2>Bienvenido a casa.</h2><p>Accede a tu cartera de propiedades con tu cuenta autorizada.</p>${message?`<p class="alert" role="alert">${escape(message)}</p>`:''}<form id="login-form"><label class="field">Usuario<input id="username" name="username" autocomplete="username" required maxlength="200" ${pending?'disabled':''}></label><label class="field">Contraseña<input id="password" name="password" type="password" autocomplete="current-password" required maxlength="1024" ${pending?'disabled':''}></label><button class="primary" id="login" type="submit" ${pending?'disabled':''}>${pending?'Preparando acceso…':'Entrar a mi portal →'}</button></form><p class="fine">Acceso privado · Promalza</p></section></main>`;
  document.querySelector('#login-form').onsubmit=async event=>{
    event.preventDefault();const form=event.currentTarget;const button=form.querySelector('button');button.disabled=true;button.textContent='Comprobando acceso…';
    const credentials={username:form.username.value,password:form.password.value};form.password.value='';
    try {await identity.login(credentials);state.authorized=true;await load();}
    catch(error){gate(error.message||'No se puede iniciar sesión.');}
    finally{credentials.password='';}
  };
}
function shell(){
  const selectedBuilding=state.buildings.find(building=>building.id===state.selectedBuildingId);
  const propertyTitle=state.selectedBuildingId==='__unassigned__'?'Viviendas sin edificio':selectedBuilding?`Viviendas · ${selectedBuilding.nombre}`:'Edificios y viviendas';
  const heading=state.view==='propiedades'?propertyTitle:state.view==='resumen'?'Tu cartera, de un vistazo.':labels[state.view];
  const createLabel=state.view==='propiedades'?(state.selectedBuildingId&&state.selectedBuildingId!=='__unassigned__'?'Nueva vivienda':state.selectedBuildingId?'':'Nuevo edificio'):state.view==='inquilinos'?'Nuevo inquilino':state.view==='documentos'?'Nuevo documento':'Nueva incidencia';
  const breadcrumb=selectedBuilding?` / ${escape(selectedBuilding.nombre)}`:'';
  root.innerHTML=`<div class="workspace"><aside class="sidebar"><a class="wordmark brand-lockup" href="#resumen" aria-label="Promalza, ir al resumen"><span class="brand-mark"><img src="/images/promalza-mark.png" alt=""></span><span class="brand-name">ROMALZA<small>PROPIEDADES</small></span></a><p class="nav-label">TU CARTERA</p><nav aria-label="Secciones">${Object.entries(labels).map(([key,label],i)=>`<button data-view="${key}" class="nav-item ${state.view===key?'active':''}" ${state.view===key?'aria-current="page"':''}><span class="nav-number" aria-hidden="true">0${i+1}</span>${label}</button>`).join('')}</nav><div class="sidebar-foot">${skyline}<span>Zaragoza, en perspectiva.</span><button class="logout" id="logout">Cerrar sesión ↗</button></div></aside><div class="content"><header class="topbar"><span>Promalza / <strong>${labels[state.view]}</strong>${state.view==='propiedades'?breadcrumb:''}</span><span class="session-dot">Espacio privado</span></header><main><div class="page-heading"><div><p class="eyebrow">GESTIÓN DE PROPIEDADES</p><h1>${escape(heading)}</h1><p>${state.view==='propiedades'?(selectedBuilding?'Viviendas agrupadas en este edificio.':state.selectedBuildingId?'Asigna estas viviendas a un edificio para organizarlas.':'Crea primero un edificio; después podrás añadir sus viviendas aquí.'):state.view==='pagos'?'Cada importe, con su contexto.':state.view==='resumen'?'Una perspectiva clara de tus inmuebles y cobros.':'Toda la información, en un mismo lugar.'}</p></div>${['resumen','pagos'].includes(state.view)?`<label class="month-control">Período<input id="month" type="month" value="${state.month}" required></label>`:`<div class="heading-actions">${state.view==='propiedades'&&state.selectedBuildingId?'<button class="secondary" id="back-buildings">Edificios</button>':''}${createLabel?`<button class="primary" id="new-record">+ ${createLabel}</button>`:''}</div>`}</div><div id="status" aria-live="polite">${state.error?`<div class="alert" role="alert">${escape(state.error)} <button id="retry">Recargar</button></div>`:''}${state.notice?`<div class="notice">${escape(state.notice)}</div>`:''}</div><section id="view" ${state.loading?'aria-busy="true"':''}>${state.loading?'<div class="loading">Consultando tu cartera…</div>':view()}</section><footer>Gestión centralizada · Promalza <span>Los importes sin dato permanecen desconocidos.</span></footer></main></div></div><dialog id="editor"></dialog>`;
  root.querySelectorAll('[data-view]').forEach(button=>button.onclick=()=>{state.view=button.dataset.view;state.selectedBuildingId=null;state.search='';state.notice='';load();});
  root.querySelector('#logout').onclick=async()=>{try{await identity.logout();gate('Sesión cerrada.');}catch(error){state.error=error.message;shell();}};
  root.querySelector('#month')?.addEventListener('change',event=>{if(event.target.value){state.month=event.target.value;load();}});
  root.querySelector('#new-record')?.addEventListener('click',()=>editRecord(undefined,state.view==='propiedades'?(state.selectedBuildingId?'propiedades':'edificios'):state.view));
  root.querySelector('#back-buildings')?.addEventListener('click',()=>{state.selectedBuildingId=null;shell();});
  root.querySelector('#retry')?.addEventListener('click',load);
  root.querySelector('.wordmark').onclick=event=>{event.preventDefault();state.view='resumen';load();};
  bindView();showMaintenance();
}
function empty(title,description){return `<div class="empty"><span class="empty-mark">⌂</span><h2>${title}</h2><p>${description}</p></div>`;}
function view(){
  if(state.view==='resumen'){
    if(!state.summary)return empty('Tu resumen está pendiente.','Recarga para consultar la información.');
    const s=state.summary;
    return `<div class="metrics"><article class="metric dark"><span>Abonado registrado</span><strong>${money(s.knownAmountPaid)}</strong><small>${s.unknownPaidCount} registros sin importe abonado</small></article><article class="metric"><span>Saldo conocido</span><strong>${money(s.knownBalance)}</strong><small>${s.unknownBalanceCount} registros sin saldo calculable</small></article><article class="metric"><span>Inquilinos activos</span><strong>${escape(s.inquilinosActivos)}</strong><small>${escape(s.pagados)} pagados · ${escape(s.parciales)} parciales</small></article></div><div class="overview-grid"><article class="panel"><div class="panel-title"><h2>El mes en perspectiva</h2><span class="tag">${escape(state.month)}</span></div><div class="stat-row"><span>Pagados</span><strong>${escape(s.pagados)}</strong></div><div class="stat-row"><span>Parciales</span><strong>${escape(s.parciales)}</strong></div><div class="stat-row"><span>Pendientes</span><strong>${escape(s.pendientes)}</strong></div><p class="fine">${s.complete?'Todos los importes del resumen son conocidos.':'Resumen parcial: hay importes desconocidos.'} Los importes registrados no equivalen a conciliación bancaria.</p><button class="text-button" data-go-payments>Revisar pagos del mes →</button></article><article class="city-panel"><p class="eyebrow">TU CIUDAD, TU CARTERA</p><h2>Perspectiva local.<br>Gestión al día.</h2>${skyline}<p>La información cambia en el backend y se consulta desde tus dispositivos.</p></article></div>`;
  }
  if(state.view==='pagos'){
    if(!state.data.length)return empty('No hay contratos activos en este período.','Selecciona otro mes o revisa las fechas de los contratos.');
    return `<div class="panel"><div class="panel-title"><h2>Seguimiento mensual</h2><span class="tag">${state.data.length} inquilinos</span></div><div class="table-scroll"><table><thead><tr><th>Inquilino</th><th>Estado</th><th>Debido</th><th>Abonado</th><th>Saldo</th><th><span class="sr-only">Acciones</span></th></tr></thead><tbody>${state.data.map((p,i)=>`<tr><td><strong>${escape(p.nombre)}</strong><small>${escape(p.nota||'Sin nota')}</small></td><td><span class="badge ${escape(p.estado)}">${escape(p.estado)}</span></td><td>${money(p.amountDue)}</td><td>${money(p.amountPaid)}</td><td>${money(p.balance)}</td><td><button class="row-button" data-payment="${i}">Registrar</button></td></tr>`).join('')}</tbody></table></div><p class="fine panel-note">Los recibos adjuntos estarán disponibles cuando se complete el almacenamiento de archivos.</p></div>`;
  }
  if(state.view==='propiedades'){
    const unassigned=state.data.filter(property=>!property.edificioId);
    if(!state.selectedBuildingId){
      if(!state.buildings.length&&!unassigned.length)return empty('Aún no hay edificios.','Añade primero un edificio o urbanización. Después podrás incorporar sus viviendas.');
      return `<div class="record-grid">${state.buildings.map(building=>{const count=state.data.filter(property=>property.edificioId===building.id).length;return `<article class="record-card building-card"><div class="record-top"><span class="eyebrow">EDIFICIO</span><span class="record-symbol">⌂</span></div><h2>${escape(building.nombre)}</h2><p>${escape(building.direccion||'Edificio residencial')}</p><div class="record-detail"><span>Viviendas</span><strong>${count}</strong></div><div class="record-actions"><button class="text-button" data-open-building="${escape(building.id)}">Ver viviendas →</button><button class="text-button" data-edit-building="${escape(building.id)}">Editar</button><button class="text-button muted" data-archive-building="${escape(building.id)}">Archivar</button></div></article>`;}).join('')}${unassigned.length?`<article class="record-card building-card"><div class="record-top"><span class="eyebrow">PENDIENTE DE ASIGNACIÓN</span><span class="record-symbol">⌂</span></div><h2>Viviendas sin edificio</h2><p>Asigna las viviendas existentes a su edificio.</p><div class="record-detail"><span>Viviendas</span><strong>${unassigned.length}</strong></div><div class="record-actions"><button class="text-button" data-open-building="__unassigned__">Revisar viviendas →</button></div></article>`:''}</div>`;
    }
    const properties=state.data.filter(property=>state.selectedBuildingId==='__unassigned__'?!property.edificioId:property.edificioId===state.selectedBuildingId);
    const building=state.buildings.find(item=>item.id===state.selectedBuildingId);
    const locationBar=building?`<div class="building-location"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 21V4.8c0-.5.4-.8.9-.8H14v17M14 9h5.1c.5 0 .9.4.9.9V21M2 21h20M8 7h2m-2 4h2m-2 4h2m6-2h2m-2 4h2"/></svg><div class="building-location-copy"><strong>${escape(building.direccion||building.nombre)}</strong>${building.direccion&&building.nombre!==building.direccion?`<span>${escape(building.nombre)}</span>`:''}</div><div class="building-location-count">${properties.length} ${properties.length===1?'vivienda':'viviendas'}</div></div>`:'';
    if(!properties.length)return `${locationBar}${empty('Este edificio aún no tiene viviendas.','Añade la primera vivienda para que aparezca agrupada aquí.')}`;
    return `${locationBar}<div class="list-toolbar"><label class="search"><span>Buscar</span><input id="search" type="search" placeholder="Nombre o dirección" value="${escape(state.search)}"></label><span>${properties.length} viviendas</span></div><div class="record-grid">${properties.filter(item=>`${item.nombre||''} ${item.direccion||''}`.toLocaleLowerCase('es').includes(state.search.toLocaleLowerCase('es'))).map(item=>`<article class="record-card"><div class="record-top"><span class="eyebrow">VIVIENDA</span><span class="record-symbol">⌂</span></div><h2>${escape(item.nombre)}</h2><p>${escape(item.direccion||'Sin dirección adicional')}</p>${state.view==='documentos'?(item.archivo?`<a class="text-button document-download" href="/api/v1/documentos/${encodeURIComponent(item.id)}/archivo" download>${escape(item.archivo.nombre)} · Descargar ↓</a>`:'<p class="fine">Sin archivo adjunto</p>'):''}<div class="record-actions"><button class="text-button" data-edit="${escape(item.id)}">Editar →</button><button class="text-button muted" data-archive="${escape(item.id)}">Archivar</button></div></article>`).join('')}</div>`;
  }
  const items=state.data.filter(item=>`${item.nombre||item.titulo||''} ${item.direccion||''}`.toLocaleLowerCase('es').includes(state.search.toLocaleLowerCase('es')));
  return `<div class="list-toolbar"><label class="search"><span>Buscar</span><input id="search" type="search" placeholder="Nombre o dirección" value="${escape(state.search)}"></label><span>${state.data.length} registros</span></div>${state.view==='documentos'?'<p class="fine">Añade documentos a tu cartera y descarga sus archivos cuando los necesites.</p>':''}${!items.length?empty(state.data.length?'Sin coincidencias.':'Tu cartera empieza aquí.',state.data.length?'Prueba con otra búsqueda.':'Añade tu primer registro para empezar a organizarlo.'):`<div class="record-grid">${items.map(item=>`<article class="record-card"><div class="record-top"><span class="eyebrow">${labels[state.view]}</span><span class="record-symbol">↗</span></div><h2>${escape(item.nombre||item.titulo)}</h2><p>${escape(item.direccion||item.descripcion||item.email||item.tipo||'Sin información adicional')}</p>${state.view==='inquilinos'?`<div class="record-detail"><span>Renta actual</span><strong>${money(item.renta)}</strong></div>`:''}${state.view==='incidencias'?`<p class="issue-property"><span>Vivienda</span><strong>${escape(incidentProperty(item))}</strong></p><span class="badge issue-status ${escape(item.estado)}">${escape(item.estado.replace('_',' '))}</span>`:''}${state.view==='documentos'?(item.archivo?`<a class="text-button document-download" href="/api/v1/documentos/${encodeURIComponent(item.id)}/archivo" download>${escape(item.archivo.nombre)} · Descargar ↓</a>`:'<p class="fine">Sin archivo adjunto</p>'):''}<div class="record-actions"><button class="text-button" data-edit="${escape(item.id)}">Editar →</button><button class="text-button muted" data-archive="${escape(item.id)}">Archivar</button></div></article>`).join('')}</div>`}`;
}
function incidentProperty(item){
  const property=state.properties.find(property=>property.id===item.propiedadId);
  if(!property)return item.propiedadId?'Vivienda no disponible':'Sin vivienda asignada';
  const building=state.buildings.find(building=>building.id===property.edificioId);
  return `${building?.nombre||'Sin edificio'} · ${property.nombre}`;
}
function bindView(){
  root.querySelector('[data-go-payments]')?.addEventListener('click',()=>{state.view='pagos';load();});
  root.querySelectorAll('[data-payment]').forEach(button=>button.onclick=()=>editPayment(state.data[Number(button.dataset.payment)]));
  root.querySelectorAll('[data-edit]').forEach(button=>button.onclick=()=>editRecord(state.data.find(item=>item.id===button.dataset.edit)));
  root.querySelectorAll('[data-archive]').forEach(button=>button.onclick=()=>archiveRecord(state.data.find(item=>item.id===button.dataset.archive)));
  root.querySelectorAll('[data-open-building]').forEach(button=>button.onclick=()=>{state.selectedBuildingId=button.dataset.openBuilding;state.search='';shell();});
  root.querySelectorAll('[data-edit-building]').forEach(button=>button.onclick=()=>editRecord(state.buildings.find(item=>item.id===button.dataset.editBuilding),'edificios'));
  root.querySelectorAll('[data-archive-building]').forEach(button=>button.onclick=()=>archiveRecord(state.buildings.find(item=>item.id===button.dataset.archiveBuilding),'edificios'));
  root.querySelector('#search')?.addEventListener('input',event=>{state.search=event.target.value;const position=event.target.selectionStart;root.querySelector('#view').innerHTML=view();bindView();const input=root.querySelector('#search');input.focus();input.setSelectionRange(position,position);});
}
async function listAll(kind){
  let data=[],cursor;
  do {const result=await api(`/${kind}?limit=200${cursor?`&cursor=${encodeURIComponent(cursor)}`:''}`);data.push(...result.data);cursor=result.nextCursor;if(data.length>=10000&&cursor)throw new Error('La lista supera el límite de consulta. Reduce el volumen antes de continuar.');}while(cursor);
  return data;
}
async function load(){
  if(!state.authorized)return;
  const epoch=++state.epoch;const selected=state.view;state.error='';state.loading=true;shell();
  await refreshCapabilities();if(epoch!==state.epoch||!state.authorized)return;
  try {
    const result=selected==='resumen'?await api(`/dashboard?mes=${state.month}`):selected==='pagos'?await api(`/pagos?mes=${state.month}`):selected==='propiedades'?await Promise.all([listAll('edificios'),listAll('propiedades')]):selected==='incidencias'?await Promise.all([listAll('incidencias'),listAll('propiedades'),listAll('edificios')]):await listAll(selected);
    if(epoch!==state.epoch||!state.authorized)return;
    if(selected==='resumen')state.summary=result;else if(selected==='pagos')state.data=result.data;else if(selected==='propiedades'){state.buildings=result[0];state.data=result[1];}else if(selected==='incidencias'){[state.data,state.properties,state.buildings]=result;}else state.data=result;
  }catch(error){if(epoch!==state.epoch||!state.authorized)return;state.error=error.message==='Failed to fetch'?'No se puede conectar. Comprueba que el servicio esté disponible.':error.message;state.data=[];state.summary=null;}
  if(epoch===state.epoch&&state.authorized){state.loading=false;shell();}
}
const definitions={
  edificios:[['nombre','Nombre del edificio o urbanización',true],['direccion','Dirección'],['notas','Notas']],
  propiedades:[['nombre','Vivienda (piso, puerta o referencia)',true],['edificioId','Edificio',true,'edificios'],['direccion','Dirección'],['referencia','Referencia'],['superficie','Superficie'],['habitaciones','Habitaciones'],['notas','Notas']],
  inquilinos:[['nombre','Nombre',true],['propiedadId','Propiedad',true,'propiedades'],['dni','DNI',true],['telefono','Teléfono'],['email','Email'],['renta','Renta actual',true,'money'],['fianza','Fianza',true,'money'],['inicio','Inicio del contrato',true,'date'],['fin','Fin del contrato',false,'date'],['notas','Notas']],
  incidencias:[['titulo','Título',true],['propiedadId','Propiedad',false,'propiedades'],['estado','Estado',true,['abierta','en_curso','resuelta']],['prioridad','Prioridad',true,['baja','media','alta']],['descripcion','Descripción']],
  documentos:[['nombre','Nombre',true],['tipo','Tipo',true,['contrato','fianza','carta','otro']],['propiedadId','Propiedad',true,'propiedades'],['inquilinoId','Inquilino',true,'inquilinos'],['fecha','Fecha',false,'date'],['notas','Notas']]
};
function field([name,label,required=false,type],value='',{excludeTenantId,blockOccupied=false,showBuilding=false}={}){
  let control;
  if(Array.isArray(type)||type==='propiedades'||type==='inquilinos'||type==='edificios'){
    const options=Array.isArray(type)?type.map(v=>({id:v,nombre:v})):type==='propiedades'?state.properties:type==='edificios'?state.buildings:state.tenants;
    control=`<select name="${name}" ${required?'required':''}><option value="">Seleccionar</option>${options.map(item=>{const occupant=type==='propiedades'&&blockOccupied?state.tenants.find(tenant=>tenant.id!==excludeTenantId&&tenant.activo!==false&&tenant.propiedadId===item.id):null;return `<option value="${escape(item.id)}" ${item.id===value?'selected':''} ${occupant?'disabled':''}>${escape(type==='propiedades'&&showBuilding?`${state.buildings.find(building=>building.id===item.edificioId)?.nombre||'Sin edificio'} · ${item.nombre}`:item.nombre)}${occupant?' (Ocupada)':''}</option>`;}).join('')}</select>`;
  }else if(name==='notas'||name==='descripcion')control=`<textarea name="${name}" rows="3" maxlength="5000">${escape(value)}</textarea>`;
  else control=`<input name="${name}" type="${type==='date'?'date':name==='email'?'email':'text'}" value="${escape(value)}" ${required?'required':''} ${type==='money'?'inputmode="decimal" pattern="[0-9]+([.][0-9]{1,2})?" placeholder="0.00"':type==='date'?'':'maxlength="200"'}>`;
  control=control.replace(/^<(input|select|textarea)/,`<$1 aria-label="${label}${required?' *':''}"`);
  return `<label class="field">${label}${required?' *':''}${control}</label>`;
}
function dialog(title,fields,onSave,description=''){
  const editor=root.querySelector('#editor');if(!editor)return;
  editor.innerHTML=`<form><div class="dialog-heading"><h2>${title}</h2><button type="button" class="close" aria-label="Cerrar">×</button></div>${description?`<p class="fine">${description}</p>`:''}<div class="form-grid">${fields}</div><p class="form-error" role="alert"></p><div class="form-actions"><button type="button" class="secondary cancel">Cancelar</button><button class="primary" type="submit">Guardar</button></div></form>`;
  editor.querySelector('.close').onclick=()=>editor.close();editor.querySelector('.cancel').onclick=()=>editor.close();
  editor.querySelector('form').onsubmit=async event=>{
    event.preventDefault();const form=event.currentTarget;const button=form.querySelector('[type=submit]');if(maintenance){form.querySelector('.form-error').textContent='Espera a que termine la actualización. El formulario se conserva.';return;}button.disabled=true;button.textContent='Guardando…';
    try {await onSave(new FormData(form));if(!state.authorized)return;editor.close();state.notice='Cambios guardados en el servidor.';await load();}catch(error){if(error.code==='MAINTENANCE_IN_PROGRESS'){maintenance=true;showMaintenance();}if(editor.isConnected)form.querySelector('.form-error').textContent=error.message;}
    finally{button.disabled=maintenance;button.textContent='Guardar';}
  };
  editor.showModal();
  showMaintenance();
}
async function editRecord(item,kind=state.view){
  if(state.loading)return;
  const currentView=state.view;
  try {
    if(['inquilinos','incidencias','documentos'].includes(kind))state.properties=await listAll('propiedades');
    if(kind==='inquilinos')[state.tenants,state.buildings]=await Promise.all([listAll('inquilinos'),listAll('edificios')]);
    if(['propiedades','incidencias'].includes(kind))state.buildings=await listAll('edificios');
    if(kind==='documentos'){
      state.tenants=(await listAll('inquilinos')).filter(tenant=>tenant.activo!==false&&state.properties.some(property=>property.id===tenant.propiedadId));
      state.properties=state.properties.filter(property=>state.tenants.some(tenant=>tenant.propiedadId===property.id));
    }
    if(!state.authorized||state.view!==currentView)return;
    const title=kind==='edificios'?(item?'Editar edificio':'Nuevo edificio'):kind==='propiedades'?(item?'Editar vivienda':'Nueva vivienda'):item?'Editar registro':'Nuevo registro';
    const fields=definitions[kind].map(def=>field(def,item?.[def[0]]??(def[0]==='edificioId'&&kind==='propiedades'&&state.selectedBuildingId!=='__unassigned__'?state.selectedBuildingId:''),{excludeTenantId:item?.id,blockOccupied:kind==='inquilinos',showBuilding:['inquilinos','incidencias'].includes(kind)})).join('')+(kind==='documentos'?`<label class="field document-file">${item?.archivo?'Sustituir archivo':'Archivo *'}<input type="file" name="archivo" ${item?.archivo?'':'required'}><small>${item?.archivo?`Actual: ${escape(item.archivo.nombre)}. Selecciona otro para sustituirlo. `:''}Máximo 10 MB.</small></label>`:'');
    dialog(title,fields,async form=>{
      const body=Object.fromEntries(form);const file=form.get('archivo');delete body.archivo;
      for(const key of ['renta','fianza'])if(body[key]==='')delete body[key];
      if(kind==='documentos'&&file instanceof File&&file.name){
        if(!file.size||file.size>10*1024*1024)throw new Error('Selecciona un archivo de entre 1 byte y 10 MB.');
        await api(item?`/documentos/${encodeURIComponent(item.id)}/archivo`:'/documentos/archivo',{method:item?'PUT':'POST',file,metadata:{document:body,filename:file.name,version:item?.version}});return;
      }
      if(item)body.version=item.version;
      await api(`/${kind}${item?`/${encodeURIComponent(item.id)}`:''}`,{method:item?'PATCH':'POST',body});
    });
    if(kind==='documentos'){
      const property=root.querySelector('#editor [name=propiedadId]');
      const tenant=root.querySelector('#editor [name=inquilinoId]');
      property.addEventListener('change',()=>{tenant.value=state.tenants.find(item=>item.propiedadId===property.value)?.id||'';});
      tenant.addEventListener('change',()=>{property.value=state.tenants.find(item=>item.id===tenant.value)?.propiedadId||'';});
      if(tenant.value)property.value=state.tenants.find(item=>item.id===tenant.value)?.propiedadId||'';
      else if(property.value)tenant.value=state.tenants.find(item=>item.propiedadId===property.value)?.id||'';
    }
  }catch(error){if(state.authorized){state.error=error.message;shell();}}
}
function editPayment(payment){
  dialog(`Pago · ${escape(payment.nombre)}`,[field(['amountDue','Importe debido del período',false,'money'],payment.amountDue),field(['amountPaid','Total abonado',false,'money'],payment.amountPaid),field(['nota','Nota'],payment.nota)].join(''),async form=>{
    const body={nota:form.get('nota'),version:payment.version};
    for(const key of ['amountDue','amountPaid'])if(form.get(key))body[key]=form.get(key);
    await api(`/inquilinos/${encodeURIComponent(payment.inquilinoId)}/pagos/${state.month}`,{method:'PUT',body});
  },'El estado se calcula automáticamente: sin abono queda pendiente, con abono inferior al debido queda parcial y al cubrirlo queda pagado. Registra el total abonado; un importe en blanco conserva el valor existente.');
}
function archiveRecord(item,kind=state.view){
  dialog(kind==='edificios'?'Archivar edificio':'Archivar registro','',async()=>api(`/${kind}/${encodeURIComponent(item.id)}?version=${item.version}`,{method:'DELETE'}),`¿Archivar ${escape(item.nombre||item.titulo)}? Se retirará de la lista activa. Las relaciones protegidas pueden impedir la operación.`);
}
async function boot(){
  identity=createSession();api=createApi(identity,()=>gate('La sesión no permite acceder. Inicia sesión con tu cuenta autorizada.'));
  gate('',true);
  try {
    if(!await identity.init()){gate();return;}
    state.authorized=true;await load();
  }catch(error){gate(error.message||'No se pudo iniciar el acceso.');}
}
boot();


