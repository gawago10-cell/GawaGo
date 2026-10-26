# Architecture

High-level architecture docs for web, mobile, backend, and data layers.

## Current diagrams (draw.io)

Open these in draw.io (desktop or app.diagrams.net). Each diagram is its own file with a single page.

| File | Diagram |
|---|---|
| `GawaGo_Context_Diagram.drawio` | Context Diagram: the platform as one system box, its five user roles, OpenRouteService (OSRM fallback), the email service and the PostgreSQL database, with one labelled line per data flow |
| `GawaGo_DFD_Level_2.drawio` | DFD Level 2: all 38 sub-processes on one page, grouped in labelled boxes by parent process (1.0-10.0), coloured like the context diagram, with open-ended data stores (`D1 \| User Accounts`) and a data-store index. Thick blue arrows carry the data each sub-process hands to the next, so the page reads as one connected flow from sign-up to reports |
| `GawaGo_ERD_Chen.drawio` | ERD in Chen notation, laid out in rows: every entity with its attribute ovals stacked on both sides (keys underlined, derived dashed, multivalued double), all 36 relationships as diamonds between the rows, with cardinality |
| `GawaGo_Database_Schema.drawio` | dbdiagram-style schema: every table, column, type, PK/FK, with crow's-foot relationship lines |
| `GawaGo_Current_Database_Schema.dbml` | The same schema for dbdiagram.io (paste it in), plus the Django framework tables |

All were generated from the Django models and the API on 2026-10-26. In the diagrams no lines cross; in the DFD, entities and data stores repeat where needed, which is the standard DFD duplicate convention.

## Older figures

`Figure_3_3_*`, `Figure_3_4_*`, `GawaGo_Full_Data_Schema_ERD.drawio` and `Updated_Full_Data_Schema_ERD (1).drawio` predate the reports, chat, portfolio, audit-log and job-history tables, so they no longer match the database. They are kept for reference only.
