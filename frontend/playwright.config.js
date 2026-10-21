import {defineConfig} from '@playwright/test';
export default defineConfig({
  testDir:'./tests',workers:1,timeout:60000,use:{baseURL:'http://127.0.0.1:55173',headless:true},
  webServer:[
    {command:'npm --prefix .. run backend:local',url:'http://127.0.0.1:58080/health/live',reuseExistingServer:true,timeout:60000},
    {command:'npm run dev',url:'http://127.0.0.1:55173',reuseExistingServer:true,timeout:60000}
  ]
});
