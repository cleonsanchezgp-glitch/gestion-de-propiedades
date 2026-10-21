# Instructions

- Following Playwright test failed.
- Explain why, be concise, respect Playwright best practices.
- Provide a snippet of code with the fix, if possible.

# Test info

- Name: frontend\tests\portal.spec.js >> login, persistencia de pago y cierre a 360px
- Location: frontend\tests\portal.spec.js:14:3

# Error details

```
Error: page.goto: Protocol error (Page.navigate): Cannot navigate to invalid URL
Call log:
  - navigating to "/", waiting until "load"

```

# Test source

```ts
  1  | import {test,expect} from '@playwright/test';
  2  | import {readFile,mkdir,writeFile} from 'node:fs/promises';
  3  | import {fileURLToPath} from 'node:url';
  4  | const settings=JSON.parse(await readFile(new URL('../../tests/.runtime/settings.json',import.meta.url),'utf8'));
  5  | async function login(page,other=false){
> 6  |   await page.goto('/');await expect(page.getByRole('button',{name:'Entrar a mi portal'})).toBeEnabled();
     |              ^ Error: page.goto: Protocol error (Page.navigate): Cannot navigate to invalid URL
  7  |   const directory=new URL('../../tests/artifacts/frontend/',import.meta.url);await mkdir(directory,{recursive:true});
  8  |   await page.screenshot({path:fileURLToPath(new URL(`login-${page.viewportSize().width}.png`,directory)),fullPage:true});
  9  |   await page.locator('#username').fill(other?'sin-acceso-local':'gestor-local');
  10 |   await page.locator('#password').fill(other?settings.TEST_OTHER_PASSWORD:settings.TEST_OWNER_PASSWORD);
  11 |   await page.getByRole('button',{name:'Entrar a mi portal'}).click();
  12 | }
  13 | for(const width of [1440,360]){
  14 |   test(`login, persistencia de pago y cierre a ${width}px`,async({page})=>{
  15 |     await page.setViewportSize({width,height:1000});
  16 |     await login(page);await expect(page.getByRole('heading',{name:'Tu cartera, de un vistazo.'})).toBeVisible();
  17 |     await page.getByRole('button',{name:'Propiedades',exact:true}).click();
  18 |     await page.getByRole('button',{name:'Nuevo edificio'}).click();
  19 |     const suffix=Date.now().toString();
  20 |     await page.getByLabel('Nombre del edificio o urbanización *',{exact:true}).fill(`Residencial prueba ${suffix}`);
  21 |     await page.getByLabel('Dirección',{exact:true}).fill('Zaragoza · Datos sintéticos');
  22 |     await page.getByRole('button',{name:'Guardar',exact:true}).click();
  23 |     await expect(page.getByRole('heading',{name:`Residencial prueba ${suffix}`})).toBeVisible();
  24 |     await page.getByRole('button',{name:'Ver viviendas'}).click();
  25 |     await page.getByRole('button',{name:'Nueva vivienda'}).click();
  26 |     await page.getByLabel('Nombre *',{exact:true}).fill(`Vivienda ${suffix}`);
  27 |     await page.getByLabel('Edificio *',{exact:true}).selectOption({label:`Residencial prueba ${suffix}`});
  28 |     await page.getByLabel('Dirección',{exact:true}).fill('Zaragoza · Datos sintéticos');
  29 |     await page.getByRole('button',{name:'Guardar',exact:true}).click();
  30 |     await expect(page.getByRole('heading',{name:`Vivienda ${suffix}`})).toBeVisible();
  31 |     await page.getByRole('button',{name:'Inquilinos',exact:true}).click();await page.getByRole('button',{name:'Nuevo inquilino'}).click();
  32 |     await page.getByLabel('Nombre *',{exact:true}).fill(`Persona prueba ${suffix}`);
  33 |     await page.getByLabel('Propiedad *',{exact:true}).selectOption({label:`Vivienda ${suffix}`});
  34 |     await page.getByLabel('Renta actual',{exact:true}).fill('600.00');
  35 |     await page.getByRole('button',{name:'Guardar',exact:true}).click();
  36 |     await expect(page.getByRole('heading',{name:`Persona prueba ${suffix}`})).toBeVisible();
  37 |     await page.getByRole('button',{name:'Pagos',exact:true}).click();
  38 |     const row=page.getByRole('row').filter({hasText:`Persona prueba ${suffix}`});
  39 |     await row.getByRole('button',{name:'Registrar'}).click();await page.getByLabel('Estado *').selectOption('parcial');
  40 |     await page.getByLabel('Importe debido del período').fill('600.00');await page.getByLabel('Total abonado').fill('250.00');
  41 |     await page.getByRole('button',{name:'Guardar',exact:true}).click();
  42 |     await expect(row).toContainText('350,00');
  43 |     await page.reload();await expect(page.getByRole('heading',{name:'Tu cartera, de un vistazo.'})).toBeVisible();
  44 |     await page.getByRole('button',{name:'Pagos',exact:true}).click();await expect(row).toContainText('350,00');
  45 |     await row.getByRole('button',{name:'Registrar'}).click();
  46 |     await page.route('**/api/v1/inquilinos/*/pagos/*',route=>route.request().method()==='PUT'?route.fulfill({status:409,contentType:'application/json',body:JSON.stringify({error:{code:'CONFLICT'}})}):route.continue());
  47 |     await page.getByRole('button',{name:'Guardar',exact:true}).click();
  48 |     await expect(page.getByRole('dialog')).toBeVisible();
  49 |     await expect(page.locator('.form-error')).toContainText('Recarga');
  50 |     await page.getByRole('button',{name:'Cancelar',exact:true}).click();
  51 |     await page.unroute('**/api/v1/inquilinos/*/pagos/*');
  52 |     await expect(row).toContainText('350,00');
  53 |     const directory=new URL('../../tests/artifacts/frontend/',import.meta.url);await mkdir(directory,{recursive:true});
  54 |     await page.screenshot({path:fileURLToPath(new URL(`pagos-${width}.png`,directory)),fullPage:true});
  55 |     const layout=await page.evaluate(()=>({width:innerWidth,scroll:document.documentElement.scrollWidth,overflow:[...document.querySelectorAll('body *')].filter(e=>!e.closest('.table-scroll')&&e.getBoundingClientRect().right>innerWidth+1).map(e=>e.tagName+'.'+e.className).slice(0,12)}));
  56 |     expect(layout.scroll,JSON.stringify(layout)).toBeLessThanOrEqual(width);
  57 |     await page.getByRole('button',{name:'Cerrar sesión'}).click();await expect(page.getByRole('button',{name:'Entrar a mi portal'})).toBeVisible();
  58 |     await expect(page.getByRole('heading',{name:`Persona prueba ${suffix}`})).toHaveCount(0);
  59 |     await writeFile(new URL(`browser-${width}.json`,directory),JSON.stringify({generatedAt:new Date().toISOString(),viewport:width,scope:'Portal form login validated by Keycloak, HttpOnly session, create property/tenant, persist amount/saldo, reload and logout; no production acceptance',status:'PASS'},null,2));
  60 |   });
  61 | }
  62 | test('otro usuario autenticado no accede al portal',async({page})=>{
  63 |   await login(page,true);await expect(page.getByRole('alert')).toContainText('acceso');
  64 |   await expect(page.getByRole('heading',{name:'Tu cartera, de un vistazo.'})).toHaveCount(0);
  65 | });
  66 | 
  67 | test('credenciales incorrectas, cookie protegida y cierre efectivo',async({page,context})=>{
  68 |   await page.goto('/');await page.getByLabel('Usuario',{exact:true}).fill('gestor-local');
  69 |   await page.getByLabel('Contraseña',{exact:true}).fill('incorrecta-sintetica');await page.getByRole('button',{name:'Entrar a mi portal'}).click();
  70 |   await expect(page.getByRole('alert')).toContainText('incorrectos');
  71 |   await expect(page).toHaveURL('http://127.0.0.1:55173/');
  72 |   await page.getByLabel('Usuario',{exact:true}).fill('gestor-local');await page.getByLabel('Contraseña',{exact:true}).fill(settings.TEST_OWNER_PASSWORD);
  73 |   await page.getByRole('button',{name:'Entrar a mi portal'}).click();await expect(page.getByRole('heading',{name:'Tu cartera, de un vistazo.'})).toBeVisible();
  74 |   const cookies=await context.cookies();const session=cookies.find(cookie=>cookie.name==='aelium_session');
  75 |   expect(session.httpOnly).toBeTruthy();expect(session.sameSite).toBe('Strict');
  76 |   const foreign=await context.request.post('/api/v1/propiedades',{headers:{Origin:'https://untrusted.example'},data:{nombre:'No debe crearse'}});expect(foreign.status()).toBe(403);
  77 |   const refreshed=await context.request.get('/api/v1/me');expect(refreshed.status()).toBe(200);
  78 |   await page.getByRole('button',{name:'Cerrar sesión'}).click();await expect(page.getByRole('button',{name:'Entrar a mi portal'})).toBeVisible();
  79 |   const stale=await context.request.get('/api/v1/me',{headers:{Cookie:`aelium_session=${session.value}`}});expect(stale.status()).toBe(401);
  80 | });
  81 | 
  82 | test('sesión renovada por backend al caducar el token de acceso',async({page,context})=>{
  83 |   test.setTimeout(90000);
  84 |   await login(page);await expect(page.getByRole('heading',{name:'Tu cartera, de un vistazo.'})).toBeVisible();
  85 |   // Local Keycloak tokens live for 60 seconds. Both reads must survive the original expiry.
  86 |   await page.waitForTimeout(31000);expect((await context.request.get('/api/v1/me')).status()).toBe(200);
  87 |   await page.waitForTimeout(31000);expect((await context.request.get('/api/v1/me')).status()).toBe(200);
  88 |   await page.getByRole('button',{name:'Cerrar sesión'}).click();await expect(page.getByRole('button',{name:'Entrar a mi portal'})).toBeVisible();
  89 | });
  90 | 
```