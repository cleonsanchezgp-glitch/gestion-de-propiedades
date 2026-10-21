import { startTestBackend } from './backend-process.mjs';
const child=await startTestBackend({owner:process.argv.includes('--owner')});
child.stdout.pipe(process.stdout);
child.stderr.pipe(process.stderr);
child.on('error',()=>{console.error('Build the backend and start test infrastructure first.');process.exitCode=1;});
child.on('exit',code=>{process.exitCode=code??1;});
for(const signal of ['SIGINT','SIGTERM']) process.on(signal,()=>child.kill());
