# ── Pilot schema, Mareano ────────────────────────────────────────────────────
# `core` carries the six seastamp location columns, which the geo step fills.
# Mareano names the country column `country` rather than `est_country`, and
# types `dist_to_coast` as INTEGER; both differ from the other sources and are
# kept as they are so the stored database is reproduced exactly.

pilot_schema_mareano <- function() {
  list(
    order = c("cruise", "core", "sample", "parameter", "sediment", "lld"),
    ddl = list(
      cruise = "
CREATE TABLE cruise (
  cruise_id TEXT NOT NULL,
  source TEXT NOT NULL,
  cruise_type TEXT NOT NULL,
  year INTEGER NOT NULL,
  cruise_no TEXT,
  start TEXT,
  end TEXT,
  start_year INTEGER,
  start_month INTEGER,
  start_day INTEGER,
  end_year INTEGER,
  end_month INTEGER,
  end_day INTEGER,
  area TEXT,
  cruise_no2 TEXT,

  PRIMARY KEY (cruise_id)
);",
      core = "
CREATE TABLE core (
  cruise_id TEXT NOT NULL,
  core_id TEXT NOT NULL,
  station_no TEXT,
  sampling_tool TEXT,
  tool_id TEXT,
  core_name TEXT,
  ddn REAL NOT NULL,
  dde REAL NOT NULL,
  mbsl REAL,
  dist_to_coast INTEGER,
  country TEXT,
  country_code TEXT,
  municipality TEXT,
  sea_name TEXT,

  FOREIGN KEY (cruise_id) REFERENCES cruise(cruise_id),

  PRIMARY KEY (cruise_id, core_id)
);",
      sample = "
CREATE TABLE sample (
  cruise_id TEXT NOT NULL,
  core_id TEXT NOT NULL,
  sample_id TEXT NOT NULL,
  depth_from INTEGER NOT NULL,
  depth_to INTEGER NOT NULL,
  batch_id TEXT,
  sample_id2 TEXT,

  FOREIGN KEY (cruise_id, core_id) REFERENCES core(cruise_id, core_id),

  PRIMARY KEY (cruise_id, core_id, sample_id)
);",
      parameter = "
CREATE TABLE parameter (
  parameter TEXT NOT NULL,
  unit TEXT,
  symbol TEXT,
  element TEXT,
  method1 TEXT,
  method2 TEXT,
  institute TEXT,

  PRIMARY KEY (parameter)
);",
      sediment = "
CREATE TABLE sediment (
  cruise_id TEXT NOT NULL,
  core_id TEXT NOT NULL,
  sample_id TEXT NOT NULL,
  parameter TEXT NOT NULL,
  value REAL NOT NULL,
  is_lld INTEGER NOT NULL,

  FOREIGN KEY (cruise_id, core_id, sample_id) REFERENCES sample(cruise_id, core_id, sample_id),
  FOREIGN KEY (parameter) REFERENCES parameter(parameter),

  PRIMARY KEY (cruise_id, core_id, sample_id, parameter)
);",
      lld = "
CREATE TABLE lld (
  batch_id TEXT NOT NULL,
  parameter TEXT NOT NULL,
  value TEXT NOT NULL,
  comment TEXT,

  FOREIGN KEY (parameter) REFERENCES parameter(parameter),

  PRIMARY KEY (batch_id, parameter)
);"
    )
  )
}
