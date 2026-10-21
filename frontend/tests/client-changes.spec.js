import {test,expect} from '@playwright/test';
import {readFile} from 'node:fs/promises';
const settings=JSON.parse(await readFile(new URL('../../tests/.runtime/settings.json',import.meta.url),'utf8'));
for(const width of [1440,360])test(`estados, contratos y años a ${width}px`,async({page})=>{
  await page.setViewportSize({width,height:1000});
  await page.goto('/');
  await page.locator('#username').fill('gestor-local');
  await page.locator('#password').fill(settings.TEST_OWNER_PASSWORD);
  await page.getByRole('button',{name:'Entrar a mi portal'}).click();
  await expect(page.locator('#month')).toBeVisible();
  const call=async(path,method='GET',body)=>page.evaluate(async({path,method,body})=>{
    const response=await fetch('/api/v1'+path,{method,headers:{'Content-Type':'application/json'},body:body===undefined?undefined:JSON.stringify(body)});
    if(!response.ok)throw new Error(`${response.status} ${path}`);return response.json();
  },{path,method,body});
  const suffix=Date.now();
  const building=await call('/edificios','POST',{nombre:`Fechas ${suffix}`});
  const property=await call('/propiedades','POST',{nombre:`Vivienda ${suffix}`,edificioId:building.id});
  const tenant=await call('/inquilinos','POST',{nombre:`Contrato ${suffix}`,propiedadId:property.id,inicio:'2028-03-31',fin:'2028-05-01',renta:'600.00',dni:'PRUEBA',fianza:'600.00'});
  for(const [month,visible] of [['2028-02',false],['2028-03',true],['2028-05',true],['2028-06',false]]){
    const payments=await call(`/pagos?mes=${month}`);
    expect(payments.data.some(row=>row.inquilinoId===tenant.id)).toBe(visible);
  }
  await page.getByRole('button',{name:'Pagos',exact:true}).click();
  await page.locator('#month').fill('2028-03');
  await expect(page.getByRole('row').filter({hasText:tenant.nombre})).toBeVisible();
  await page.getByRole('button',{name:'Inquilinos',exact:true}).click();
  await page.getByRole('button',{name:'Nuevo inquilino'}).click();
  for(const name of ['DNI *','Renta actual *','Fianza *','Inicio del contrato *'])await expect(page.getByLabel(name,{exact:true})).toHaveAttribute('required','');
  const invalid=await page.evaluate(async propertyId=>{
    const valid={nombre:'Validación sintética',propiedadId:propertyId,dni:'PRUEBA',renta:'0.00',fianza:'0.00',inicio:'2024-02-29'};
    const statuses=[];
    for(const field of ['dni','renta','fianza','inicio']){
      const body={...valid};delete body[field];
      statuses.push((await fetch('/api/v1/inquilinos',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)})).status);
    }
    return statuses;
  },property.id);
  expect(invalid).toEqual([400,400,400,400]);
  await page.getByLabel('Inicio del contrato *',{exact:true}).fill('2024-02-29');
  await expect(page.locator('input[name=inicio]')).toHaveValue('2024-02-29');
  await page.getByRole('button',{name:'Cancelar',exact:true}).click();
  for(const estado of ['abierta','en_curso','resuelta'])await call('/incidencias','POST',{titulo:`Estado ${estado} ${suffix}`,estado,prioridad:'media'});
  await page.getByRole('button',{name:'Incidencias',exact:true}).click();
  const colors=[];
  for(const estado of ['abierta','en_curso','resuelta']){
    const badge=page.locator('.record-card').filter({hasText:`Estado ${estado} ${suffix}`}).locator('.issue-status');
    await expect(badge).toHaveClass(new RegExp(estado));colors.push(await badge.evaluate(e=>getComputedStyle(e).color));
  }
  expect(new Set(colors).size).toBe(3);
  expect(await page.evaluate(()=>document.documentElement.scrollWidth)).toBeLessThanOrEqual(width);
});
