# Index Selectivity Experiment (MySQL vs PostgreSQL)

## Summary

This experiment measures how an optimizer reacts when a predicate matches a large portion of the table (index selectivity around ~80%).

Dataset:
- `TestStatus(status, payload)` with 1,000,000 rows
- `status` distribution: `Active` ~80% and `Inactive` ~20%
- an index on `status`

What was compared:
- default optimizer decision for `WHERE status='Active'` vs `WHERE status='Inactive'`
- forced “use index” vs forced “avoid index” (via hints / planner settings)

Key results (from `EXPLAIN ANALYZE`):
- **MySQL (InnoDB):** for the ~80% case, the optimizer chose an index lookup, but forcing a table scan was faster in this run.
- **PostgreSQL:** the plan stayed index-assisted via `Bitmap Heap Scan` (with `Bitmap Index Scan`) even for the ~80% case.

## Menu

- `docs/index-selectivity-optimizer-compare.md`: side-by-side plan + timing summary from the exact `EXPLAIN ANALYZE` runs
- `docs/index-selectivity-deep-dive.md`: full deep dive (why the crossover happens, how to read the plans, and practical guidance)

# Index Selectivity Deep Dive Series

This series collects experiments and explanations about how database optimizers choose between:

- using an index (B+Tree / secondary index + row fetch)
- scanning more of the table (sequential access patterns)
- index-assisted strategies (e.g., PostgreSQL bitmap heap scan)

## Start here

- `../docs/index-selectivity-deep-dive.md`: the main deep dive based on the MySQL vs PostgreSQL `EXPLAIN ANALYZE` reports
- `../docs/index-selectivity-optimizer-compare.md`: side-by-side plan/timing summary for the 4 test cases

## Suggested next deep dives (topics)

- Low-cardinality / “many duplicates” indexes (when an index helps less)
- Secondary index “double lookup” overhead (why random fetches dominate)
- Covering indexes and index-only scans (reducing row-fetch cost)
- Composite indexes: how column order changes selectivity and plan choice
- Statistics, stale cardinality, and `ANALYZE TABLE` / `ANALYZE` effects on selectivity
- Bitmap vs index scan strategies (PostgreSQL focus; generalizable principles)
- Join selectivity: how filter selectivity interacts with join order
- Caching effects and warm vs cold runs (why timings can shift)

