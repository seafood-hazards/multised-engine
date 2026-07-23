library(DBI)
library(RSQLite)
library(tidyverse)

# ── 0. Open slim db ──────────────────────────────────────────────────────────
con <- dbConnect(RSQLite::SQLite(), "./data/db/ices_dome_slim.sqlite")
dbExecute(con, "PRAGMA foreign_keys = ON;")

# ── 1. Add below_loq column (idempotent) ─────────────────────────────────────
# Common cross-source flag: 1 = value is below the detection/quantification
# limit (an uncertain "less-than" reading), 0 = a quantified value. These rows
# are candidates for removal in the clean stage.
if (!"below_loq" %in% dbListFields(con, "measurement")) {
  dbExecute(con, "ALTER TABLE measurement ADD COLUMN below_loq INTEGER;")
}

# ── 2. Map the source detection flag onto below_loq ──────────────────────────
# ICES-DOME uses the ICES `qflag` quality flag. All the non-NULL codes present
# are below-limit indicators: '<' less-than, 'D' below detection limit, 'Q'
# below quantification limit, '<~Q' less-than / approx / below quantification.
# NULL = an ordinary quantified value. Any unexpected non-NULL code is reported
# below so the mapping stays auditable after a rebuild.
below_codes <- c("<", "D", "Q", "<~Q")

qf <- dbGetQuery(con, "SELECT DISTINCT qflag FROM measurement WHERE qflag IS NOT NULL")$qflag
unmapped <- setdiff(qf, below_codes)
if (length(unmapped) > 0) {
  warning("Unmapped non-NULL qflag code(s): ", paste(unmapped, collapse = ", "),
          " -- treated as NOT below_loq (0). Review whether they are below-limit.")
}

dbExecute(con, sprintf("
  UPDATE measurement
  SET below_loq = CASE WHEN qflag IN (%s) THEN 1 ELSE 0 END;",
  paste(sprintf("'%s'", below_codes), collapse = ", ")))

# ── 3. Verify ────────────────────────────────────────────────────────────────
cat("qflag -> below_loq crosstab:\n")
print(dbGetQuery(con, "SELECT COALESCE(qflag,'(NULL)') qflag,
                              below_loq, COUNT(*) n
                       FROM measurement GROUP BY qflag, below_loq ORDER BY n DESC"))
cat("below_loq totals:\n")
print(dbGetQuery(con, "SELECT below_loq, COUNT(*) n
                       FROM measurement GROUP BY below_loq ORDER BY n DESC"))

dbDisconnect(con)
