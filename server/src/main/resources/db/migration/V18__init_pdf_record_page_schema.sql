-- V1.2 PDF OCR 页级结果表：保存多页 PDF 的页状态、页文本和页内文本块。
-- 隐私边界：页级数据仍归属于 recognition_records.user_id；不得绕过记录归属直接跨用户读取。
CREATE TABLE recognition_record_pages (
    id BIGINT NOT NULL AUTO_INCREMENT,
    record_id BIGINT NOT NULL,
    page_index INT NOT NULL,
    page_number INT NOT NULL,
    status VARCHAR(16) NOT NULL,
    raw_text MEDIUMTEXT NULL,
    edited_text MEDIUMTEXT NULL,
    duration_ms INT NULL,
    confidence DECIMAL(5,4) NULL,
    error_code VARCHAR(64) NULL,
    failure_reason VARCHAR(255) NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uk_record_pages_record_page_index (record_id, page_index),
    KEY idx_record_pages_record_id (record_id),
    CONSTRAINT fk_record_pages_record
        FOREIGN KEY (record_id) REFERENCES recognition_records (id)
        ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE recognition_record_page_blocks (
    id BIGINT NOT NULL AUTO_INCREMENT,
    record_id BIGINT NOT NULL,
    page_id BIGINT NOT NULL,
    block_index INT NOT NULL,
    text TEXT NULL,
    confidence DECIMAL(5,4) NULL,
    bounding_box JSON NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uk_page_blocks_page_index (page_id, block_index),
    KEY idx_page_blocks_record_id (record_id),
    KEY idx_page_blocks_page_id (page_id),
    CONSTRAINT fk_page_blocks_record
        FOREIGN KEY (record_id) REFERENCES recognition_records (id)
        ON DELETE CASCADE,
    CONSTRAINT fk_page_blocks_page
        FOREIGN KEY (page_id) REFERENCES recognition_record_pages (id)
        ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
