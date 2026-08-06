# ── Pilot schema, Vannmiljø ──────────────────────────────────────────────────
# `site` carries the six seastamp location columns (named `country`, not
# `est_country`, unlike ICES-DOME / MUDAB / 4Demon), which the geo step fills.

pilot_schema_vannmiljo <- function() {
  list(
    order = c("activity", "client", "contractor", "site", "sample_method", "analysis_method", "parameter", "sample", "sediment", "lld"),
    ddl = list(
      activity = "
CREATE TABLE activity (
    activity_id TEXT NOT NULL PRIMARY KEY,
    activity_name TEXT NOT NULL
);",
      client = "
CREATE TABLE client (
    client_id INTEGER NOT NULL PRIMARY KEY,
    client TEXT NOT NULL,
    archive BOOLEAN NOT NULL
);",
      contractor = "
CREATE TABLE contractor (
    contractor_id INTEGER NOT NULL PRIMARY KEY,
    contractor TEXT NOT NULL
);",
      site = "
CREATE TABLE site (
    site_code TEXT NOT NULL PRIMARY KEY,
    site_name TEXT,
    label TEXT,
    lat REAL NOT NULL,
    lon REAL NOT NULL,
    dist_to_coast REAL,
    country TEXT,
    country_code TEXT,
    municipality TEXT,
    sea_name TEXT
);",
      sample_method = "
CREATE TABLE sample_method (
    method_id INTEGER NOT NULL PRIMARY KEY,
    method TEXT NOT NULL
);",
      analysis_method = "
CREATE TABLE analysis_method (
    analysis_id INTEGER NOT NULL PRIMARY KEY,
    analysis TEXT NOT NULL,
    unit TEXT NOT NULL
);",
      parameter = "
CREATE TABLE parameter (
    param_id TEXT NOT NULL PRIMARY KEY,
    param_name TEXT NOT NULL,
    cas_no TEXT
);",
      sample = "
CREATE TABLE sample (
    sample_id TEXT NOT NULL PRIMARY KEY,
    activity_id TEXT NOT NULL,
    site_code TEXT NOT NULL,
    client_id INTEGER NOT NULL,
    contractor_id INTEGER NOT NULL,
    method_id INTEGER NOT NULL,
    upper_depth REAL NOT NULL,
    lower_depth REAL NOT NULL,
    sample_time TEXT,
    filtered BOOLEAN,

    FOREIGN KEY (activity_id) REFERENCES activity (activity_id),
    FOREIGN KEY (site_code) REFERENCES site (site_code),
    FOREIGN KEY (client_id) REFERENCES client (client_id),
    FOREIGN KEY (contractor_id) REFERENCES contractor (contractor_id),
    FOREIGN KEY (method_id) REFERENCES sample_method (method_id)
);",
      sediment = "
CREATE TABLE sediment (
    sample_id TEXT NOT NULL,
    param_id TEXT NOT NULL,
    sediment_no INTEGER NOT NULL,
    analysis_id INTEGER NOT NULL,
    value REAL NOT NULL,
    operator TEXT,
    sample_no TEXT,
    n_values INTEGER,

    PRIMARY KEY (sample_id, param_id, sediment_no),

    FOREIGN KEY (sample_id) REFERENCES sample (sample_id),
    FOREIGN KEY (param_id) REFERENCES parameter (param_id),
    FOREIGN KEY (analysis_id) REFERENCES analysis_method (analysis_id)
);",
      lld = "
CREATE TABLE lld (
    sample_id TEXT NOT NULL,
    param_id TEXT NOT NULL,
    sediment_no INTEGER NOT NULL,
    type TEXT NOT NULL,
    value REAL NOT NULL,

    PRIMARY KEY (sample_id, param_id, sediment_no, type),
    FOREIGN KEY (sample_id, param_id, sediment_no)
        REFERENCES sediment (sample_id, param_id, sediment_no)
);"
    )
  )
}
