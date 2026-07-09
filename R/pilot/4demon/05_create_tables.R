library(DBI)
library(RSQLite)
library(tidyverse)

# --- Connect ---
con <- dbConnect(RSQLite::SQLite(), "./data/db/pilot_4demon.sqlite")
dbExecute(con, "PRAGMA foreign_keys = ON;")

# --- 0. Drop tables in reverse dependency order ---
walk(
  c("sediment", "sample", "method", "parameter", "station", "project"),
  \(tbl) dbExecute(con, sprintf("DROP TABLE IF EXISTS %s;", tbl))
)

# --- 1. Independent table: project ---
dbExecute(con, "
CREATE TABLE project (
    project_id         INTEGER NOT NULL PRIMARY KEY,
    project_survey_id  INTEGER NOT NULL,
    project            TEXT    NOT NULL,
    campaign_code      TEXT,
    year               INTEGER,
    month              INTEGER,
    season             INTEGER
);
")

# --- 2. Independent table: station ---
dbExecute(con, "
CREATE TABLE station (
    station_id     INTEGER NOT NULL PRIMARY KEY,
    station_code   TEXT    NOT NULL,
    station_group  TEXT,
    latitude       REAL,
    longitude      REAL,
    dist_to_coast  REAL,
    est_country    TEXT,
    country_code   TEXT,
    municipality   TEXT,
    sea_name       TEXT
);
")

# --- 3. Independent table: parameter ---
dbExecute(con, "
CREATE TABLE parameter (
    parameter      TEXT NOT NULL PRIMARY KEY,
    parameter_name TEXT,
    parameter_type TEXT
);
")

# --- 4. Independent table: method ---
dbExecute(con, "
CREATE TABLE method (
    method_id     INTEGER NOT NULL PRIMARY KEY,
    method_seq_no     INTEGER NOT NULL,
    method_code       TEXT,
    matrix_code       TEXT,
    fraction_range_um TEXT
);
")

# --- 5. Dependent table: sample ---
dbExecute(con, "
CREATE TABLE sample (
    sample_id          INTEGER NOT NULL PRIMARY KEY,
    sample_seq_no      INTEGER NOT NULL,
    station_id         INTEGER NOT NULL,
    project_id  INTEGER NOT NULL,
    sample_ref_code    TEXT,
    sample_timestamp   TEXT,
    start_date         TEXT,
    gear_code          TEXT,
    depth_range        TEXT,
    replicate_number   INTEGER,

    FOREIGN KEY (station_id)        REFERENCES station (station_id),
    FOREIGN KEY (project_id) REFERENCES project (project_id)
);
")

# --- 6. Dependent table: sediment (fact table) ---
dbExecute(con, "
CREATE TABLE sediment (
    survey_seq_no       INTEGER NOT NULL PRIMARY KEY,
    sample_id           INTEGER NOT NULL,
    method_id           INTEGER NOT NULL,
    parameter           TEXT    NOT NULL,
    value               REAL,
    corrected_value     REAL,
    unit                TEXT,
    value_flag          INTEGER,
    det_limit_flag      INTEGER,
    range_check_flag    INTEGER,
    outlier_extreme_flag INTEGER,
    outlier_stdev_flag  INTEGER,

    FOREIGN KEY (sample_id) REFERENCES sample    (sample_id),
    FOREIGN KEY (method_id) REFERENCES method    (method_id),
    FOREIGN KEY (parameter)     REFERENCES parameter (parameter)
);
")

# --- Write in dependency order ---
dbWriteTable(con, "project",   df_project,   append = TRUE)
dbWriteTable(con, "station",   df_station,   append = TRUE)
dbWriteTable(con, "parameter", df_parameter, append = TRUE)
dbWriteTable(con, "method",    df_method,    append = TRUE)
dbWriteTable(con, "sample",    df_sample,    append = TRUE)
dbWriteTable(con, "sediment",  df_sediment,  append = TRUE)

# --- Verify ---
walk(dbListTables(con), \(tbl) {
  n <- dbGetQuery(con, sprintf("SELECT COUNT(*) AS n FROM %s", tbl))$n
  message(sprintf("%-12s %d rows", tbl, n))
})

dbDisconnect(con)
