import test from 'node:test';
import assert from 'node:assert/strict';
import {handleRequest} from '../../frontend/cloudflare/worker.js';
const env={API_ORIGIN:'https://api.example.com',CF_ACCESS_CLIENT_ID:'service-id',CF_ACCESS_CLIENT_SECRET:'service-secret',ASSETS:{fetch:async()=>new Response('portal')}};
test('assets are independent from API configuration',async()=>{
  const response=await handleRequest(new Request('https://portal.example.com/'),{ASSETS:env.ASSETS});
  assert.equal(await response.text(),'portal');
});
test('proxy preserves origin, cookie, body and query; returns HttpOnly cookie without caching',async()=>{
  const response=await handleRequest(new Request('https://portal.example.com/api/v1/session/login?x=1',{method:'POST',headers:{Origin:'https://portal.example.com',Cookie:'aelium_session=old','CF-Access-Client-Secret':'untrusted','Content-Type':'application/json'},body:'{"username":"owner","password":"test"}'}),env,async(request)=>{
    assert.equal(request.url,'https://api.example.com/api/v1/session/login?x=1');
    assert.equal(request.headers.get('Origin'),'https://portal.example.com');
    assert.equal(request.headers.get('Cookie'),'aelium_session=old');
    assert.equal(request.headers.get('CF-Access-Client-Secret'),'service-secret');
    assert.equal(request.redirect,'manual');
    assert.equal((await request.json()).username,'owner');
    return new Response('{}',{headers:{'Set-Cookie':'aelium_session=new; Path=/api; HttpOnly; Secure; SameSite=Strict'}});
  });
  assert.equal(response.headers.get('Cache-Control'),'no-store');
  assert.match(response.headers.get('Set-Cookie'),/HttpOnly; Secure/);
});
test('invalid upstream and missing secrets fail closed',async()=>{
  for(const overrides of [{API_ORIGIN:'http://localhost:58080'},{API_ORIGIN:'https://portal.example.com'},{CF_ACCESS_CLIENT_SECRET:''}]){
    const response=await handleRequest(new Request('https://portal.example.com/api/v1/clients'),{...env,...overrides},()=>{throw new Error('must not fetch');});
    assert.equal(response.status,503);
  }
});
test('offline server and upstream redirects produce a safe JSON error',async()=>{
  for(const send of [async()=>{throw new Error('offline');},async()=>new Response(null,{status:302,headers:{Location:'https://auth.example.com'}})]){
    const response=await handleRequest(new Request('https://portal.example.com/api/v1/clients'),env,send);
    assert.equal(response.status,502);
    assert.equal(response.headers.get('Cache-Control'),'no-store');
    assert.ok((await response.json()).error.message);
  }
});
