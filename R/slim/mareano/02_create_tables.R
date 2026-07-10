# ── 11. Create target database and schema ────────────────────────────────────
con <- dbConnect(RSQLite::SQLite(), "./data/db/mareano_slim.sqlite")
dbExecute(con, "PRAGMA foreign_keys = ON;")

for (tbl in c("measurement", "subsample", "method", "event",
              "site", "dataset", "element")) {
  dbExecute(con, paste0("DROP TABLE IF EXISTS ", tbl, ";"))
}

dbExecute(con, "
CREATE TABLE element (
  symbol  TEXT NOT NULL,
  element TEXT NOT NULL,
  PRIMARY KEY (symbol)
);")

dbExecute(con, "
CREATE TABLE dataset (
  dataset_id   INTEGER NOT NULL,
  source_db    TEXT    NOT NULL,
  country      TEXT    NOT NULL,
  institute    TEXT    NOT NULL,
  project_name TEXT    NOT NULL,
  PRIMARY KEY (dataset_id)
);")

dbExecute(con, "
CREATE TABLE site (
  site_id       INTEGER NOT NULL,
  latitude      REAL    NOT NULL,
  longitude     REAL    NOT NULL,
  depth         REAL,
  country       TEXT,
  country_code  TEXT,
  dist_to_coast INTEGER,
  municipality  TEXT,
  sea_name      TEXT,
  PRIMARY KEY (site_id)
);")

dbExecute(con, "
CREATE TABLE event (
  event_id      INTEGER NOT NULL,
  dataset_id    INTEGER NOT NULL,
  site_id       INTEGER NOT NULL,
  sampling_tool TEXT,
  year          INTEGER,
  date          TEXT,
  FOREIGN KEY (dataset_id) REFERENCES dataset(dataset_id),
  FOREIGN KEY (site_id)    REFERENCES site(site_id),
  PRIMARY KEY (event_id)
);")

dbExecute(con, "
CREATE TABLE method (
  method_id INTEGER NOT NULL,
  symbol    TEXT    NOT NULL,
  method    TEXT,
  lab       TEXT,
  lld       REAL,
  comment   TEXT,
  FOREIGN KEY (symbol) REFERENCES element(symbol),
  PRIMARY KEY (method_id)
);")

dbExecute(con, "
CREATE TABLE subsample (
  subsample_id INTEGER NOT NULL,
  event_id     INTEGER NOT NULL,
  depth_from   INTEGER NOT NULL,
  depth_to     INTEGER NOT NULL,
  FOREIGN KEY (event_id) REFERENCES event(event_id),
  PRIMARY KEY (subsample_id)
);")

dbExecute(con, "
CREATE TABLE measurement (
  measurement_id INTEGER NOT NULL,
  subsample_id   INTEGER NOT NULL,
  symbol         TEXT    NOT NULL,
  value          REAL    NOT NULL,
  unit           TEXT,
  below_lld      INTEGER NOT NULL,
  method_id      INTEGER NOT NULL,
  FOREIGN KEY (subsample_id) REFERENCES subsample(subsample_id),
  FOREIGN KEY (symbol)       REFERENCES element(symbol),
  FOREIGN KEY (method_id)    REFERENCES method(method_id),
  PRIMARY KEY (measurement_id)
);")

# ── 12. Insert data ──────────────────────────────────────────────────────────
dbWriteTable(con, "element",     df_element,     append = TRUE)
dbWriteTable(con, "dataset",     df_dataset,     append = TRUE)
dbWriteTable(con, "site",        df_site,        append = TRUE)
dbWriteTable(con, "event",       df_event,       append = TRUE)
dbWriteTable(con, "method",      df_method,      append = TRUE)
dbWriteTable(con, "subsample",   df_subsample,   append = TRUE)
dbWriteTable(con, "measurement", df_measurement, append = TRUE)

# ── 13. Verify ────────────────────────────────────────────────────────
cat("Tables:", paste(dbListTables(con), collapse = ", "), "\n")
for (tbl in dbListTables(con)) {
  n <- dbGetQuery(con, paste0("SELECT COUNT(*) FROM ", tbl))[[1]]
  cat(sprintf("  %-15s %d rows\n", tbl, n))
}

dbDisconnect(con)
