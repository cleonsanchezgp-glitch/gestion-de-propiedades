// The browser always uses /api on the portal origin. Secrets stay in the Worker.
export async function handleRequest(request, env, send = fetch) {
  const incoming = new URL(request.url);
  if (incoming.pathname !== '/api' && !incoming.pathname.startsWith('/api/')) {
    return env.ASSETS.fetch(request);
  }
  let target;
  try {
    target = new URL(env.API_ORIGIN);
    if (target.protocol !== 'https:' || target.username || target.password ||
        target.pathname !== '/' || target.search || target.hash || target.origin === incoming.origin ||
        !env.CF_ACCESS_CLIENT_ID || !env.CF_ACCESS_CLIENT_SECRET) throw new Error('configuration');
  } catch {
    return Response.json({error:{message:'API no configurada.'}}, {status:503,headers:{'Cache-Control':'no-store'}});
  }
  target.pathname = incoming.pathname;
  target.search = incoming.search;
  const headers = new Headers(request.headers);
  headers.delete('Host');
  headers.delete('CF-Access-Jwt-Assertion');
  headers.set('CF-Access-Client-Id', env.CF_ACCESS_CLIENT_ID);
  headers.set('CF-Access-Client-Secret', env.CF_ACCESS_CLIENT_SECRET);
  try {
    const upstream = await send(new Request(target, {
      method:request.method, headers, redirect:'manual', duplex:'half',
      body:['GET','HEAD'].includes(request.method) ? undefined : request.body,
    }), { cf:{cacheTtl:0,cacheEverything:false} });
    // An Access login redirect must never take the browser away from the portal.
    if (upstream.status >= 300 && upstream.status < 400) throw new Error('redirect');
    const response = new Response(upstream.body, upstream);
    response.headers.set('Cache-Control','no-store');
    return response;
  } catch {
    return Response.json({error:{message:'El servidor local no está disponible.'}}, {status:502,headers:{'Cache-Control':'no-store'}});
  }
}
export default {fetch(request, env) { return handleRequest(request, env); }};
