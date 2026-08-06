# ── Pilot schema, ICES-DOME ──────────────────────────────────────────────────
# `site` carries the six seastamp location columns, which the geo step fills.
# Several extract frames carry a `row_count` column used only while building; it
# is dropped on the way in, as the original write step did.

pilot_schema_ices_dome <- function() {
  list(
    order = c("code_lookup", "project", "site", "parameter", "lld",
              "analysis_method", "reference", "sample", "sediment"),
    drop_cols = list(
      parameter       = "row_count",
      lld             = "row_count",
      analysis_method = "row_count",
      reference       = "row_count",
      sample          = "row_count"),
    ddl = list(
      code_lookup = "
CREATE TABLE code_lookup (
    data_col    TEXT NOT NULL,
    code_type   TEXT NOT NULL,
    raw_code    TEXT NOT NULL,
    code        TEXT NOT NULL,
    description TEXT,

    PRIMARY KEY (data_col, code_type, raw_code, code)
);",
      project = "
CREATE TABLE project (
    project_id  INTEGER NOT NULL PRIMARY KEY,
    project     TEXT    NOT NULL,
    purpose     TEXT,
    country     TEXT,
    institute   TEXT
);",
      site = "
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
);",
      parameter = "
CREATE TABLE parameter (
    param             TEXT NOT NULL PRIMARY KEY,
    param_description TEXT,
    group_code        TEXT NOT NULL,
    group_description TEXT
);",
      lld = "
CREATE TABLE lld (
    lld_id    INTEGER NOT NULL PRIMARY KEY,
    param     TEXT    NOT NULL,
    lod       REAL,
    loq       REAL,

    FOREIGN KEY (param) REFERENCES parameter (param)
);",
      analysis_method = "
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
);",
      reference = "
CREATE TABLE reference (
    ref_id          INTEGER NOT NULL PRIMARY KEY,
    ref             TEXT,
    ref_description TEXT
);",
      sample = "
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
);",
      sediment = "
CREATE TABLE sediment (
    project_id  INTEGER NOT NULL,
    site_id     INTEGER NOT NULL,
    sample_id   INTEGER NOT NULL,
    param       TEXT    NOT NULL,
    sediment_no INTEGER NOT NULL,
    depth_from  REAL,
    depth_to    REAL,
    matrix      TEXT,
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
);"
    )
  )
}
