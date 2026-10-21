import {defineConfig} from '@playwright/test';
export default defineConfig({testDir:'./tests',testMatch:'update.spec.js',workers:1,timeout:30000,
  use:{baseURL:'http://127.0.0.1:55173',headless:true},
  webServer:{command:'npm run dev',url:'http://127.0.0.1:55173',reuseExistingServer:true,timeout:30000}});
