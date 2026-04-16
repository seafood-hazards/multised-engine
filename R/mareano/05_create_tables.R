library(DBI)
library(RSQLite)

con <- dbConnect(RSQLite::SQLite(), "./data/db/pilot_mareano.sqlite")
dbExecute(con, "PRAGMA foreign_keys = ON;")

# --- 0. Drop all tables ---
drop_tables_sql <- "DROP TABLE IF EXISTS sediment;"
dbExecute(con, drop_tables_sql)

drop_tables_sql <- "DROP TABLE IF EXISTS lld;"
dbExecute(con, drop_tables_sql)

drop_tables_sql <- "DROP TABLE IF EXISTS parameter;"
dbExecute(con, drop_tables_sql)

drop_tables_sql <- "DROP TABLE IF EXISTS sample;"
dbExecute(con, drop_tables_sql)

drop_tables_sql <- "DROP TABLE IF EXISTS core;"
dbExecute(con, drop_tables_sql)

drop_tables_sql <- "DROP TABLE IF EXISTS cruise;"
dbExecute(con, drop_tables_sql)

# --- 1. CRUISE (Parent Table) ---
create_cruise_sql <- "
CREATE TABLE cruise (
  cruise_id TEXT NOT NULL,
  source TEXT NOT NULL,
  cruise_type TEXT NOT NULL,
  year INTEGER NOT NULL,
  cruise_no INTEGER,
  start TEXT,
  end TEXT,
  start_year INTEGER,
  start_month INTEGER,
  start_day INTEGER,
  end_year INTEGER,
  end_month INTEGER,
  end_day INTEGER,
  area INTEGER,
  cruise_no2 INTEGER,

  PRIMARY KEY (cruise_id)
);
"
dbExecute(con, create_cruise_sql)

# --- 2. CORE (Child of Cruise) ---
create_core_sql <- "
CREATE TABLE core (
  cruise_id TEXT NOT NULL,
  core_id TEXT NOT NULL,
  station_no TEXT,
  sampling_tool TEXT,
  tool_id TEXT,
  core_name TEXT,
  dde REAL NOT NULL,
  ddn REAL NOT NULL,
  mbsl REAL,
  dist_to_coast INTEGER,
  country TEXT,
  country_code TEXT,
  municipality TEXT,
  sea_name TEXT,

  FOREIGN KEY (cruise_id) REFERENCES cruise(cruise_id),

  PRIMARY KEY (cruise_id, core_id)
);
"
dbExecute(con, create_core_sql)

# --- 3. SAMPLE (Child of Core) ---
create_sample_sql <- "
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
);
"
dbExecute(con, create_sample_sql)

# --- 4. PARAMETER (Lookup Table) ---
create_parameter_sql <- "
CREATE TABLE parameter (
  parameter TEXT NOT NULL,
  unit TEXT,
  symbol TEXT,
  element TEXT,
  method1 TEXT,
  method2 TEXT,
  institute TEXT,

  PRIMARY KEY (parameter)
);
"
dbExecute(con, create_parameter_sql)

# --- 5. SEDIMENT (Data Table) ---
create_sediment_sql <- "
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
);
"
dbExecute(con, create_sediment_sql)

# --- 6. LLD (Data Table) ---
create_lld_sql <- "
CREATE TABLE lld (
  batch_id TEXT NOT NULL,
  parameter TEXT NOT NULL,
  value TEXT NOT NULL,

  FOREIGN KEY (parameter) REFERENCES parameter(parameter),

  PRIMARY KEY (batch_id, parameter)
);
"
dbExecute(con, create_lld_sql)

# Verify
print(dbListTables(con))

dbDisconnect(con)

