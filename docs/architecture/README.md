# Architecture

High-level architecture docs for web, mobile, backend, and data layers.

## Current diagrams (draw.io)

Open these in draw.io (desktop or app.diagrams.net). Each diagram is its own file with a single page.

| File | Diagram |
|---|---|
| `GawaGo_Context_Diagram.drawio` | Context Diagram: GawaGo as one process with its seven external entities and the data flowing between them |
| `GawaGo_DFD_Level_2.drawio` | DFD Level 2: all 38 sub-processes on one page, grouped in labelled boxes by parent process (1.0-10.0), with the data stores D1-D17 and a data-store index |
| `GawaGo_ERD_Chen.drawio` | ERD in Chen notation: all 23 entities, 36 relationships with cardinality, and every attribute (keys underlined, derived dashed, multivalued double) |
| `GawaGo_Database_Schema.drawio` | dbdiagram-style schema: every table, column, type, PK/FK, with crow's-foot relationship lines |
| `GawaGo_Current_Database_Schema.dbml` | The same schema for dbdiagram.io (paste it in), plus the Django framework tables |

All were generated from the Django models and the API on 2026-10-26. In the diagrams no lines cross; in the DFD, entities and data stores repeat where needed, which is the standard DFD duplicate convention.

## Older figures

`Figure_3_3_*`, `Figure_3_4_*`, `GawaGo_Full_Data_Schema_ERD.drawio` and `Updated_Full_Data_Schema_ERD (1).drawio` predate the reports, chat, portfolio, audit-log and job-history tables, so they no longer match the database. They are kept for reference only.
