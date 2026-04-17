library(DBI)
library(RSQLite)

con <- dbConnect(RSQLite::SQLite(), "./data/db/pilot_ices_dome.sqlite")
dbExecute(con, "PRAGMA foreign_keys = ON;")

# --- 0. Drop tables in reverse dependency order ---
walk(
  c("sediment", "sample", "lld", "analysis_method", "reference",
    "parameter", "site", "project", "code_lookup"),
  \(tbl) dbExecute(con, sprintf("DROP TABLE IF EXISTS %s;", tbl))
)

# --- 1. Independent table: code_lookup ---
dbExecute(con, "
CREATE TABLE code_lookup (
    data_col    TEXT NOT NULL,
    code_type   TEXT NOT NULL,
    raw_code    TEXT NOT NULL,
    code        TEXT NOT NULL,
    description TEXT,

    PRIMARY KEY (data_col, code_type, raw_code, code)
);
")

# --- 2. Independent table: project ---
dbExecute(con, "
CREATE TABLE project (
    project_id  INTEGER NOT NULL PRIMARY KEY,
    project     TEXT    NOT NULL,
    purpose     TEXT,
    country     TEXT,
    institute   TEXT
);
")

# --- 3. Independent table: site ---
dbExecute(con, "
CREATE TABLE site (
    site_id       INTEGER NOT NULL PRIMARY KEY,
    station       TEXT,
    latitude      REAL    NOT NULL,
    longitude     REAL    NOT NULL,
    dist_to_coast REAL,
    est_country   TEXT,
    country_code  TEXT,
    municipality  TEXT,
    sea_name      TEXT
);
")

# --- 4. Independent table: parameter ---
dbExecute(con, "
CREATE TABLE parameter (
    param             TEXT NOT NULL PRIMARY KEY,
    param_description TEXT,
    group_code        TEXT NOT NULL,
    group_description TEXT
);
")

# --- 5. Independent table: lld ---
dbExecute(con, "
CREATE TABLE lld (
    lld_id    INTEGER NOT NULL PRIMARY KEY,
    param     TEXT    NOT NULL,
    lod       REAL,
    loq       REAL,

    FOREIGN KEY (param) REFERENCES parameter (param)
);
")

# --- 6. Independent table: analysis_method ---
dbExecute(con, "
CREATE TABLE analysis_method (
    analysis_id INTEGER NOT NULL PRIMARY KEY,
    param       TEXT,
    labo        TEXT,
    metst       TEXT,
    metpt       TEXT,
    metps       TEXT,
    metcx       TEXT,
    metoa       TEXT,

    FOREIGN KEY (param) REFERENCES parameter (param)
);
")

# --- 7. Independent table: reference ---
dbExecute(con, "
CREATE TABLE reference (
    ref_id          INTEGER NOT NULL PRIMARY KEY,
    ref             TEXT,
    ref_description TEXT
);
")

# --- 8. Dependent table: sample ---
dbExecute(con, "
CREATE TABLE sample (
    sample_id               INTEGER NOT NULL PRIMARY KEY,
    project_id              INTEGER NOT NULL,
    site_id                 INTEGER NOT NULL,
    year                    INTEGER,
    date                    TEXT,
    sample_type             TEXT,
    sample_type_description TEXT,

    FOREIGN KEY (project_id) REFERENCES project (project_id),
    FOREIGN KEY (site_id)    REFERENCES site (site_id)
);
")

# --- 9. Dependent table: sediment ---
dbExecute(con, "
CREATE TABLE sediment (
    project_id  INTEGER NOT NULL,
    site_id     INTEGER NOT NULL,
    sample_id   INTEGER NOT NULL,
    param       TEXT    NOT NULL,
    sediment_no INTEGER NOT NULL,
    depth_from  REAL,
    depth_to    REAL,
    value       REAL,
    unit        TEXT,
    basis       TEXT,
    qflag       TEXT,
    vflag       TEXT,
    uncrt       REAL,
    metcu       TEXT,
    sub_no      TEXT,
    dcflag      TEXT,
    lld_id      INTEGER,
    analysis_id INTEGER,
    ref_id      INTEGER,

    PRIMARY KEY (project_id, site_id, sample_id, param, sediment_no),

    FOREIGN KEY (project_id)  REFERENCES project         (project_id),
    FOREIGN KEY (site_id)     REFERENCES site            (site_id),
    FOREIGN KEY (sample_id)   REFERENCES sample          (sample_id),
    FOREIGN KEY (param)       REFERENCES parameter       (param),
    FOREIGN KEY (lld_id)      REFERENCES lld             (lld_id),
    FOREIGN KEY (analysis_id) REFERENCES analysis_method (analysis_id),
    FOREIGN KEY (ref_id)      REFERENCES reference       (ref_id)
);
")

# --- 10. Write data ---
# Independent tables first, then dependent
dbWriteTable(con, "code_lookup",      code_lookup,                               append = TRUE)
dbWriteTable(con, "project",          df_project,                                append = TRUE)
dbWriteTable(con, "site",             df_site,                                   append = TRUE)
dbWriteTable(con, "parameter",        df_parameter |> select(-row_count),        append = TRUE)
dbWriteTable(con, "lld",              df_lld       |> select(-row_count),        append = TRUE)
dbWriteTable(con, "analysis_method",  df_analysis_method |> select(-row_count),  append = TRUE)
dbWriteTable(con, "reference",        df_referance |> select(-row_count),        append = TRUE)
dbWriteTable(con, "sample",           df_sample    |> select(-row_count),        append = TRUE)
dbWriteTable(con, "sediment",         df_sediment,                               append = TRUE)

# --- Verify ---
print(dbListTables(con))

dbDisconnect(con)
