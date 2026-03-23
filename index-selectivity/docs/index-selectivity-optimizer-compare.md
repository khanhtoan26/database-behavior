# Index Selectivity & Optimizer Decisions (MySQL vs PostgreSQL)

**Date:** 2026-03-23  
**Experiment folder:** `index-selectivity/ddl/`  
Raw reports are available under `index-selectivity/reports/`, but this document summarizes only the relevant `EXPLAIN ANALYZE` sections (plan type + timing).

## 1. Test setup

Both DBs run the same logical experiment:

- Build `TestStatus` with **1,000,000 rows**
- `status` distribution:
  - **Active ~80%** (about 800k rows)
  - **Inactive ~20%** (about 200k rows)
- Create an index on `status` (`Index_Status` in MySQL, `index_status` in PostgreSQL)

Four `EXPLAIN ANALYZE` tests are executed:

1. `WHERE status='Active'` (optimizer default)
2. `WHERE status='Active'` (optimizer forced to use the index)
3. `WHERE status='Inactive'` (optimizer default)
4. `WHERE status='Active'` (optimizer forced *not* to use the index)

## 2. MySQL (InnoDB) observations

### 2.1 What the optimizer chose

For the **high-selectivity / “large result set” case** (`Active` ~80%):

- Test 1 (default): **`Index lookup`** on `Index_Status`
- Test 2 (force index): **`Index lookup`** on `Index_Status` again
- Test 4 (force NOT using index): **`Table scan` + filter** (`status='Active'`)

For the **lower-selectivity case** (`Inactive` ~20%):

- Test 3 (default): **`Index lookup`** on `Index_Status`

### 2.2 Key timings from `EXPLAIN ANALYZE`

> The MySQL plan lines show `actual time=<start>..<end>`; below we use the **end** value as the dominant runtime indicator.

| Case | Access path | Rows returned | `actual time` end |
|---|---|---:|---:|
| Active (default) | `Index lookup` | 799,659 | **1803 ms** |
| Active (force index) | `Index lookup` | 799,659 | **1925 ms** |
| Inactive (default) | `Index lookup` | 200,341 | **820 ms** |
| Active (force NOT index) | `Table scan` + filter | ~799,659 (filter) / ~1,000,000 (scan) | **711 ms** (filter) / **595 ms** (scan) |

### 2.3 Interpretation

When the predicate matches a **very large fraction of the table (~80%)**, the index path can become unfavorable:

- secondary index lookups still lead to reading a huge number of data rows
- the access pattern becomes much closer to “many scattered reads” than an efficient sequential scan

In this run, **`Table scan` is dramatically faster than `Index lookup`** for `Active` (711 ms vs 1803–1925 ms), suggesting the optimizer’s cost model is misaligned for this data distribution.

## 3. PostgreSQL observations

### 3.1 What the optimizer chose

Across all four tests, the execution plan node type is **`Bitmap Heap Scan`** with a **`Bitmap Index Scan`** underneath:

- Even when sequence scans are disabled (`enable_seqscan = off`), PostgreSQL still uses the bitmap approach.
- When index scans are “disabled” (`enable_indexscan = off`), PostgreSQL did **not** fully stop index-based access because **bitmap scans are still allowed**.

### 3.2 Key timings from `EXPLAIN ANALYZE`

| Case | Access path | Rows returned | Execution Time |
|---|---|---:|---:|
| Active (default) | `Bitmap Heap Scan` (via bitmap index) | 800,011 | **240.007 ms** |
| Active (enable_seqscan = off) | `Bitmap Heap Scan` | 800,011 | **192.499 ms** |
| Inactive (default) | `Bitmap Heap Scan` | 199,989 | **132.025 ms** |
| Active (enable_indexscan = off) | `Bitmap Heap Scan` | 800,011 | **185.018 ms** |

### 3.3 Interpretation

PostgreSQL’s bitmap strategy is designed to reduce the penalty of many index hits:

- it accumulates matching tuple locations into a bitmap
- then fetches heap pages efficiently (less random I/O than pure index-driven row-by-row fetching)

That’s why the plan stays in “index-assisted” mode even for the ~80% case.

## 4. What this means for index selectivity

### 4.1 The core idea

Index selectivity is not just “is there an index?” but “how many rows does the predicate produce relative to the table?”

At ~80% match rate:

- index-driven execution can lose due to the cost of fetching so many rows
- full scan / sequential access can win because it reads data in a more storage-friendly pattern

### 4.2 Practical recommendations

1. **Validate with `EXPLAIN ANALYZE`** (not just `EXPLAIN`): the crossover point depends on table size, storage characteristics, and runtime statistics.
2. **For MySQL:** keep in mind that low-to-medium selectivity predicates can cause “index chosen but worse performance” outcomes.
3. **For PostgreSQL:** disabling `enable_indexscan` doesn’t necessarily eliminate index usage; to fully force sequential behavior you typically need to also disable bitmap scanning (e.g., `enable_bitmapscan = off`) in addition to `enable_indexscan = off`.
4. **When selectivity is poor, add more predicates** (or redesign indexes) so the plan can avoid touching a large portion of the table.

