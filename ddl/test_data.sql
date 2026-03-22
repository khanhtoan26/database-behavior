-- ============================================
-- Index Selectivity Experiment (MySQL)
-- ============================================

DROP TABLE IF EXISTS TestStatus;

-- 1. Create table
CREATE TABLE TestStatus (
    id INT AUTO_INCREMENT PRIMARY KEY,
    status VARCHAR(10),
    payload CHAR(200)
) ENGINE=InnoDB;

-- ============================================
-- 2. Generate 1,000,000 rows
-- 80% Active
-- 20% Inactive
-- ============================================

INSERT INTO TestStatus (status, payload)
SELECT
    IF(RAND() < 0.8, 'Active', 'Inactive'),
    RPAD('X',200,'X')
FROM
    (SELECT 1 FROM information_schema.columns LIMIT 1000) a,
    (SELECT 1 FROM information_schema.columns LIMIT 1000) b;

-- Verify row count
SELECT COUNT(*) AS total_rows FROM TestStatus;

-- ============================================
-- 3. Create index
-- ============================================

CREATE INDEX Index_Status
ON TestStatus(status);

-- ============================================
-- 4. Test 1 : Optimizer decision
-- ============================================

EXPLAIN ANALYZE
SELECT *
FROM TestStatus
WHERE status='Active';

-- ============================================
-- 5. Test 2 : Force index
-- ============================================

EXPLAIN ANALYZE
SELECT *
FROM TestStatus USE INDEX (Index_Status)
WHERE status='Active';

-- ============================================
-- 6. Test 3 : High selectivity query
-- ============================================

EXPLAIN ANALYZE
SELECT *
FROM TestStatus
WHERE status='Inactive';

-- ============================================
-- 8. Test 4 : Force NOT using index
-- ============================================

EXPLAIN ANALYZE
SELECT *
FROM TestStatus IGNORE INDEX (Index_Status)
WHERE status='Active';

-- ============================================
-- 7. Optional: measure pure execution time
-- ============================================

SELECT SQL_NO_CACHE *
FROM TestStatus
WHERE status='Active';

SELECT SQL_NO_CACHE *
FROM TestStatus USE INDEX (Index_Status)
WHERE status='Active';

SELECT SQL_NO_CACHE *
FROM TestStatus
WHERE status='Inactive';