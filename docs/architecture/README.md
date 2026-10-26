# Architecture

High-level architecture docs for web, mobile, backend, and data layers.

## Current diagrams (draw.io)

Open these in draw.io (desktop or app.diagrams.net); each file has several pages (tabs at the bottom).

| File | Pages |
|---|---|
| `GawaGo_Context_and_DFD.drawio` | Context Diagram; DFD Level 1 (processes 1.0-10.0, with a data-store index); DFD Level 2 for each of the ten processes |
| `GawaGo_ERD_Chen.drawio` | ERD Overview in Chen notation (all 23 entities and 36 relationships with cardinality); four attribute pages (Users and Security, Worker Portfolio, Jobs/Matching/Chat, Reviews and Reports) |
| `GawaGo_Database_Schema.drawio` | dbdiagram-style schema: every table, column, type, PK/FK, with crow's-foot relationship lines |
| `GawaGo_Current_Database_Schema.dbml` | The same schema for dbdiagram.io (paste it in), plus the Django framework tables |

All four were generated from the Django models and the API on 2026-10-26. In the diagrams no lines cross; DFD entities and data stores repeat per row where needed, which is the standard DFD duplicate convention.

## Older figures

`Figure_3_3_*`, `Figure_3_4_*`, `GawaGo_Full_Data_Schema_ERD.drawio` and `Updated_Full_Data_Schema_ERD (1).drawio` predate the reports, chat, portfolio, audit-log and job-history tables, so they no longer match the database. They are kept for reference only.
