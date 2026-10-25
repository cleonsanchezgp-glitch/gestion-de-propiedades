import { defineConfig } from 'vite';
const apiTarget=process.env.API_PROXY_TARGET || 'http://127.0.0.1:58080';
export default defineConfig({
  server: { host:'127.0.0.1', port:55173, strictPort:true, proxy:{ '/api':{target:apiTarget}, '/health':{target:apiTarget} } },
  preview:{host:'127.0.0.1',port:55173,strictPort:true}
});
