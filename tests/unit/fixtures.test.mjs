import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const data = JSON.parse(await readFile(new URL('../fixtures/domain.json', import.meta.url), 'utf8'));
test('synthetic fixtures have valid tenant and property relations', () => {
  const properties = new Set(data.propiedades.map(record => record.id));
  const buildings = new Set(data.edificios.map(record => record.id));
  for (const property of data.propiedades) assert.ok(buildings.has(property.edificioId));
  const tenants = new Set(data.inquilinos.map(record => record.id));
  for (const tenant of data.inquilinos) assert.ok(properties.has(tenant.propiedadId));
  for (const payment of data.pagos) assert.ok(tenants.has(payment.inquilinoId));
});
test('fixtures cover every legacy payment state without inventing partial amounts', () => {
  assert.deepEqual([...new Set(data.pagos.map(record => record.estado))].sort(), ['pagado', 'parcial', 'pendiente']);
  assert.equal(data.pagos.find(record => record.estado === 'parcial').importeAbonado, null);
  assert.equal(new Set(data.pagos.map(record => `${record.inquilinoId}/${record.mes}`)).size, data.pagos.length);
});
