library(DBI)
library(RSQLite)

con <- dbConnect(RSQLite::SQLite(), "./data/db/pilot_vannmiljo.sqlite")
dbExecute(con, "PRAGMA foreign_keys = ON;")

# --- 0. Drop all tables ---
drop_table_sql <- "DROP TABLE IF EXISTS activity;"
dbExecute(con, drop_table_sql)

drop_table_sql <- "DROP TABLE IF EXISTS client;"
dbExecute(con, drop_table_sql)

drop_table_sql <- "DROP TABLE IF EXISTS contractor;"
dbExecute(con, drop_table_sql)

drop_table_sql <- "DROP TABLE IF EXISTS site;"
dbExecute(con, drop_table_sql)

drop_table_sql <- "DROP TABLE IF EXISTS sample_method;"
dbExecute(con, drop_table_sql)

drop_table_sql <- "DROP TABLE IF EXISTS analysis_method;"
dbExecute(con, drop_table_sql)

drop_table_sql <- "DROP TABLE IF EXISTS sample;"
dbExecute(con, drop_table_sql)

drop_table_sql <- "DROP TABLE IF EXISTS parameter;"
dbExecute(con, drop_table_sql)

drop_table_sql <- "DROP TABLE IF EXISTS sediment;"
dbExecute(con, drop_table_sql)

drop_table_sql <- "DROP TABLE IF EXISTS lld;"
dbExecute(con, drop_table_sql)

#-- 1. Create independent table: activity
create_table_sql <- "
CREATE TABLE activity (
    activity_id TEXT NOT NULL PRIMARY KEY,
    activity_name TEXT NOT NULL
);
"
dbExecute(con, create_table_sql)

#-- 2. Create independent table: client
create_table_sql <- "
CREATE TABLE client (
    client_id INTEGER NOT NULL PRIMARY KEY,
    client TEXT NOT NULL,
    archive BOOLEAN NOT NULL
);
"
dbExecute(con, create_table_sql)

#-- 3. Create independent table: contractor
create_table_sql <- "
CREATE TABLE contractor (
    contractor_id INTEGER NOT NULL PRIMARY KEY,
    contractor TEXT NOT NULL
);
"
dbExecute(con, create_table_sql)

#-- 4. Create independent table: site
create_table_sql <- "
CREATE TABLE site (
    site_code TEXT NOT NULL PRIMARY KEY,
    site_name TEXT,
    label TEXT,
    lon REAL NOT NULL,
    lat REAL NOT NULL,
    dist_to_coast REAL,
    country TEXT,
    country_code TEXT,
    municipality TEXT,
    sea_name TEXT
);
"
dbExecute(con, create_table_sql)

#-- 5. Create independent table: sample_method
create_table_sql <- "
CREATE TABLE sample_method (
    method_id INTEGER NOT NULL PRIMARY KEY,
    method TEXT NOT NULL
);
"
dbExecute(con, create_table_sql)

#-- 6. Create independent table: analysis_method
create_table_sql <- "
CREATE TABLE analysis_method (
    analysis_id INTEGER NOT NULL PRIMARY KEY,
    analysis TEXT NOT NULL,
    unit TEXT NOT NULL
);
"
dbExecute(con, create_table_sql)

#-- 7. Create independent table: parameter
create_table_sql <- "
CREATE TABLE parameter (
    param_id TEXT NOT NULL PRIMARY KEY,
    param_name TEXT NOT NULL,
    cas_no TEXT
);
"
dbExecute(con, create_table_sql)

#-- 8. Create dependent table: sample
create_table_sql <- "
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
);
"
dbExecute(con, create_table_sql)

#-- 9. Create dependent table: sediment
create_table_sql <- "
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
);
"
dbExecute(con, create_table_sql)

#-- 10. Create dependent table: lld (Limits of Detection/Quantification)
create_table_sql <- "
CREATE TABLE lld (
    sample_id TEXT NOT NULL,
    param_id TEXT NOT NULL,
    sediment_no INTEGER NOT NULL,
    type TEXT NOT NULL,
    value REAL NOT NULL,

    PRIMARY KEY (sample_id, param_id, sediment_no, type),
    FOREIGN KEY (sample_id, param_id, sediment_no)
        REFERENCES sediment (sample_id, param_id, sediment_no)
);
"
dbExecute(con, create_table_sql)

# Verify
print(dbListTables(con))

dbDisconnect(con)

