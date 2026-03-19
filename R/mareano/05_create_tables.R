library(DBI)
library(RSQLite)

con <- dbConnect(RSQLite::SQLite(), "./data/db/mariano.sqlite")
dbExecute(con, "PRAGMA foreign_keys = ON;")

# --- 0. Drop all tables ---
drop_tables_sql <- "DROP TABLE IF EXISTS sediment;"
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
  source TEXT,
  type TEXT,
  year INTEGER,
  month INTEGER,
  day INTEGER,
  cruise_no INTEGER,
  start INTEGER,
  end INTEGER,
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
  dde REAL,
  ddn REAL,
  mbsl REAL,
  dist_to_coast INTEGER,

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
  depth_from INTEGER,
  depth_to INTEGER,
  sample_batch_id TEXT,
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
  value REAL,
  is_lld INTEGER,

  FOREIGN KEY (cruise_id, core_id, sample_id) REFERENCES sample(cruise_id, core_id, sample_id),
  FOREIGN KEY (parameter) REFERENCES parameter(parameter),

  PRIMARY KEY (cruise_id, core_id, sample_id, parameter)
);
"
dbExecute(con, create_sediment_sql)

# Verify
print(dbListTables(con))

dbDisconnect(con)
