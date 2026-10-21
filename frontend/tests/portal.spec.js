import {test,expect} from '@playwright/test';
import {readFile,mkdir,writeFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
const settings=JSON.parse(await readFile(new URL('../../tests/.runtime/settings.json',import.meta.url),'utf8'));
async function login(page,other=false){
  await page.goto('/');await expect(page.getByRole('button',{name:'Entrar a mi portal'})).toBeEnabled();
  const directory=new URL('../../tests/artifacts/frontend/',import.meta.url);await mkdir(directory,{recursive:true});
  await page.screenshot({path:fileURLToPath(new URL(`login-${page.viewportSize().width}.png`,directory)),fullPage:true});
  await page.locator('#username').fill(other?'sin-acceso-local':'gestor-local');
  await page.locator('#password').fill(other?settings.TEST_OTHER_PASSWORD:settings.TEST_OWNER_PASSWORD);
  await page.getByRole('button',{name:'Entrar a mi portal'}).click();
}
for(const width of [1440,360]){
  test(`login, persistencia de pago y cierre a ${width}px`,async({page})=>{
    await page.setViewportSize({width,height:1000});
    await login(page);await expect(page.getByRole('heading',{name:'Tu cartera, de un vistazo.'})).toBeVisible();
    await page.getByRole('button',{name:'Propiedades',exact:true}).click();
    await page.getByRole('button',{name:'Nuevo edificio'}).click();
    const suffix=Date.now().toString();
    await page.getByLabel('Nombre del edificio o urbanización *',{exact:true}).fill(`Residencial prueba ${suffix}`);
    await page.getByLabel('Dirección',{exact:true}).fill('Zaragoza · Datos sintéticos');
    await page.getByRole('button',{name:'Guardar',exact:true}).click();
    await expect(page.getByRole('heading',{name:`Residencial prueba ${suffix}`})).toBeVisible();
    await page.locator('.building-card').filter({has:page.getByRole('heading',{name:`Residencial prueba ${suffix}`})}).getByRole('button',{name:'Ver viviendas'}).click();
    await expect(page.locator('.building-location')).toContainText('Zaragoza · Datos sintéticos');
    await expect(page.locator('.building-location')).toContainText(`Residencial prueba ${suffix}`);
    await page.getByRole('button',{name:'Nueva vivienda'}).click();
    await page.getByLabel('Vivienda (piso, puerta o referencia) *',{exact:true}).fill(`Vivienda ${suffix}`);
    await page.getByLabel('Edificio *',{exact:true}).selectOption({label:`Residencial prueba ${suffix}`});
    await page.getByLabel('Dirección',{exact:true}).fill('Zaragoza · Datos sintéticos');
    await page.getByRole('button',{name:'Guardar',exact:true}).click();
    await expect(page.getByRole('heading',{name:`Vivienda ${suffix}`})).toBeVisible();
    await page.getByRole('button',{name:'Inquilinos',exact:true}).click();await page.getByRole('button',{name:'Nuevo inquilino'}).click();
    await page.getByLabel('Nombre *',{exact:true}).fill(`Persona prueba ${suffix}`);
    await page.getByLabel('Propiedad *',{exact:true}).selectOption({label:`Residencial prueba ${suffix} · Vivienda ${suffix}`});
    await page.getByLabel('DNI *',{exact:true}).fill('PRUEBA');
    await page.getByLabel('Renta actual *',{exact:true}).fill('600.00');
    await page.getByLabel('Fianza *',{exact:true}).fill('600.00');
    await page.getByLabel('Inicio del contrato *',{exact:true}).fill('2020-01-01');
    await page.getByRole('button',{name:'Guardar',exact:true}).click();
    await expect(page.getByRole('heading',{name:`Persona prueba ${suffix}`})).toBeVisible();
    await page.getByRole('button',{name:'Inquilinos',exact:true}).click();await page.getByRole('button',{name:'Nuevo inquilino'}).click();
    await expect(page.getByLabel('Propiedad *',{exact:true}).locator('option',{hasText:`Vivienda ${suffix}`})).toHaveAttribute('disabled','');
    await page.getByRole('button',{name:'Cancelar',exact:true}).click();
    await page.getByRole('button',{name:'Pagos',exact:true}).click();
    const row=page.getByRole('row').filter({hasText:`Persona prueba ${suffix}`});
    await row.getByRole('button',{name:'Registrar'}).click();await expect(page.getByLabel('Importe debido del período')).toHaveValue('600.00');await expect(page.getByLabel('Estado *')).toHaveCount(0);
    await page.getByLabel('Importe debido del período').fill('600.00');await page.getByLabel('Total abonado').fill('250.00');
    await page.getByRole('button',{name:'Guardar',exact:true}).click();
    await expect(row).toContainText('350,00');await expect(row).toContainText('parcial');
    await page.reload();await expect(page.getByRole('heading',{name:'Tu cartera, de un vistazo.'})).toBeVisible();
    await page.getByRole('button',{name:'Pagos',exact:true}).click();await expect(row).toContainText('350,00');
    await row.getByRole('button',{name:'Registrar'}).click();
    await page.route('**/api/v1/inquilinos/*/pagos/*',route=>route.request().method()==='PUT'?route.fulfill({status:409,contentType:'application/json',body:JSON.stringify({error:{code:'CONFLICT'}})}):route.continue());
    await page.getByRole('button',{name:'Guardar',exact:true}).click();
    await expect(page.getByRole('dialog')).toBeVisible();
    await expect(page.locator('.form-error')).toContainText('Recarga');
    await page.getByRole('button',{name:'Cancelar',exact:true}).click();
    await page.unroute('**/api/v1/inquilinos/*/pagos/*');
    await expect(row).toContainText('350,00');
    const directory=new URL('../../tests/artifacts/frontend/',import.meta.url);await mkdir(directory,{recursive:true});
    await page.screenshot({path:fileURLToPath(new URL(`pagos-${width}.png`,directory)),fullPage:true});
    const layout=await page.evaluate(()=>({width:innerWidth,scroll:document.documentElement.scrollWidth,overflow:[...document.querySelectorAll('body *')].filter(e=>!e.closest('.table-scroll')&&e.getBoundingClientRect().right>innerWidth+1).map(e=>e.tagName+'.'+e.className).slice(0,12)}));
    expect(layout.scroll,JSON.stringify(layout)).toBeLessThanOrEqual(width);
    await page.getByRole('button',{name:'Cerrar sesión'}).click();await expect(page.getByRole('button',{name:'Entrar a mi portal'})).toBeVisible();
    await expect(page.getByRole('heading',{name:`Persona prueba ${suffix}`})).toHaveCount(0);
    await writeFile(new URL(`browser-${width}.json`,directory),JSON.stringify({generatedAt:new Date().toISOString(),viewport:width,scope:'Portal form login validated by Keycloak, HttpOnly session, create property/tenant, persist amount/saldo, reload and logout; no production acceptance',status:'PASS'},null,2));
  });
}
test('otro usuario autenticado no accede al portal',async({page})=>{
  await login(page,true);await expect(page.getByRole('alert')).toContainText('acceso');
  await expect(page.getByRole('heading',{name:'Tu cartera, de un vistazo.'})).toHaveCount(0);
});

test('credenciales incorrectas, cookie protegida y cierre efectivo',async({page,context})=>{
  await page.goto('/');await page.getByLabel('Usuario',{exact:true}).fill('gestor-local');
  await page.getByLabel('Contraseña',{exact:true}).fill('incorrecta-sintetica');await page.getByRole('button',{name:'Entrar a mi portal'}).click();
  await expect(page.getByRole('alert')).toContainText('incorrectos');
  await expect(page).toHaveURL('http://127.0.0.1:55173/');
  await page.getByLabel('Usuario',{exact:true}).fill('gestor-local');await page.getByLabel('Contraseña',{exact:true}).fill(settings.TEST_OWNER_PASSWORD);
  await page.getByRole('button',{name:'Entrar a mi portal'}).click();await expect(page.getByRole('heading',{name:'Tu cartera, de un vistazo.'})).toBeVisible();
  const cookies=await context.cookies();const session=cookies.find(cookie=>cookie.name==='aelium_session');
  expect(session.httpOnly).toBeTruthy();expect(session.sameSite).toBe('Strict');
  const foreign=await context.request.post('/api/v1/propiedades',{headers:{Origin:'https://untrusted.example'},data:{nombre:'No debe crearse'}});expect(foreign.status()).toBe(403);
  const refreshed=await context.request.get('/api/v1/me');expect(refreshed.status()).toBe(200);
  await page.getByRole('button',{name:'Cerrar sesión'}).click();await expect(page.getByRole('button',{name:'Entrar a mi portal'})).toBeVisible();
  const stale=await context.request.get('/api/v1/me',{headers:{Cookie:`aelium_session=${session.value}`}});expect(stale.status()).toBe(401);
});

test('sesión de treinta minutos con token Keycloak y cookie privada',async({page,context})=>{
  await login(page);await expect(page.getByRole('heading',{name:'Tu cartera, de un vistazo.'})).toBeVisible();
  const cookie=(await context.cookies()).find(cookie=>cookie.name==='aelium_session');
  expect(cookie.httpOnly).toBe(true);expect(cookie.sameSite).toBe('Strict');
  expect(cookie.expires-Date.now()/1000).toBeGreaterThan(1790);
  expect(cookie.expires-Date.now()/1000).toBeLessThanOrEqual(1800);
  const tokenResponse=await context.request.post('http://127.0.0.1:58081/realms/propiedades-test/protocol/openid-connect/token',{form:{grant_type:'password',client_id:'portal-local-login',client_secret:settings.TEST_LOGIN_SECRET,username:'gestor-local',password:settings.TEST_OWNER_PASSWORD}});
  expect(tokenResponse.status()).toBe(200);
  const tokens=await tokenResponse.json();const claims=JSON.parse(Buffer.from(tokens.access_token.split('.')[1],'base64url').toString());
  expect(claims.exp-claims.iat).toBeLessThanOrEqual(1800);expect(claims.exp-claims.iat).toBeGreaterThanOrEqual(1790);
  expect((await context.request.get('/api/v1/me')).status()).toBe(200);
  await page.getByRole('button',{name:'Cerrar sesión'}).click();await expect(page.getByRole('button',{name:'Entrar a mi portal'})).toBeVisible();
});
