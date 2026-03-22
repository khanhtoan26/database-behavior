-- ============================================
-- Index Selectivity Experiment (PostgreSQL)
-- Converted from MySQL test_data.sql
-- ============================================

DROP TABLE IF EXISTS TestStatus;

-- 1. Create table
CREATE TABLE TestStatus (
    id BIGSERIAL PRIMARY KEY,
    status VARCHAR(10),
    payload CHAR(200)
);

-- ============================================
-- 2. Generate 1,000,000 rows
-- 80% Active
-- 20% Inactive
-- ============================================

INSERT INTO TestStatus (status, payload)
SELECT
    CASE WHEN random() < 0.8 THEN 'Active' ELSE 'Inactive' END,
    RPAD('X',200,'X')
FROM generate_series(1,1000000);

-- Verify row count
SELECT COUNT(*) AS total_rows FROM TestStatus;

-- ============================================
-- 3. Create index
-- ============================================

CREATE INDEX index_status ON TestStatus(status);

-- ============================================
-- 4. Test 1 : Optimizer decision
-- ============================================

EXPLAIN ANALYZE
SELECT *
FROM TestStatus
WHERE status='Active';

-- ============================================
-- 5. Test 2 : Force index (disable sequential scans)
-- Note: this changes planner behavior for the session
-- ============================================

SET LOCAL enable_seqscan = off;
EXPLAIN ANALYZE
SELECT *
FROM TestStatus
WHERE status='Active';
SET LOCAL enable_seqscan = on;

-- ============================================
-- 6. Test 3 : High selectivity query
-- ============================================

EXPLAIN ANALYZE
SELECT *
FROM TestStatus
WHERE status='Inactive';

-- ============================================
-- 7. Test 4 : Force NOT using index (disable index scans)
-- ============================================

SET LOCAL enable_indexscan = off;
EXPLAIN ANALYZE
SELECT *
FROM TestStatus
WHERE status='Active';
SET LOCAL enable_indexscan = on;

-- ============================================
-- 8. Optional: measure pure execution time
-- Use psql's \timing on, or run these directly
-- ============================================

SELECT *
FROM TestStatus
WHERE status='Active'
LIMIT 100;

SELECT *
FROM TestStatus
WHERE status='Inactive'
LIMIT 100;
