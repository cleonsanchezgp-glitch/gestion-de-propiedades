-- Promote the former per-property recinto label into a reusable parent entity.
-- Existing properties with the same label are grouped under one migrated building.
ALTER TABLE entities DROP CONSTRAINT entities_kind_check;
ALTER TABLE entities ADD CONSTRAINT entities_kind_check
  CHECK (kind IN ('edificios','propiedades','inquilinos','incidencias','documentos'));
ALTER TABLE entities ADD COLUMN building_id text GENERATED ALWAYS AS (NULLIF(payload->>'edificioId','')) STORED;
ALTER TABLE entities ADD COLUMN building_kind text GENERATED ALWAYS AS ('edificios'::text) STORED;
ALTER TABLE entities ADD CONSTRAINT entities_building_fk
  FOREIGN KEY (building_kind,building_id) REFERENCES entities(kind,id);
CREATE INDEX entities_building ON entities(building_id);

INSERT INTO entities(kind,id,payload)
SELECT 'edificios', 'legacy-building-' || md5(trim(payload->>'recinto')),
       jsonb_build_object('nombre',trim(payload->>'recinto'))
FROM entities
WHERE kind='propiedades' AND nullif(trim(payload->>'recinto'),'') IS NOT NULL
GROUP BY trim(payload->>'recinto')
ON CONFLICT (kind,id) DO NOTHING;

UPDATE entities
SET payload=(payload - 'recinto') || jsonb_build_object(
    'edificioId','legacy-building-' || md5(trim(payload->>'recinto'))
)
WHERE kind='propiedades' AND nullif(trim(payload->>'recinto'),'') IS NOT NULL;
