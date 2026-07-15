-- V1.2 导出任务表：保存当前用户发起的 TXT、Markdown、JSON、PDF 等导出任务元数据。
-- 隐私边界：导出内容文件进入对象存储，MySQL 只保存任务状态、格式、文件名和对象 key。
CREATE TABLE export_jobs (
    job_id VARCHAR(64) PRIMARY KEY,
    user_id BIGINT NOT NULL,
    status VARCHAR(32) NOT NULL,
    format VARCHAR(32) NOT NULL,
    file_name VARCHAR(160) NOT NULL,
    content_type VARCHAR(128) NOT NULL,
    size_bytes BIGINT NOT NULL,
    searchable BOOLEAN NOT NULL DEFAULT FALSE,
    degraded BOOLEAN NOT NULL DEFAULT FALSE,
    downgrade_reason VARCHAR(255),
    content LONGBLOB NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_export_jobs_user FOREIGN KEY (user_id) REFERENCES users(id)
);

CREATE INDEX idx_export_jobs_user_created ON export_jobs(user_id, created_at);
