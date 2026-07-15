-- V1.2 导出任务状态事件表：保存导出任务进度变化的审计时间线。
-- 维护边界：事件只包含状态和进度，不保存导出文件内容、对象存储凭据或 OCR 全文。
CREATE TABLE export_job_status_events (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    job_id VARCHAR(64) NOT NULL,
    status VARCHAR(32) NOT NULL,
    progress INT NOT NULL DEFAULT 0,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_export_job_status_events_job
        FOREIGN KEY (job_id) REFERENCES export_jobs(job_id) ON DELETE CASCADE
);

CREATE INDEX idx_export_job_status_events_job_id ON export_job_status_events(job_id, id);
