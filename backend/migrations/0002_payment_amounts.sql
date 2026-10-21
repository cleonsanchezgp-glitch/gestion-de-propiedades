-- Existing amounts remain unknown; never infer them from status or current rent.
ALTER TABLE pagos ADD COLUMN amount_due numeric(12,2) CHECK (amount_due >= 0);
ALTER TABLE pagos ADD COLUMN amount_paid numeric(12,2) CHECK (amount_paid >= 0);
