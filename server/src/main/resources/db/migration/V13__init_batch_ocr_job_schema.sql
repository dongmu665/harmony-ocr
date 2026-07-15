-- V1.2 批量 OCR 任务表：保存用户批量识别任务和单个文件 item 的处理状态。
-- 隐私边界：任务 item 只保存文件名、对象 key、状态和错误摘要，不保存图片二进制或 Access Token。
CREATE TABLE batch_ocr_jobs (
    job_id VARCHAR(64) PRIMARY KEY,
    user_id BIGINT NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_batch_ocr_jobs_user FOREIGN KEY (user_id) REFERENCES users(id)
);

CREATE TABLE batch_ocr_items (
    job_id VARCHAR(64) NOT NULL,
    item_index INT NOT NULL,
    file_name VARCHAR(255) NOT NULL,
    status VARCHAR(32) NOT NULL,
    record_id BIGINT,
    error_code VARCHAR(64),
    failure_reason VARCHAR(160),
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (job_id, item_index),
    CONSTRAINT fk_batch_ocr_items_job FOREIGN KEY (job_id) REFERENCES batch_ocr_jobs(job_id) ON DELETE CASCADE
);

CREATE INDEX idx_batch_ocr_jobs_user_created ON batch_ocr_jobs(user_id, created_at);
