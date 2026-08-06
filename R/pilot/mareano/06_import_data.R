library(DBI)
library(RSQLite)

# 1. Connect and Enable Foreign Keys
con <- dbConnect(RSQLite::SQLite(), "./data/db/mareano_pilot.sqlite")
dbExecute(con, "PRAGMA foreign_keys = ON;")

# 2. Insert 'cruise' (The top-level parent)
# We use tryCatch or direct execution. append = TRUE adds to existing table.
dbWriteTable(con, "cruise", df_cruise, append = TRUE)

# 3. Insert 'core'
# This works only because all cruise_ids in df_core exist in the cruise table
dbWriteTable(con, "core", df_core, append = TRUE)

# 4. Insert 'sample'
# This works only because all (cruise_id + core_id) combinations exist in 'core'
dbWriteTable(con, "sample", df_sample, append = TRUE)

# 5. Insert 'parameter'
# This is a lookup table, independent of the others, but needed for 'sediment'
dbWriteTable(con, "parameter", df_parameter, append = TRUE)

# 6. Insert 'sediment'
# This is a data table. It relies on keys from 'sample' and 'element'
dbWriteTable(con, "sediment", df_sediment, append = TRUE)

# 7. Insert 'lld'
# This is another data table. It relies on keys from 'sample' and 'element'
dbWriteTable(con, "lld", df_lld, append = TRUE)

# 8. Check if data arrived (optional count)
print(paste("Cruises:", dbGetQuery(con, "SELECT count(*) FROM cruise")))
print(paste("Sediment Data Points:", dbGetQuery(con, "SELECT count(*) FROM sediment")))

# Disconnect
dbDisconnect(con)
