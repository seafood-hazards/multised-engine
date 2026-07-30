library(readxl)


file_name <- "/scratch/data/sedimenter/WaterRegistrationExport.xlsx"
col_names <- c("site_code", "site_name", "label", "site_type", "activity_id", "activity_name", "client", "contractor", "param_id", "param_name", "cas_no", "medium_id", "medium_name", "taxon_id", "scientific_name", "sample_method", "analysis_method", "sample_time", "upper_depth", "lower_depth", "depth_unit", "is_filtered", "exclude_class", "operator", "value", "list_name", "unit", "sample_no", "lod", "loq", "origin", "n_values", "comment", "archive", "product_desc", "utm33_x", "utm33_y")


df <- read_excel(file_name)
colnames(df) <- col_names


df_vannmiljo_all_count <- df %>% count(param_id, param_name)

write_tsv(df_vannmiljo_all_count, "./data/vannmiljo_all_count.tsv.gz")
