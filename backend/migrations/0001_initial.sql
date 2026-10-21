CREATE TABLE entities (
  kind text NOT NULL CHECK (kind IN ('propiedades','inquilinos','incidencias','documentos')),
  id text NOT NULL,
  payload jsonb NOT NULL CHECK (jsonb_typeof(payload) = 'object'),
  version bigint NOT NULL DEFAULT 1 CHECK (version > 0),
  archived boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  property_id text GENERATED ALWAYS AS (NULLIF(payload->>'propiedadId','')) STORED,
  property_kind text GENERATED ALWAYS AS ('propiedades'::text) STORED,
  tenant_id text GENERATED ALWAYS AS (NULLIF(payload->>'inquilinoId','')) STORED,
  tenant_kind text GENERATED ALWAYS AS ('inquilinos'::text) STORED,
  PRIMARY KEY (kind, id),
  FOREIGN KEY (property_kind, property_id) REFERENCES entities(kind,id),
  FOREIGN KEY (tenant_kind, tenant_id) REFERENCES entities(kind,id)
);
CREATE INDEX entities_active_list ON entities(kind,id) WHERE NOT archived;
CREATE INDEX entities_property ON entities(property_id);
CREATE INDEX entities_tenant ON entities(tenant_id);
CREATE TABLE pagos (
  id text NOT NULL UNIQUE,
  inquilino_id text NOT NULL,
  tenant_kind text GENERATED ALWAYS AS ('inquilinos'::text) STORED,
  mes text NOT NULL CHECK (mes ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'),
  estado text NOT NULL CHECK (estado IN ('pagado','parcial','pendiente')),
  nota text NOT NULL DEFAULT '',
  fecha date NOT NULL DEFAULT CURRENT_DATE,
  version bigint NOT NULL DEFAULT 1,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (inquilino_id,mes),
  FOREIGN KEY (tenant_kind,inquilino_id) REFERENCES entities(kind,id)
);
-- Keep payment history on archive. No cascading deletion of financial records.
CREATE TABLE audit_events (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  actor text NOT NULL,
  action text NOT NULL,
  resource_kind text NOT NULL,
  resource_id text NOT NULL,
  occurred_at timestamptz NOT NULL DEFAULT now()
);
