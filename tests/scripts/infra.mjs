import './prepare.mjs';
import { compose } from './compose.mjs';

const action = process.argv[2];
if (!['up', 'down'].includes(action)) throw new Error('Expected up or down.');
// Down affects only this Compose project; never deletes external volumes.
const result = compose(action === 'up' ? ['up', '-d'] : ['down']);
process.stdout.write(result.stdout || '');
process.stderr.write(result.stderr || '');
process.exitCode = result.status ?? 1;
