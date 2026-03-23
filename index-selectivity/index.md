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