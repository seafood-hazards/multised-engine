# ── Slim schema, ICES-DOME ───────────────────────────────────────────────────
# The widest `measurement`: basis / matrix / qflag / vflag / uncrt / metcu /
# dcflag. `method` carries the ICES lab and method code plus their descriptions.

slim_schema_ices_dome <- function() {
  list(
    element = "
CREATE TABLE element (
  symbol  TEXT NOT NULL,
  element TEXT NOT NULL,
  PRIMARY KEY (symbol)
);",
    dataset = "
CREATE TABLE dataset (
  dataset_id   INTEGER NOT NULL,
  source       TEXT    NOT NULL,
  dataset_code TEXT    NOT NULL,
  dataset_name TEXT    NOT NULL,
  country      TEXT    NOT NULL,
  institute    TEXT    NOT NULL,
  PRIMARY KEY (dataset_id)
);",
    site = "
CREATE TABLE site (
  site_id       INTEGER NOT NULL,
  latitude      REAL    NOT NULL,
  longitude     REAL    NOT NULL,
  country       TEXT,
  country_code  TEXT,
  dist_to_coast INTEGER,
  municipality  TEXT,
  sea_name      TEXT,
  PRIMARY KEY (site_id)
);",
    event = "
CREATE TABLE event (
  event_id         INTEGER NOT NULL,
  dataset_id       INTEGER NOT NULL,
  site_id          INTEGER NOT NULL,
  sampling_tool    TEXT,
  tool_description TEXT,
  year             INTEGER,
  date             TEXT,
  FOREIGN KEY (dataset_id) REFERENCES dataset(dataset_id),
  FOREIGN KEY (site_id)    REFERENCES site(site_id),
  PRIMARY KEY (event_id)
);",
    method = "
CREATE TABLE method (
  method_id          INTEGER NOT NULL,
  symbol             TEXT    NOT NULL,
  lab                TEXT,
  lab_name           TEXT,
  lod                REAL,
  loq                REAL,
  method             TEXT,
  method_description TEXT,
  extraction         TEXT,
  extraction_class   INTEGER,
  FOREIGN KEY (symbol) REFERENCES element(symbol),
  PRIMARY KEY (method_id)
);",
    subsample = "
CREATE TABLE subsample (
  subsample_id INTEGER NOT NULL,
  event_id     INTEGER NOT NULL,
  depth_from   INTEGER NOT NULL,
  depth_to     INTEGER NOT NULL,
  FOREIGN KEY (event_id) REFERENCES event(event_id),
  PRIMARY KEY (subsample_id)
);",
    measurement = "
CREATE TABLE measurement (
  measurement_id INTEGER NOT NULL,
  subsample_id   INTEGER NOT NULL,
  symbol         TEXT    NOT NULL,
  value          REAL    NOT NULL,
  unit           TEXT,
  basis          TEXT,
  matrix         TEXT,
  qflag          TEXT,
  vflag          TEXT,
  uncrt          REAL,
  metcu          TEXT,
  dcflag         TEXT,
  method_id      INTEGER NOT NULL,
  FOREIGN KEY (subsample_id) REFERENCES subsample(subsample_id),
  FOREIGN KEY (symbol)       REFERENCES element(symbol),
  FOREIGN KEY (method_id)    REFERENCES method(method_id),
  PRIMARY KEY (measurement_id)
);"
  )
}
