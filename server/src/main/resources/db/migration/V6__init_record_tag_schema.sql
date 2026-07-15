-- V1.2 历史标签迁移：新增用户级 OCR 标签表和记录-标签绑定表，所有外键均按用户资源隔离并在删除时清理关联。
CREATE TABLE recognition_tags (
    id BIGINT NOT NULL AUTO_INCREMENT,
    user_id BIGINT NOT NULL,
    name VARCHAR(64) NOT NULL,
    normalized_name VARCHAR(64) NOT NULL,
    color VARCHAR(32) NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uk_tags_user_normalized_name (user_id, normalized_name),
    KEY idx_tags_user_created (user_id, created_at),
    CONSTRAINT fk_recognition_tags_user
        FOREIGN KEY (user_id) REFERENCES users (id)
        ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE recognition_record_tags (
    id BIGINT NOT NULL AUTO_INCREMENT,
    user_id BIGINT NOT NULL,
    record_id BIGINT NOT NULL,
    tag_id BIGINT NOT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uk_record_tags_record_tag (record_id, tag_id),
    KEY idx_record_tags_user_tag (user_id, tag_id),
    KEY idx_record_tags_record (record_id),
    CONSTRAINT fk_record_tags_user
        FOREIGN KEY (user_id) REFERENCES users (id)
        ON DELETE CASCADE,
    CONSTRAINT fk_record_tags_record
        FOREIGN KEY (record_id) REFERENCES recognition_records (id)
        ON DELETE CASCADE,
    CONSTRAINT fk_record_tags_tag
        FOREIGN KEY (tag_id) REFERENCES recognition_tags (id)
        ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE INDEX idx_records_user_engine_created
    ON recognition_records (user_id, ocr_engine, created_at);
