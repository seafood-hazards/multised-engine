# ── Pilot schema, 4Demon ─────────────────────────────────────────────────────
# `station` carries the six seastamp location columns, which the geo step fills.

pilot_schema_4demon <- function() {
  list(
    order = c("project", "station", "parameter", "method", "sample", "sediment"),
    ddl = list(
      project = "
CREATE TABLE project (
    project_id         INTEGER NOT NULL PRIMARY KEY,
    project_survey_id  INTEGER NOT NULL,
    project            TEXT    NOT NULL,
    campaign_code      TEXT,
    year               INTEGER,
    month              INTEGER,
    season             INTEGER
);",
      station = "
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
);",
      parameter = "
CREATE TABLE parameter (
    parameter      TEXT NOT NULL PRIMARY KEY,
    parameter_name TEXT,
    parameter_type TEXT
);",
      method = "
CREATE TABLE method (
    method_id     INTEGER NOT NULL PRIMARY KEY,
    method_seq_no     INTEGER NOT NULL,
    method_code       TEXT,
    matrix_code       TEXT,
    fraction_range_um TEXT
);",
      sample = "
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
);",
      sediment = "
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
);"
    )
  )
}
