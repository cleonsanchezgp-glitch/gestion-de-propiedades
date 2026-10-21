import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../../', import.meta.url));
export function compose(args) {
  const command = process.env.TEST_COMPOSE_BIN || 'docker-compose';
  const result = spawnSync(command, ['--env-file', 'tests/.runtime/.env', '-f', 'tests/compose.yaml', ...args], {
    cwd: root, encoding: 'utf8', timeout: 240000, windowsHide: true
  });
  if (result.error) throw result.error;
  return result;
}
