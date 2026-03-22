library(DBI)
library(RSQLite)

# 1. Connect and Enable Foreign Keys
con <- dbConnect(RSQLite::SQLite(), "./data/db/pilot_vannmiljo.sqlite")
dbExecute(con, "PRAGMA foreign_keys = ON;")

# 2. Insert 'activity' (The top-level parent)
dbWriteTable(con, "activity", df_activity, append = TRUE)

# 3. Insert 'client'
dbWriteTable(con, "client", df_client, append = TRUE)

# 4. Insert 'contractor'
dbWriteTable(con, "contractor", df_contractor, append = TRUE)

# 5. Insert 'site'
dbWriteTable(con, "site", df_site, append = TRUE)

# 6. Insert 'sample_method'
dbWriteTable(con, "sample_method", df_sample_method, append = TRUE)

# 7. Insert 'analysis_method'
dbWriteTable(con, "analysis_method", df_analysis_method, append = TRUE)

# 8. Insert 'sample'
dbWriteTable(con, "sample", df_sample, append = TRUE)

# 9. Insert 'parameter'
dbWriteTable(con, "parameter", df_parameter, append = TRUE)

# 10. Insert 'sediment'
dbWriteTable(con, "sediment", df_sediment, append = TRUE)

# 11. Insert 'lld'
dbWriteTable(con, "lld", df_lld, append = TRUE)

# 12. Check if data arrived (optional count)
print(paste("Activities:", dbGetQuery(con, "SELECT count(*) FROM activity")))
print(paste("Sediment Data Points:", dbGetQuery(con, "SELECT count(*) FROM sediment")))

# Disconnect
dbDisconnect(con)
