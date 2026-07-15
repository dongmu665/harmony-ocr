-- V1.0 OCR 历史记录基础表：保存当前用户的识别文本、编辑文本和文本块。
-- 隐私边界：记录必须按 user_id 做归属校验；图片二进制不进入 MySQL，只保存对象存储 key。
CREATE TABLE recognition_records (
    id BIGINT NOT NULL AUTO_INCREMENT,
    user_id BIGINT NOT NULL,
    title VARCHAR(128) NULL,
    source_type VARCHAR(32) NOT NULL,
    image_object_key VARCHAR(512) NULL,
    raw_text MEDIUMTEXT NULL,
    edited_text MEDIUMTEXT NULL,
    language VARCHAR(32) NULL,
    ocr_engine VARCHAR(64) NULL,
    duration_ms INT NULL,
    favorite TINYINT NOT NULL DEFAULT 0,
    deleted TINYINT NOT NULL DEFAULT 0,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    deleted_at DATETIME NULL,
    PRIMARY KEY (id),
    KEY idx_records_user_created (user_id, created_at),
    KEY idx_records_user_favorite (user_id, favorite),
    KEY idx_records_user_deleted (user_id, deleted),
    KEY idx_records_user_source_created (user_id, source_type, created_at),
    CONSTRAINT fk_recognition_records_user
        FOREIGN KEY (user_id) REFERENCES users (id)
        ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE recognition_blocks (
    id BIGINT NOT NULL AUTO_INCREMENT,
    record_id BIGINT NOT NULL,
    block_index INT NOT NULL,
    text TEXT NULL,
    confidence DECIMAL(5,4) NULL,
    bounding_box JSON NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_blocks_record_id (record_id),
    CONSTRAINT fk_recognition_blocks_record
        FOREIGN KEY (record_id) REFERENCES recognition_records (id)
        ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
