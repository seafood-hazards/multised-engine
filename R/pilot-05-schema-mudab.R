# ── Pilot schema, MUDAB ──────────────────────────────────────────────────────
# `survey` carries the six seastamp location columns, which the geo step fills;
# MUDAB keys its positions on the monitoring station rather than the project
# station, so the geo columns hang off `survey`, not `station`.

pilot_schema_mudab <- function() {
  list(
    order = c("code_lookup", "station", "parameter", "measurement_time",
              "analysis_method", "reference_material", "survey", "lod",
              "sample", "sediment"),
    ddl = list(
      code_lookup = "
CREATE TABLE code_lookup (
    category_code TEXT NOT NULL,
    category_name TEXT,
    code          TEXT NOT NULL,
    code_name     TEXT,

    PRIMARY KEY (category_code, code)
);",
      station = "
CREATE TABLE station (
    station_no            INTEGER NOT NULL PRIMARY KEY,
    station_name          TEXT NOT NULL,
    station_id            INTEGER NOT NULL,
    responsible_institute TEXT,
    region                TEXT,
    institute             TEXT,
    latitude              REAL,
    longitude             REAL,
    organisation          TEXT,
    project_affiliation   TEXT,
    station_type          TEXT,
    water_body_category   TEXT
);",
      parameter = "
CREATE TABLE parameter (
    parameter       TEXT NOT NULL PRIMARY KEY,
    parameter_name  TEXT,
    parameter_group TEXT,
    cas_number      TEXT,
    lawa_code       REAL
);",
      measurement_time = "
CREATE TABLE measurement_time (
    measurement_time_id INTEGER NOT NULL PRIMARY KEY,
    year                REAL,
    measurement_date    TEXT,
    measurement_time    TEXT
);",
      analysis_method = "
CREATE TABLE analysis_method (
    analysis_method_id      INTEGER NOT NULL PRIMARY KEY,
    measurement_method_code TEXT,
    chemical_treatment      TEXT,
    physical_treatment      TEXT,
    measurement_basis       TEXT,
    accreditation           TEXT,
    analytical_laboratory   TEXT,
    control_chart_type      TEXT,
    discipline              TEXT,
    proficiency_testing     TEXT
);",
      reference_material = "
CREATE TABLE reference_material (
    reference_material_id   INTEGER NOT NULL PRIMARY KEY,
    parameter               TEXT  NOT NULL,
    reference_material_code TEXT,
    reference_material_basis TEXT,
    reference_material_type TEXT,
    reference_material_sd   REAL,
    reference_material_mean REAL,

    FOREIGN KEY (parameter) REFERENCES parameter (parameter)
);",
      survey = "
CREATE TABLE survey (
    survey_id               INTEGER NOT NULL PRIMARY KEY,
    monitoring_station_name TEXT,
    measurement_depth       REAL,
    station_latitude        REAL,
    station_longitude       REAL,
    measurement_project     TEXT,
    survey_start            REAL,
    survey_end              REAL,
    vessel_code             TEXT,
    platform_type           TEXT,
    vessel_name             TEXT,
    dist_to_coast           REAL,
    est_country             TEXT,
    country_code            TEXT,
    municipality            TEXT,
    sea_name                TEXT
);",
      lod = "
CREATE TABLE lod (
    lod_id                           INTEGER NOT NULL PRIMARY KEY,
    parameter                        TEXT  NOT NULL,
    internal_qa_detection_limit      REAL,
    internal_qa_quantification_limit REAL,
    expanded_uncertainty_pct         REAL,
    uncertainty_method               TEXT,

    FOREIGN KEY (parameter) REFERENCES parameter (parameter)
);",
      sample = "
CREATE TABLE sample (
    sample_no            INTEGER NOT NULL PRIMARY KEY,
    sample_id            TEXT,
    layer_upper_boundary REAL,
    layer_lower_boundary REAL,
    sampling_method      TEXT,
    flag                 TEXT,
    matrix               TEXT,
    sediment_composition TEXT,
    sediment_content     TEXT,
    sampled_area         REAL
);",
      sediment = "
CREATE TABLE sediment (
    station_no              INTEGER NOT NULL,
    measurement_time_id     INTEGER NOT NULL,
    analysis_method_id      INTEGER NOT NULL,
    reference_material_id   INTEGER NOT NULL,
    survey_id               INTEGER NOT NULL,
    sample_no               INTEGER NOT NULL,
    lod_id                  INTEGER NOT NULL,
    sediment_no             INTEGER NOT NULL,
    parameter               TEXT    NOT NULL,
    measurement_start       REAL,
    measurement_end         REAL,
    measured_value          REAL,
    unit                    TEXT,
    data_qualifier          TEXT,
    internal_qa_count       REAL,
    recovery_rate           REAL,

    PRIMARY KEY (station_no, measurement_time_id, analysis_method_id,
                 reference_material_id, survey_id, sample_no,
                 lod_id, sediment_no, parameter),

    FOREIGN KEY (station_no)            REFERENCES station            (station_no),
    FOREIGN KEY (measurement_time_id)   REFERENCES measurement_time   (measurement_time_id),
    FOREIGN KEY (analysis_method_id)    REFERENCES analysis_method    (analysis_method_id),
    FOREIGN KEY (reference_material_id) REFERENCES reference_material (reference_material_id),
    FOREIGN KEY (survey_id)             REFERENCES survey             (survey_id),
    FOREIGN KEY (sample_no)             REFERENCES sample             (sample_no),
    FOREIGN KEY (lod_id)                REFERENCES lod                (lod_id),
    FOREIGN KEY (parameter)             REFERENCES parameter          (parameter)
);"
    )
  )
}
