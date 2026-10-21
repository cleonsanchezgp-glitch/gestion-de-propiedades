CREATE TABLE document_files (
    document_id text PRIMARY KEY,
    document_kind text GENERATED ALWAYS AS ('documentos'::text) STORED,
    filename text NOT NULL CHECK (length(filename) BETWEEN 1 AND 200),
    content bytea NOT NULL CHECK (octet_length(content) BETWEEN 1 AND 10485760),
    updated_at timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (document_kind,document_id) REFERENCES entities(kind,id) ON DELETE CASCADE
);
