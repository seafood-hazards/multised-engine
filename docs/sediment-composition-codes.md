# Sediment composition codes (ICES-DOME)

Grain-size parameters used in step 5 (`05_mark_additional_data.R`) to flag
whether sediment-composition data exist. Source: ICES-DOME.

| Code | Description |
|------|-------------|
| GS>1000<2000 | Grain Size Mass Fraction Range >1000 micron - <2000 |
| GS>125<250 | Grain Size Mass Fraction Range >125 micron - <250 |
| GS>2000<4000 | Grain Size Mass Fraction Range >2000 micron - <4000 |
| GS>200<600 | Grain Size Mass Fraction Range >200 micron - <600 |
| GS>20<60 | Grain Size Mass Fraction Range >20 micron - <60 |
| GS>250<500 | Grain Size Mass Fraction Range >250 micron - <500 |
| GS>4000<8000 | Grain Size Mass Fraction Range >4000 micron - <8000 |
| GS>500<1000 | Grain Size Mass Fraction Range >500 micron - <1000 |
| GS>600<2000 | Grain Size Mass Fraction Range >600 micron - <2000 |
| GS>60<200 | Grain Size Mass Fraction Range >60 micron - <200 |
| GS>63<125 | Grain Size Mass Fraction Range >63 micron - <125 |
| GS>63<2000 | Grain Size Mass Fraction Range >63 micron - <2000 (sand) |
| GSMF1 | Grain Size Mass Fraction <1 micron |
| GSMF1000 | Grain Size Mass Fraction <1000 micron |
| GSMF105 | Grain Size Mass Fraction <105 micron |
| GSMF1200 | Grain Size Mass Fraction <1200 micron |
| GSMF125 | Grain Size Mass Fraction <125 micron |
| GSMF15 | Grain Size Mass Fraction <15 micron |
| GSMF150 | Grain Size Mass Fraction <150 micron |
| GSMF16 | Grain Size Mass Fraction <16 micron |
| GSMF1700 | Grain Size Mass Fraction <1700 micron |
| GSMF2 | Grain Size Mass Fraction <2 micron |
| GSMF20 | Grain Size Mass Fraction <20 micron |
| GSMF200 | Grain Size Mass Fraction <200 micron |
| GSMF2000 | Grain Size Mass Fraction <2000 micron |
| GSMF210 | Grain Size Mass Fraction <210 micron |
| GSMF250 | Grain Size Mass Fraction <250 micron |
| GSMF3 | Grain Size Mass Fraction <3 micron |
| GSMF300 | Grain Size Mass Fraction <300 micron |
| GSMF31 | Grain Size Mass Fraction <31 micron |
| GSMF4 | Grain Size Mass Fraction <4 micron |
| GSMF420 | Grain Size Mass Fraction <420 micron |
| GSMF50 | Grain Size Mass Fraction <50 micron |
| GSMF500 | Grain Size Mass Fraction <500 micron |
| GSMF53 | Grain Size Mass Fraction <53 micron |
| GSMF600 | Grain Size Mass Fraction <600 micron |
| GSMF63 | Grain Size Mass Fraction <63 micron (silt/clay) |
| GSMF630 | Grain Size Mass Fraction <630 micron |
| GSMF7 | Grain Size Mass Fraction <7 micron |
| GSMF75 | Grain Size Mass Fraction <75 micron |
| GSMF8 | Grain Size Mass Fraction <8 micron |
| GSMF850 | Grain Size Mass Fraction <850 micron |
| GSMF90 | Grain Size Mass Fraction <90 micron |
| GSMF>2000 | Grain Size Mass Fraction >2000 micron (gravel) |
| GSMF>8000 | Grain Size Mass Fraction >8000 micron |

Note: each source encodes grain-size differently (e.g. Vannmiljø uses codes like
`GSMF2_63`, `GSMF_63`, `FINS`; MUDAB/ICES-DOME select by parameter group
`P-PHY`). The transform scripts (`01_transform_data.R`) show the per-source
selection used to populate `df_ref_*`.
