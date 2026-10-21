-- Test harness schema, not the production schema or a production migration.
CREATE SCHEMA test_fixtures;
CREATE TABLE test_fixtures.propiedades (id text PRIMARY KEY, nombre text NOT NULL);
CREATE TABLE test_fixtures.inquilinos (
  id text PRIMARY KEY,
  propiedad_id text NOT NULL REFERENCES test_fixtures.propiedades(id)
);
CREATE TABLE test_fixtures.pagos (
  id text PRIMARY KEY,
  inquilino_id text NOT NULL REFERENCES test_fixtures.inquilinos(id),
  mes text NOT NULL CHECK (mes ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'),
  estado text NOT NULL CHECK (estado IN ('pagado', 'parcial', 'pendiente')),
  importe_abonado numeric(12,2) CHECK (importe_abonado >= 0),
  UNIQUE(inquilino_id, mes)
);
INSERT INTO test_fixtures.propiedades VALUES ('test-prop-001', 'Inmueble sintético');
INSERT INTO test_fixtures.inquilinos VALUES ('test-inq-001', 'test-prop-001');
INSERT INTO test_fixtures.pagos VALUES
  ('test-pago-001', 'test-inq-001', '2026-01', 'pagado', 450.00),
  ('test-pago-002', 'test-inq-001', '2026-02', 'parcial', NULL),
  ('test-pago-003', 'test-inq-001', '2026-03', 'pendiente', NULL);
