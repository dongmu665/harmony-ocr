package com.harmonyocr.ocr.service;

import com.harmonyocr.common.error.BusinessException;
import com.harmonyocr.common.error.ErrorCode;
import com.harmonyocr.ocr.dto.BatchOcrItemResponse;
import com.harmonyocr.ocr.dto.BatchOcrItemStatus;
import com.harmonyocr.ocr.dto.BatchOcrJobResponse;
import com.harmonyocr.ocr.dto.BatchOcrTaskItemSummaryResponse;
import com.harmonyocr.ocr.dto.BatchOcrTaskSummaryResponse;
import com.harmonyocr.ocr.dto.OcrRecognizeResponse;
import com.harmonyocr.record.dto.CreateRecordRequest;
import com.harmonyocr.record.dto.RecordBlockRequest;
import com.harmonyocr.record.dto.RecordBlockResponse;
import com.harmonyocr.record.dto.RecordPageRequest;
import com.harmonyocr.record.dto.RecordPageResponse;
import com.harmonyocr.record.dto.RecordResponse;
import com.harmonyocr.record.service.RecordService;
import java.math.BigDecimal;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;

/**
 * 批量 OCR 服务，属于 ocr 模块。
 * 维护说明：V2.0 复用现有 OCR Provider 处理小批量图片，并将任务、item 状态和重试次数持久化到数据库。
 * 当前 worker 在请求线程内执行，生产级异步调度、多节点领取和生命周期清理仍由后续生产架构处理。
 */
@Service
public class BatchOcrService {

    private static final RowMapper<MutableBatchJob> BATCH_JOB_ROW_MAPPER = (rs, rowNum) -> new MutableBatchJob(
            rs.getString("job_id"),
            rs.getLong("user_id"),
            BatchJobStatus.valueOf(rs.getString("status")),
            rs.getInt("progress"),
            rs.getLong("record_id") == 0 && rs.wasNull() ? null : rs.getLong("record_id"),
            rs.getTimestamp("created_at").toInstant());
    private static final RowMapper<MutableBatchItem> BATCH_ITEM_ROW_MAPPER = (rs, rowNum) -> new MutableBatchItem(
            rs.getInt("item_index"),
            rs.getString("file_name"),
            BatchOcrItemStatus.valueOf(rs.getString("status")),
            rs.getLong("record_id") == 0 && rs.wasNull() ? null : rs.getLong("record_id"),
            rs.getString("error_code"),
            rs.getString("failure_reason"),
            rs.getInt("retry_count"));

    private final OcrRecognitionService ocrRecognitionService;
    private final RecordService recordService;
    private final JdbcTemplate jdbcTemplate;

    public BatchOcrService(OcrRecognitionService ocrRecognitionService, RecordService recordService, JdbcTemplate jdbcTemplate) {
        this.ocrRecognitionService = ocrRecognitionService;
        this.recordService = recordService;
        this.jdbcTemplate = jdbcTemplate;
    }

    /**
     * 创建批量 OCR 任务并同步处理所有 item。
     * 参数 userId 来自认证上下文，files 为已上传图片数组；返回每项 SUCCESS/FAILED 结果。安全注意：失败不会中断其他 item。
     */
    public BatchOcrJobResponse create(Long userId, MultipartFile[] files, String language, boolean saveToHistory) {
        if (files == null || files.length == 0) {
            throw new BusinessException(ErrorCode.VALIDATION_ERROR, "files must not be empty");
        }
        MutableBatchJob job = new MutableBatchJob(UUID.randomUUID().toString(), userId, BatchJobStatus.QUEUED, 0, null, Instant.now());
        saveJob(job);
        for (int i = 0; i < files.length; i++) {
            job.items.add(MutableBatchItem.queued(i, safeFileName(files[i])));
            saveItem(job.jobId, job.items.get(i));
        }
        markJob(job, BatchJobStatus.RUNNING);
        for (int i = 0; i < files.length; i++) {
            processItem(job, i, files[i], language, false);
        }
        refreshJobState(job, false);
        syncAggregateRecord(job, saveToHistory);
        return toResponse(job);
    }

    /**
     * 重试指定失败 item。
     * 参数 jobId 和 itemIndex 必须属于当前用户；file 是用户重新上传的图片。成功后刷新任务进度。
     */
    public BatchOcrJobResponse retry(Long userId, String jobId, int itemIndex, MultipartFile file, String language, boolean saveToHistory) {
        MutableBatchJob job = ownedJob(userId, jobId);
        if (itemIndex < 0 || itemIndex >= job.items.size()) {
            throw new BusinessException(ErrorCode.NOT_FOUND);
        }
        MutableBatchItem item = job.items.get(itemIndex);
        if (item.status != BatchOcrItemStatus.FAILED) {
            throw new BusinessException(ErrorCode.VALIDATION_ERROR, "only failed item can be retried");
        }
        item.fileName = safeFileName(file);
        markJob(job, BatchJobStatus.RETRYING);
        item.retryCount++;
        processItem(job, itemIndex, file, language, true);
        refreshJobState(job, false);
        syncAggregateRecord(job, saveToHistory || job.recordId != null);
        return toResponse(job);
    }

    /**
     * 查询当前用户的批量 OCR 任务摘要。
     * 参数 userId 来自认证上下文；返回值按创建时间倒序排列，且不携带 OCR 全文。
     */
    public List<BatchOcrTaskSummaryResponse> listOwned(Long userId) {
        return jdbcTemplate.query("""
                        SELECT job_id, user_id, status, progress, record_id, created_at
                        FROM batch_ocr_jobs
                        WHERE user_id = ?
                        ORDER BY created_at DESC
                        """, BATCH_JOB_ROW_MAPPER, userId)
                .stream()
                .peek(this::loadItems)
                .peek(this::consolidateLegacyItemRecordsIfNeeded)
                .map(this::toSummaryResponse)
                .toList();
    }

    /**
     * 查询当前用户拥有的单个批量 OCR 任务摘要。
     * 参数 jobId 必须属于当前用户；越权和不存在统一返回 NOT_FOUND，避免泄露其他用户任务。
     */
    public BatchOcrTaskSummaryResponse detailOwned(Long userId, String jobId) {
        return toSummaryResponse(ownedJob(userId, jobId));
    }

    /**
     * 取消当前用户拥有的未完成批量 OCR 任务。
     * 安全注意：只更新任务和 item 的脱敏状态，不读取图片内容或 OCR 全文；已完成/失败任务不可被改写。
     */
    public BatchOcrJobResponse cancel(Long userId, String jobId) {
        MutableBatchJob job = ownedJob(userId, jobId);
        if (job.status == BatchJobStatus.SUCCESS || job.status == BatchJobStatus.FAILED || job.status == BatchJobStatus.CANCELED) {
            throw new BusinessException(ErrorCode.VALIDATION_ERROR, "only queued or running batch can be canceled");
        }
        for (MutableBatchItem item : job.items) {
            if (item.status == BatchOcrItemStatus.QUEUED
                    || item.status == BatchOcrItemStatus.PENDING
                    || item.status == BatchOcrItemStatus.RUNNING
                    || item.status == BatchOcrItemStatus.RETRYING) {
                item.status = BatchOcrItemStatus.CANCELED;
                item.errorCode = null;
                item.failureReason = null;
                item.result = null;
                updateItem(job.jobId, item);
            }
        }
        job.status = BatchJobStatus.CANCELED;
        jdbcTemplate.update("""
                UPDATE batch_ocr_jobs
                SET status = ?, progress = ?, updated_at = CURRENT_TIMESTAMP
                WHERE job_id = ? AND user_id = ?
                """,
                job.status.name(),
                job.progress,
                job.jobId,
                job.userId);
        loadItems(job);
        return toResponse(job);
    }

    private void processItem(MutableBatchJob job, int itemIndex, MultipartFile file, String language, boolean retrying) {
        MutableBatchItem item = job.items.get(itemIndex);
        item.status = retrying ? BatchOcrItemStatus.RETRYING : BatchOcrItemStatus.RUNNING;
        item.errorCode = null;
        item.failureReason = null;
        item.result = null;
        item.recordId = null;
        updateItem(job.jobId, item);
        try {
            OcrRecognizeResponse result = ocrRecognitionService.recognize(file, language);
            item.result = result;
            item.status = BatchOcrItemStatus.SUCCESS;
        } catch (BusinessException ex) {
            item.status = BatchOcrItemStatus.FAILED;
            item.errorCode = ex.getErrorCode().getCode();
            item.failureReason = safeFailureReason(ex.getMessage());
        } catch (RuntimeException ex) {
            item.status = BatchOcrItemStatus.FAILED;
            item.errorCode = ErrorCode.INTERNAL_ERROR.getCode();
            item.failureReason = "Batch OCR item failed";
        }
        updateItem(job.jobId, item);
        refreshJobState(job, false);
    }

    /**
     * 同步批量任务的一条聚合历史记录。
     * 参数 allowCreate 控制没有旧记录时是否创建新记录；重试会优先更新旧记录，避免同一批次产生多条历史记录。
     */
    private void syncAggregateRecord(MutableBatchJob job, boolean allowCreate) {
        if (!allowCreate && job.recordId == null) {
            return;
        }
        RecordResponse existingRecord = loadAggregateRecordOrNull(job);
        if (existingRecord == null && !allowCreate) {
            job.recordId = null;
            updateJobRecordId(job);
            return;
        }
        CreateRecordRequest request = toAggregateRecordRequest(job, existingRecord);
        RecordResponse record = existingRecord == null
                ? recordService.create(job.userId, request)
                : recordService.replaceGeneratedContent(job.userId, existingRecord.id(), request);
        job.recordId = record.id();
        updateJobRecordId(job);
        for (MutableBatchItem item : job.items) {
            item.recordId = record.id();
            updateItem(job.jobId, item);
        }
    }

    /**
     * 兼容旧版本“每个批量 item 一条 import 历史记录”的数据。
     * 安全边界：只通过 RecordService 读取当前用户自己的旧记录；合并过程不记录 OCR 全文、图片路径或 Token。
     */
    private void consolidateLegacyItemRecordsIfNeeded(MutableBatchJob job) {
        if (job.recordId != null || job.items.isEmpty() || !hasLegacyItemRecordIds(job)) {
            return;
        }
        RecordResponse existingSharedAggregate = sharedBatchAggregateRecordOrNull(job);
        if (existingSharedAggregate != null) {
            job.recordId = existingSharedAggregate.id();
            updateJobRecordId(job);
            return;
        }
        List<RecordPageRequest> pages = new ArrayList<>();
        List<RecordResponse> legacyRecords = new ArrayList<>();
        for (MutableBatchItem item : job.items) {
            RecordResponse legacyRecord = loadRecordOrNull(job.userId, item.recordId);
            if (legacyRecord != null) {
                legacyRecords.add(legacyRecord);
                pages.add(legacyRecordPageRequest(item, legacyRecord));
            } else {
                pages.add(toRecordPageRequest(item, null, item.itemIndex));
            }
        }
        if (legacyRecords.isEmpty()) {
            return;
        }
        RecordResponse aggregateRecord = recordService.create(job.userId, legacyAggregateRecordRequest(pages, legacyRecords));
        job.recordId = aggregateRecord.id();
        updateJobRecordId(job);
        for (MutableBatchItem item : job.items) {
            item.recordId = aggregateRecord.id();
            updateItem(job.jobId, item);
        }
        for (RecordResponse legacyRecord : legacyRecords) {
            recordService.softDelete(job.userId, legacyRecord.id());
        }
    }

    private boolean hasLegacyItemRecordIds(MutableBatchJob job) {
        for (MutableBatchItem item : job.items) {
            if (item.recordId != null) {
                return true;
            }
        }
        return false;
    }

    private RecordResponse sharedBatchAggregateRecordOrNull(MutableBatchJob job) {
        Long sharedRecordId = null;
        for (MutableBatchItem item : job.items) {
            if (item.recordId == null) {
                return null;
            }
            if (sharedRecordId == null) {
                sharedRecordId = item.recordId;
            } else if (!sharedRecordId.equals(item.recordId)) {
                return null;
            }
        }
        RecordResponse record = loadRecordOrNull(job.userId, sharedRecordId);
        if (record != null && "batch".equals(record.sourceType())) {
            return record;
        }
        return null;
    }

    private RecordResponse loadRecordOrNull(Long userId, Long recordId) {
        if (recordId == null) {
            return null;
        }
        try {
            return recordService.detail(userId, recordId);
        } catch (BusinessException ex) {
            if (ex.getErrorCode() == ErrorCode.NOT_FOUND) {
                return null;
            }
            throw ex;
        }
    }

    private CreateRecordRequest legacyAggregateRecordRequest(List<RecordPageRequest> pages, List<RecordResponse> legacyRecords) {
        String rawText = aggregatePageText(pages, false);
        String editedText = aggregatePageText(pages, true);
        return new CreateRecordRequest(
                "批量 OCR",
                "batch",
                null,
                rawText,
                editedText,
                firstLegacyLanguage(legacyRecords),
                firstLegacyEngine(legacyRecords),
                aggregateDurationMs(pages),
                false,
                List.of(),
                pages);
    }

    private RecordPageRequest legacyRecordPageRequest(MutableBatchItem item, RecordResponse legacyRecord) {
        String pageStatus = item.status == BatchOcrItemStatus.FAILED ? "FAILED" : "SUCCESS";
        return new RecordPageRequest(
                item.itemIndex,
                item.itemIndex + 1,
                pageStatus,
                legacyRecord.rawText(),
                legacyRecord.editedText(),
                legacyRecord.durationMs(),
                null,
                item.errorCode,
                item.status == BatchOcrItemStatus.FAILED ? item.failureReason : null,
                legacyRecord.blocks() == null ? List.of() : legacyRecord.blocks().stream()
                        .map(this::toRecordBlockRequest)
                        .toList());
    }

    private String firstLegacyLanguage(List<RecordResponse> legacyRecords) {
        for (RecordResponse record : legacyRecords) {
            if (record.language() != null && !record.language().isBlank()) {
                return record.language();
            }
        }
        return null;
    }

    private String firstLegacyEngine(List<RecordResponse> legacyRecords) {
        for (RecordResponse record : legacyRecords) {
            if (record.ocrEngine() != null && !record.ocrEngine().isBlank()) {
                return record.ocrEngine();
            }
        }
        return null;
    }

    private RecordResponse loadAggregateRecordOrNull(MutableBatchJob job) {
        if (job.recordId == null) {
            return null;
        }
        try {
            return recordService.detail(job.userId, job.recordId);
        } catch (BusinessException ex) {
            if (ex.getErrorCode() == ErrorCode.NOT_FOUND) {
                return null;
            }
            throw ex;
        }
    }

    private CreateRecordRequest toAggregateRecordRequest(MutableBatchJob job, RecordResponse existingRecord) {
        List<RecordPageRequest> pages = new ArrayList<>();
        for (MutableBatchItem item : job.items) {
            pages.add(toRecordPageRequest(item, existingPage(existingRecord, item.itemIndex), item.itemIndex));
        }
        String rawText = aggregatePageText(pages, false);
        String editedText = aggregatePageText(pages, true);
        return new CreateRecordRequest(
                "批量 OCR",
                "batch",
                null,
                rawText,
                editedText,
                aggregateLanguage(job, existingRecord),
                aggregateEngine(job, existingRecord),
                aggregateDurationMs(pages),
                false,
                List.of(),
                pages);
    }

    private RecordPageResponse existingPage(RecordResponse existingRecord, int pageIndex) {
        if (existingRecord == null || existingRecord.pages() == null) {
            return null;
        }
        for (RecordPageResponse page : existingRecord.pages()) {
            if ((page.pageIndex() == null ? -1 : page.pageIndex()) == pageIndex) {
                return page;
            }
        }
        return null;
    }

    private RecordPageRequest toRecordPageRequest(MutableBatchItem item, RecordPageResponse existingPage, int fallbackIndex) {
        if (item.status == BatchOcrItemStatus.SUCCESS) {
            if (item.result != null) {
                return successPageRequest(fallbackIndex, item.result);
            }
            if (existingPage != null) {
                return copyPageRequest(existingPage, fallbackIndex);
            }
            return new RecordPageRequest(fallbackIndex, fallbackIndex + 1, "SUCCESS", "", "", null, null, null, null, List.of());
        }
        if (item.status == BatchOcrItemStatus.FAILED) {
            return new RecordPageRequest(
                    fallbackIndex,
                    fallbackIndex + 1,
                    "FAILED",
                    "",
                    "",
                    null,
                    null,
                    item.errorCode,
                    item.failureReason,
                    List.of());
        }
        if (existingPage != null) {
            return copyPageRequest(existingPage, fallbackIndex);
        }
        return new RecordPageRequest(
                fallbackIndex,
                fallbackIndex + 1,
                "FAILED",
                "",
                "",
                null,
                null,
                item.status.name(),
                "Batch OCR item is not completed",
                List.of());
    }

    private RecordPageRequest successPageRequest(int itemIndex, OcrRecognizeResponse result) {
        return new RecordPageRequest(
                itemIndex,
                itemIndex + 1,
                "SUCCESS",
                result.rawText(),
                result.editedText(),
                Math.toIntExact(Math.min(result.durationMs(), Integer.MAX_VALUE)),
                result.confidence(),
                result.errorCode(),
                null,
                result.blocks() == null ? List.of() : result.blocks().stream()
                        .map(block -> new RecordBlockRequest(
                                block.order(),
                                block.text(),
                                block.confidence() == null ? null : BigDecimal.valueOf(block.confidence()),
                                block.boundingBox()))
                        .toList());
    }

    private RecordPageRequest copyPageRequest(RecordPageResponse page, int fallbackIndex) {
        return new RecordPageRequest(
                page.pageIndex() == null ? fallbackIndex : page.pageIndex(),
                page.pageNumber() == null ? fallbackIndex + 1 : page.pageNumber(),
                page.status(),
                page.rawText(),
                page.editedText(),
                page.durationMs(),
                page.confidence(),
                page.errorCode(),
                page.failureReason(),
                page.blocks() == null ? List.of() : page.blocks().stream()
                        .map(this::toRecordBlockRequest)
                        .toList());
    }

    private RecordBlockRequest toRecordBlockRequest(RecordBlockResponse block) {
        return new RecordBlockRequest(
                block.blockIndex(),
                block.text(),
                block.confidence(),
                block.boundingBox());
    }

    private String aggregatePageText(List<RecordPageRequest> pages, boolean edited) {
        List<String> texts = new ArrayList<>();
        for (RecordPageRequest page : pages) {
            if (!"SUCCESS".equals(page.status())) {
                continue;
            }
            String text = edited
                    ? firstNonBlank(page.editedText(), page.rawText())
                    : firstNonBlank(page.rawText(), page.editedText());
            if (text.isBlank()) {
                continue;
            }
            texts.add("第 " + aggregatePageNumber(page) + " 张\n" + text.trim());
        }
        return String.join("\n\n", texts);
    }

    private int aggregatePageNumber(RecordPageRequest page) {
        if (page.pageNumber() != null) {
            return page.pageNumber();
        }
        return page.pageIndex() == null ? 1 : page.pageIndex() + 1;
    }

    private String aggregateLanguage(MutableBatchJob job, RecordResponse existingRecord) {
        for (MutableBatchItem item : job.items) {
            if (item.result != null && item.result.language() != null && !item.result.language().isBlank()) {
                return item.result.language();
            }
        }
        return existingRecord == null ? null : existingRecord.language();
    }

    private String aggregateEngine(MutableBatchJob job, RecordResponse existingRecord) {
        for (MutableBatchItem item : job.items) {
            if (item.result != null && item.result.ocrEngine() != null && !item.result.ocrEngine().isBlank()) {
                return item.result.ocrEngine();
            }
        }
        return existingRecord == null ? null : existingRecord.ocrEngine();
    }

    private int aggregateDurationMs(List<RecordPageRequest> pages) {
        long durationMs = 0;
        for (RecordPageRequest page : pages) {
            if (page.durationMs() != null && page.durationMs() > 0) {
                durationMs += page.durationMs();
            }
        }
        return Math.toIntExact(Math.min(durationMs, Integer.MAX_VALUE));
    }

    private String firstNonBlank(String preferred, String fallback) {
        if (preferred != null && !preferred.isBlank()) {
            return preferred;
        }
        return fallback == null ? "" : fallback;
    }

    private MutableBatchJob ownedJob(Long userId, String jobId) {
        List<MutableBatchJob> jobs = jdbcTemplate.query("""
                        SELECT job_id, user_id, status, progress, record_id, created_at
                        FROM batch_ocr_jobs
                        WHERE job_id = ? AND user_id = ?
                        """, BATCH_JOB_ROW_MAPPER, jobId, userId);
        if (jobs.isEmpty()) {
            throw new BusinessException(ErrorCode.NOT_FOUND);
        }
        MutableBatchJob job = jobs.getFirst();
        loadItems(job);
        consolidateLegacyItemRecordsIfNeeded(job);
        return job;
    }

    private void saveJob(MutableBatchJob job) {
        jdbcTemplate.update("""
                INSERT INTO batch_ocr_jobs (job_id, user_id, status, progress, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                job.jobId,
                job.userId,
                job.status.name(),
                job.progress,
                java.sql.Timestamp.from(job.createdAt),
                java.sql.Timestamp.from(job.createdAt));
    }

    private void saveItem(String jobId, MutableBatchItem item) {
        jdbcTemplate.update("""
                INSERT INTO batch_ocr_items
                    (job_id, item_index, file_name, status, record_id, error_code, failure_reason, retry_count, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
                """,
                jobId,
                item.itemIndex,
                item.fileName,
                item.status.name(),
                item.recordId,
                item.errorCode,
                item.failureReason,
                item.retryCount);
    }

    /**
     * 更新批量 OCR item 的脱敏状态。
     * 参数 item 不保存原始图片 bytes 或 OCR 全文，只保存可审计的状态、记录 ID 和错误摘要。
     */
    private void updateItem(String jobId, MutableBatchItem item) {
        jdbcTemplate.update("""
                UPDATE batch_ocr_items
                SET file_name = ?, status = ?, record_id = ?, error_code = ?, failure_reason = ?, retry_count = ?, updated_at = CURRENT_TIMESTAMP
                WHERE job_id = ? AND item_index = ?
                """,
                item.fileName,
                item.status.name(),
                item.recordId,
                item.errorCode,
                item.failureReason,
                item.retryCount,
                jobId,
                item.itemIndex);
    }

    private void markJob(MutableBatchJob job, BatchJobStatus status) {
        job.status = status;
        jdbcTemplate.update("""
                UPDATE batch_ocr_jobs
                SET status = ?, progress = ?, record_id = ?, updated_at = CURRENT_TIMESTAMP
                WHERE job_id = ?
                """,
                job.status.name(),
                job.progress,
                job.recordId,
                job.jobId);
    }

    private void updateJobRecordId(MutableBatchJob job) {
        jdbcTemplate.update("""
                UPDATE batch_ocr_jobs
                SET record_id = ?, updated_at = CURRENT_TIMESTAMP
                WHERE job_id = ? AND user_id = ?
                """,
                job.recordId,
                job.jobId,
                job.userId);
    }

    /**
     * 根据持久化 item 状态刷新 job 聚合状态。
     * 安全注意：progress 只统计成功项比例，不读取或记录 OCR 全文。
     */
    private void refreshJobState(MutableBatchJob job) {
        refreshJobState(job, true);
    }

    private void refreshJobState(MutableBatchJob job, boolean reloadItems) {
        if (reloadItems) {
            loadItems(job);
        }
        int completed = 0;
        int failed = 0;
        for (MutableBatchItem item : job.items) {
            if (item.status == BatchOcrItemStatus.SUCCESS) {
                completed++;
            } else if (item.status == BatchOcrItemStatus.FAILED) {
                failed++;
            }
        }
        int total = job.items.size();
        job.progress = calculateProgress(total, completed);
        if (failed > 0) {
            job.status = BatchJobStatus.FAILED;
        } else if (total > 0 && completed == total) {
            job.status = BatchJobStatus.SUCCESS;
        } else {
            job.status = BatchJobStatus.RUNNING;
        }
        jdbcTemplate.update("""
                UPDATE batch_ocr_jobs
                SET status = ?, progress = ?, record_id = ?, updated_at = CURRENT_TIMESTAMP
                WHERE job_id = ?
                """,
                job.status.name(),
                job.progress,
                job.recordId,
                job.jobId);
    }

    private void loadItems(MutableBatchJob job) {
        job.items.clear();
        job.items.addAll(jdbcTemplate.query("""
                        SELECT item_index, file_name, status, record_id, error_code, failure_reason, retry_count
                        FROM batch_ocr_items
                        WHERE job_id = ?
                        ORDER BY item_index ASC
                        """, BATCH_ITEM_ROW_MAPPER, job.jobId));
    }

    private BatchOcrJobResponse toResponse(MutableBatchJob job) {
        int completed = 0;
        int failed = 0;
        List<BatchOcrItemResponse> responses = new ArrayList<>();
        for (MutableBatchItem item : job.items) {
            if (item.status == BatchOcrItemStatus.SUCCESS) {
                completed++;
            } else if (item.status == BatchOcrItemStatus.FAILED) {
                failed++;
            }
            responses.add(new BatchOcrItemResponse(
                    item.itemIndex,
                    item.fileName,
                    item.status,
                    item.result,
                    item.recordId,
                    item.errorCode,
                    item.failureReason));
        }
        int total = job.items.size();
        int progress = calculateProgress(total, completed);
        return new BatchOcrJobResponse(job.jobId, job.status.name(), job.recordId, total, completed, failed, progress, responses);
    }

    private int calculateProgress(int total, int completed) {
        return total == 0 ? 0 : (int) Math.round((completed * 100.0) / total);
    }

    private BatchOcrTaskSummaryResponse toSummaryResponse(MutableBatchJob job) {
        BatchOcrJobResponse response = toResponse(job);
        List<BatchOcrTaskItemSummaryResponse> items = job.items.stream()
                .map(item -> new BatchOcrTaskItemSummaryResponse(
                        item.itemIndex,
                        item.fileName,
                        item.status,
                        item.recordId,
                        item.errorCode,
                        item.failureReason))
                .toList();
        return new BatchOcrTaskSummaryResponse(
                response.jobId(),
                response.status(),
                response.recordId(),
                response.total(),
                response.completed(),
                response.failed(),
                response.progress(),
                job.createdAt,
                items);
    }

    private String safeFileName(MultipartFile file) {
        if (file == null || file.getOriginalFilename() == null || file.getOriginalFilename().isBlank()) {
            return "image";
        }
        return file.getOriginalFilename().replaceAll("[\\r\\n\"\\\\/]+", "_");
    }

    private String safeFailureReason(String message) {
        if (message == null || message.isBlank()) {
            return "OCR item failed";
        }
        String singleLine = message.replaceAll("[\\r\\n]+", " ").trim();
        return singleLine.length() > 120 ? singleLine.substring(0, 120) : singleLine;
    }

    private static final class MutableBatchJob {
        private final String jobId;
        private final Long userId;
        private BatchJobStatus status;
        private int progress;
        private Long recordId;
        private final Instant createdAt;
        private final List<MutableBatchItem> items = new ArrayList<>();

        private MutableBatchJob(String jobId, Long userId, BatchJobStatus status, int progress, Long recordId, Instant createdAt) {
            this.jobId = jobId;
            this.userId = userId;
            this.status = status;
            this.progress = progress;
            this.recordId = recordId;
            this.createdAt = createdAt;
        }
    }

    private static final class MutableBatchItem {
        private final int itemIndex;
        private String fileName;
        private BatchOcrItemStatus status;
        private OcrRecognizeResponse result;
        private Long recordId;
        private String errorCode;
        private String failureReason;
        private int retryCount;

        private MutableBatchItem(int itemIndex, String fileName, BatchOcrItemStatus status) {
            this.itemIndex = itemIndex;
            this.fileName = fileName;
            this.status = status;
        }

        private MutableBatchItem(
                int itemIndex,
                String fileName,
                BatchOcrItemStatus status,
                Long recordId,
                String errorCode,
                String failureReason,
                int retryCount) {
            this.itemIndex = itemIndex;
            this.fileName = fileName;
            this.status = status;
            this.recordId = recordId;
            this.errorCode = errorCode;
            this.failureReason = failureReason;
            this.retryCount = retryCount;
        }

        private static MutableBatchItem queued(int itemIndex, String fileName) {
            return new MutableBatchItem(itemIndex, fileName, BatchOcrItemStatus.QUEUED);
        }
    }

    private enum BatchJobStatus {
        QUEUED,
        RUNNING,
        RETRYING,
        CANCELED,
        SUCCESS,
        FAILED
    }
}
