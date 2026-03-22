-- ============================================
-- SQL Script: Generate 1 Million Records for Index Testing
-- Purpose: Test Index vs Full Scan Performance
-- ============================================

-- Tạo database nếu chưa tồn tại
-- CREATE DATABASE IF NOT EXISTS test_db;
-- USE test_db;

-- ============================================
-- 1. Tạo bảng test_table
-- ============================================
DROP TABLE IF EXISTS test_table;

CREATE TABLE test_table (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    status VARCHAR(50) NOT NULL,
    user_name VARCHAR(100) NOT NULL,
    email VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    amount DECIMAL(10, 2),
    description TEXT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================
-- 2. Tạo Stored Procedure để generate 1,000,000 records (100 batches × 10,000)
-- Sử dụng cross-join 0..9 × 0..9 × 0..9 × 0..9 = 10,000 rows per batch
-- ============================================
DELIMITER //

CREATE PROCEDURE populate_test_table()
BEGIN
    DECLARE batch INT DEFAULT 0;
    DECLARE batch_size INT DEFAULT 10000;
    DECLARE total_batches INT DEFAULT 100; -- 100 × 10,000 = 1,000,000
    DECLARE offset_val INT;

    SET autocommit = 0;

    WHILE batch < total_batches DO
        SET offset_val = batch * batch_size;

        INSERT INTO test_table (status, user_name, email, amount, description)
        SELECT
            CASE
                WHEN RAND() < 0.80 THEN 'Active'
                WHEN RAND() < 0.90 THEN 'Inactive'
                WHEN RAND() < 0.95 THEN 'Pending'
                ELSE 'Deleted'
            END AS status,
            CONCAT('user_', offset_val + (a.n*1000 + b.n*100 + c.n*10 + d.n) + 1) AS user_name,
            CONCAT('user_', offset_val + (a.n*1000 + b.n*100 + c.n*10 + d.n) + 1, '@example.com') AS email,
            ROUND(RAND() * 10000, 2) AS amount,
            CONCAT('Description for record ', offset_val + (a.n*1000 + b.n*100 + c.n*10 + d.n) + 1) AS description
        FROM
            (SELECT 0 AS n UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9) a
        CROSS JOIN (SELECT 0 AS n UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9) b
        CROSS JOIN (SELECT 0 AS n UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9) c
        CROSS JOIN (SELECT 0 AS n UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9) d;

        COMMIT;
        SET batch = batch + 1;
    END WHILE;

    SET autocommit = 1;
END //

DELIMITER ;

-- ============================================
-- 3. Chạy Stored Procedure để generate 1,000,000 records
-- ============================================
CALL populate_test_table();

-- ============================================
-- 4. Tạo Index trên cột status
-- ============================================
CREATE INDEX idx_status ON test_table(status);

-- ============================================
-- 5. Kiểm chứng dữ liệu
-- ============================================
-- Xem tổng số bản ghi
SELECT COUNT(*) AS total_records FROM test_table;

-- Xem phân bố Status
SELECT status, COUNT(*) AS count,
       ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM test_table), 2) AS percentage
FROM test_table
GROUP BY status
ORDER BY count DESC;

-- ============================================
-- 6. TEST queries
-- ============================================
-- SELECT COUNT(*) FROM test_table WHERE status = 'Active';
-- SELECT * FROM test_table USE INDEX (idx_status) WHERE status = 'Active' LIMIT 10;
-- SELECT * FROM test_table IGNORE INDEX (idx_status) WHERE status = 'Active' LIMIT 10;
-- EXPLAIN SELECT COUNT(*) FROM test_table WHERE status = 'Active';
-- EXPLAIN SELECT COUNT(*) FROM test_table USE INDEX (idx_status) WHERE status = 'Active';
