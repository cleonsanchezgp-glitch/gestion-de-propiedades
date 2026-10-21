import {test,expect} from '@playwright/test';
async function portal(page,{oldBackend=false,incompatible=false,rejectWrite=false}={}){
  const state={authenticated:false,maintenance:false,properties:[],buildings:[],rejectWrite};
  await page.route('**/api/v1/**',async route=>{
    const request=route.request(),pathname=new URL(request.url()).pathname;
    const respond=(body,status=200)=>route.fulfill({status,contentType:'application/json',body:JSON.stringify(body)});
    if(pathname.endsWith('/session/login')){state.authenticated=true;return respond({authenticated:true});}
    if(!state.authenticated)return respond({error:{code:'UNAUTHORIZED'}},401);
    if(pathname.endsWith('/me'))return respond({sub:'fixture-owner'});
    if(pathname.endsWith('/system/version'))return oldBackend?respond({error:{code:'NOT_FOUND'}},404):respond({apiContract:incompatible?'unknown-contract':'propiedades-v3',capabilities:{read:true,write:!state.maintenance},operational:!state.maintenance});
    if(pathname.endsWith('/dashboard'))return respond({knownAmountPaid:0,knownBalance:0,unknownPaidCount:0,unknownBalanceCount:0,inquilinosActivos:0,pagados:0,parciales:0,pendientes:0,complete:true});
    if(request.method()==='POST'){
      if(state.rejectWrite||state.maintenance)return respond({error:{code:'MAINTENANCE_IN_PROGRESS',message:'maintenance'}},503);
      const target=pathname.endsWith('/edificios')?state.buildings:state.properties;
      const record={...request.postDataJSON(),id:pathname.endsWith('/edificios')?'fixture-building':'fixture-property',version:1};target.push(record);return respond(record);
    }
    return respond({data:pathname.endsWith('/edificios')?state.buildings:pathname.endsWith('/propiedades')?state.properties:[],nextCursor:null});
  });
  await page.clock.install();await page.goto('/');
  await page.getByLabel('Usuario',{exact:true}).fill('fixture-owner');await page.getByLabel('Contraseña',{exact:true}).fill('fixture-password');await page.getByRole('button',{name:'Entrar a mi portal'}).click();
  await page.getByRole('button',{name:'Propiedades',exact:true}).click();
  await expect(page.getByRole('button',{name:'+ Nuevo edificio'})).toBeVisible();return state;
}
test('maintenance polling preserves unsaved form and enables saving after verification',async({page})=>{
  const state=await portal(page);await page.getByRole('button',{name:'+ Nuevo edificio'}).click();
  await page.getByLabel('Nombre del edificio o urbanización *',{exact:true}).fill('Entrada que debe conservarse');
  state.maintenance=true;await page.clock.runFor(15000);await expect(page.getByRole('button',{name:'Guardar',exact:true})).toBeDisabled();
  await expect(page.getByLabel('Nombre del edificio o urbanización *',{exact:true})).toHaveValue('Entrada que debe conservarse');
  state.maintenance=false;await page.clock.runFor(15000);await expect(page.getByRole('button',{name:'Guardar',exact:true})).toBeEnabled();
  await expect(page.getByLabel('Nombre del edificio o urbanización *',{exact:true})).toHaveValue('Entrada que debe conservarse');await page.getByRole('button',{name:'Guardar',exact:true}).click();
  await expect(page.getByText('Cambios guardados en el servidor.')).toBeVisible();
});
test('backend maintenance rejection preserves input and blocks repeated saves',async({page})=>{
  await portal(page,{rejectWrite:true});await page.getByRole('button',{name:'+ Nuevo edificio'}).click();await page.getByLabel('Nombre del edificio o urbanización *',{exact:true}).fill('Formulario pendiente');await page.getByRole('button',{name:'Guardar',exact:true}).click();
  await expect(page.getByRole('dialog')).toBeVisible();await expect(page.getByLabel('Nombre del edificio o urbanización *',{exact:true})).toHaveValue('Formulario pendiente');
  await expect(page.locator('.form-error')).toContainText('Conserva este formulario');await expect(page.getByRole('button',{name:'Guardar',exact:true})).toBeDisabled();
});
test('backend without a version endpoint keeps reads but blocks incompatible writes',async({page})=>{
  await portal(page,{oldBackend:true});await expect(page.getByRole('button',{name:'+ Nuevo edificio'})).toBeDisabled();await expect(page.getByText('Esta interfaz necesita servicios actualizados antes de guardar.')).toBeVisible();
});
test('unrecognized contract permits reads but disables new writes',async({page})=>{
  await portal(page,{incompatible:true});await expect(page.getByRole('button',{name:'+ Nuevo edificio'})).toBeDisabled();await expect(page.getByText('Aún no hay edificios.')).toBeVisible();
});
