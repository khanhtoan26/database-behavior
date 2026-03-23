# Index Selectivity Deep Dive (MySQL InnoDB vs PostgreSQL)

**Based on:** `index-selectivity/reports/run_2026-03-23_22-19-37_mysql.txt` and `index-selectivity/reports/run_2026-03-23_22-20-30_postgres.txt`  
**Experiment:** `index-selectivity/ddl/index-selectivity-mysql.sql` and `index-selectivity/ddl/index-selectivity-postgre.sql`

## 1. Why “index selectivity” is more than “does this predicate have an index?”

People often summarize selectivity like this:

> low selectivity => index is good; high selectivity => scan is bad

In practice, the key variable is the *total cost of producing the result rows*:

1. How many tuples/pages must be visited?
2. What access pattern do we use to visit them (random vs sequential, row-by-row vs batched)?
3. How expensive is the access path to fetch the full row data (secondary index lookup + clustered/heap fetch)?

The same index can be:

- an enormous win when it avoids touching most of the table
- an unexpected loss when the predicate matches so many rows that the “index helped me narrow the search” benefit disappears, but the engine still pays the overhead of reaching those rows

This experiment intentionally pushes into the “surprisingly high match rate” region: **`status='Active'` matches ~80% of the table**.

## 2. The experiment (what exactly we ran)

### 2.1 Schema

We create a table:

- `TestStatus(id, status, payload)`
- `payload` is a fixed-length `CHAR(200)` to keep the row reasonably non-trivial

We create an index on `status`:

- MySQL: `CREATE INDEX Index_Status ON TestStatus(status);`
- PostgreSQL: `CREATE INDEX index_status ON TestStatus(status);`

### 2.2 Data distribution

We generate **1,000,000 rows** with:

- `status='Active'`: ~0.8 (about 800,000 rows)
- `status='Inactive'`: ~0.2 (about 200,000 rows)

So the predicate `WHERE status='Active'` returns roughly 80% of the table.

### 2.3 Four `EXPLAIN ANALYZE` tests

We compare both default and forced planner behaviors:

1. `WHERE status='Active'` (optimizer default)
2. `WHERE status='Active'` (forced to use the index)
3. `WHERE status='Inactive'` (optimizer default)
4. `WHERE status='Active'` (forced *not* to use the index / disable index usage)

For PostgreSQL, “forced not to use index” is implemented via session settings; for MySQL it is implemented via `IGNORE INDEX`.

## 3. How to read the optimizer outputs (plan vocabulary)

### 3.1 MySQL (InnoDB) plan types in this run

In the MySQL `EXPLAIN ANALYZE` output, the important access patterns are:

- **`Index lookup ... using Index_Status (status='...')`**
  - Indicates the engine is using the secondary index on `status` to find candidate rows
  - For InnoDB, retrieving full rows typically requires going from the secondary index entry to the clustered record (a “double lookup” pattern)

- **`Table scan on TestStatus` + `Filter: (status = 'Active')`**
  - Indicates a sequential/semi-sequential traversal of the clustered data pages
  - Filtering happens as rows are read

### 3.2 PostgreSQL plan types in this run

In PostgreSQL, the relevant terms are:

- **`Bitmap Index Scan`** on `index_status`
  - Uses the index to produce a bitmap of matching tuple locations

- **`Bitmap Heap Scan`** on `teststatus`
  - Visits heap pages using the bitmap to reduce how many random fetches happen
  - Still uses the index as a guide, but fetches heap pages in a more batched way than pure index-driven row-by-row access

Important nuance from this experiment:

- Even when `enable_seqscan = off`, PostgreSQL still used bitmap access.
- When `enable_indexscan = off`, PostgreSQL still showed `Bitmap Index Scan` nodes. In other words: that setting did not fully remove index-based access paths because bitmap scanning remains in play.

## 4. Results: what happened at ~80% selectivity?

Below are the key `EXPLAIN ANALYZE` timings extracted from the runs (using the end of `actual time` as the main duration indicator).

### 4.1 MySQL (InnoDB)

Observed row counts:

- `status='Active'`: **799,659** rows (~79.97%)
- `status='Inactive'`: **200,341** rows (~20.03%)

Observed access paths and timings:

| Case | Access path | Rows returned | Timing (end of `actual time`) |
|---|---|---:|---:|
| Active (default) | `Index lookup ... status='Active'` | 799,659 | **1803 ms** |
| Active (forced index) | `Index lookup ... status='Active'` | 799,659 | **1925 ms** |
| Inactive (default) | `Index lookup ... status='Inactive'` | 200,341 | **820 ms** |
| Active (forced NOT index) | `Table scan` + `Filter` | 799,659 | **595 ms** (scan) / **711 ms** (filter) |

Key observation:

- At **~80% selectivity**, MySQL was substantially faster with **table scan** than with **index lookup**.
- For the ~20% case (`Inactive`), index lookup is clearly better (820 ms).

### 4.2 PostgreSQL

Observed row counts:

- `status='Active'`: **800,011** rows (~80.00%)
- `status='Inactive'`: **199,989** rows (~19.999%)

Observed access paths and timings:

All four cases used **`Bitmap Heap Scan`** (with an underlying `Bitmap Index Scan`):

| Case | Access path | Rows returned | Execution Time |
|---|---|---:|---:|
| Active (default) | Bitmap Heap Scan | 800,011 | **240.007 ms** |
| Active (enable_seqscan=off) | Bitmap Heap Scan | 800,011 | **192.499 ms** |
| Inactive (default) | Bitmap Heap Scan | 199,989 | **132.025 ms** |
| Active (enable_indexscan=off) | Bitmap Heap Scan | 800,011 | **185.018 ms** |

Key observation:

- PostgreSQL remained **index-assisted** (bitmap strategy) even when the predicate matched ~80% of the table.
- This suggests PostgreSQL’s bitmap approach successfully reduces the downside of “many matching index hits”.

## 5. Deep explanation: why the crossover happens around high selectivity

The experiment is essentially a controlled test of the “tipping point” between:

- **Index path:** avoid scanning most of the table, but pay overhead to reach each matching row through index structures
- **Scan path:** pay the cost of reading more data, but do it with a storage-friendly sequential access pattern

### 5.1 What makes index lookups expensive at high match rates (MySQL/InnoDB)

With a secondary index on `status`, the engine can:

1. Use the index to identify matching `status` entries
2. For each matching entry, fetch the full row from the clustered data structure

When `status='Active'` matches ~80%:

- you are no longer “skipping most rows”
- you are asking the engine to fetch a massive portion of the table via the index-driven fetch pattern

Even on SSDs or with buffer cache, the practical costs still include:

- overhead to traverse the secondary index structures at scale
- overhead to perform many heap/cluster lookups
- less predictable I/O batching compared to a pure scan path

So the scan path can win because it:

- reads pages in a more cache-friendly/sequential way
- avoids the repeated per-row (or per-location) overhead of index-driven access

That matches the measured result: **711 ms (filter) / 595 ms (scan) vs 1803-1925 ms (index lookup)**.

### 5.2 Why PostgreSQL’s bitmap strategy stays competitive

PostgreSQL’s `Bitmap Heap Scan` is designed for exactly this pain point:

- you may have many matching tuples (high match rate)
- but you still want to benefit from the index to avoid scanning unrelated pages

The bitmap approach:

1. Scans the index to build a bitmap of matching tuple locations
2. Fetches heap pages using that bitmap

This converts many small random fetches into more batched heap page fetches.

So even though the match rate is high (~80%), the engine avoids the worst version of “index-driven row-by-row random I/O”.

That’s why PostgreSQL can keep using bitmap index access rather than flipping entirely to a sequential scan in this particular experiment.

## 6. “Forcing” the planner: why it didn’t behave the way you might expect

### 6.1 MySQL: `USE INDEX` didn’t change the access path

In this run, `USE INDEX (Index_Status)` still produced **index lookup**.

The real comparison was therefore:

- default index decision vs scan forced via `IGNORE INDEX`

### 6.2 PostgreSQL: disabling `enable_indexscan` didn’t remove bitmap index access

In the run, the plan still contained `Bitmap Index Scan` nodes under `Bitmap Heap Scan` even after:

- `SET LOCAL enable_indexscan = off;`

This demonstrates a common pitfall when experimenting:

> planner knobs can disable a specific node type, but alternative index-assisted strategies (like bitmap scans) may still be allowed.

If your goal is “no index usage at all”, you typically need to disable the broader set of index scan mechanisms (for example: bitmap scans), or use an explicit query rewrite / planner settings that cover the right node classes.

## 7. Practical guidance: how to use selectivity safely

### 7.1 When index selectivity is poor, the “index exists” mindset can mislead

If your predicate matches a large portion of the table, then:

- the optimizer may still pick an index because it believes it can reduce page reads
- but the effective cost may be dominated by fetching and processing many qualifying rows

Your best tool is always:

- `EXPLAIN ANALYZE` in the environment that resembles production data distribution

### 7.2 Design tactics when you know the predicate is low-selectivity

Common ways to improve the effective selectivity:

- Add additional predicates that reduce the match set (more selective WHERE clauses)
- Add composite indexes that align with your query’s full filter pattern (not just a single low-cardinality column)
- Consider covering indexes if you can reduce “secondary index -> clustered row fetch” overhead
- Re-check statistics (especially for MySQL: `ANALYZE TABLE`; for PostgreSQL: `ANALYZE`)

### 7.3 For high match rate queries: prefer architectures that don’t require pulling everything

If your application truly needs 80% of the rows, then sometimes the best “optimization” is:

- query redesign (pagination, additional filters)
- pre-aggregation / materialization
- different access patterns (e.g., caching results, using summary tables)

## 8. Limitations of this experiment (so you don’t overfit the lesson)

This is a targeted experiment, so treat conclusions as evidence for a pattern, not a universal law:

- Data and payload size matter; different row widths and page layouts change costs
- Buffer cache state matters (warm vs cold runs)
- Storage type (SSD vs HDD), I/O concurrency, and MySQL/Postgres configuration influence outcomes
- The MySQL report file is large because the script also prints result rows for additional “pure execution time” selects; the key optimizer behavior is in the `EXPLAIN ANALYZE` sections

## 9. Suggested next experiments (to turn this into a full “selectivity tipping point” study)

If you want to map the crossover point precisely, extend the dataset:

1. Change the `Active` probability in the generator: 1%, 5%, 10%, 25%, 50%, 70%, 90%, 99%
2. Capture `EXPLAIN ANALYZE` for both default and forced behaviors
3. Compare:
   - MySQL: index lookup vs table scan timing curves
   - PostgreSQL: bitmap heap scan vs sequential scan behavior (and how it changes with selectivity)

If you do this, you can build an actual “tipping point” chart for each engine and configuration.

