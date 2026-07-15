package com.harmonyocr.export.service;

import com.harmonyocr.common.error.BusinessException;
import com.harmonyocr.common.error.ErrorCode;
import com.harmonyocr.export.dto.CreateExportRequest;
import com.harmonyocr.export.dto.CreatePdfExportRequest;
import com.harmonyocr.export.dto.ExportDownload;
import com.harmonyocr.export.dto.ExportFormat;
import com.harmonyocr.export.dto.ExportJobResponse;
import com.harmonyocr.export.dto.ExportJobStatusEventResponse;
import com.harmonyocr.export.dto.ExportStatus;
import com.harmonyocr.membership.service.MembershipService;
import com.harmonyocr.record.dto.RecordPageResponse;
import com.harmonyocr.record.dto.RecordResponse;
import com.harmonyocr.record.service.RecordService;
import java.io.ByteArrayOutputStream;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.text.Normalizer;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Service;

/**
 * 文档导出服务，属于 export 模块。
 * 维护说明：V2.0-4 提供低风险 PDF/export schema、任务状态和可抽取文本层，任务元数据和内容持久化到本地数据库；不引入 OCRmyPDF、模型或对象存储写入。
 */
@Service
public class ExportService {

    private static final String PDF_CONTENT_TYPE = "application/pdf";
    private static final int MAX_RECORDS_PER_EXPORT = 50;
    private static final int PDF_MAX_TEXT_LINES_PER_PAGE = 45;
    private static final RowMapper<MutableExportJob> EXPORT_JOB_ROW_MAPPER = (rs, rowNum) -> new MutableExportJob(
            rs.getString("job_id"),
            rs.getLong("user_id"),
            ExportStatus.valueOf(rs.getString("status")),
            ExportFormat.valueOf(rs.getString("format")),
            rs.getString("file_name"),
            rs.getString("content_type"),
            rs.getInt("progress"),
            rs.getString("checksum_sha256"),
            rs.getBoolean("searchable"),
            rs.getBoolean("degraded"),
            rs.getString("downgrade_reason"),
            rs.getTimestamp("created_at").toInstant(),
            rs.getBytes("content"));

    private final RecordService recordService;
    private final MembershipService membershipService;
    private final JdbcTemplate jdbcTemplate;

    public ExportService(RecordService recordService, MembershipService membershipService, JdbcTemplate jdbcTemplate) {
        this.recordService = recordService;
        this.membershipService = membershipService;
        this.jdbcTemplate = jdbcTemplate;
    }

    /**
     * 创建通用导出任务。
     * 参数 userId 来自认证上下文，request.format 决定文件格式；返回任务元数据，不返回文件 bytes。
     */
    public ExportJobResponse create(Long userId, CreateExportRequest request) {
        List<Long> recordIds = validateRecordIds(request.recordIds());
        ExportFormat format = request.format();
        membershipService.consume(userId, "EXPORT");
        List<RecordResponse> records = recordIds.stream()
                .map(recordId -> recordService.detail(userId, recordId))
                .toList();
        MutableExportJob job = buildExportJob(userId, records, format, request.fileName());
        saveJob(job);
        markJob(job, ExportStatus.RUNNING, 10);
        markJob(job, ExportStatus.SUCCESS, 100);
        return toResponse(ownedJob(userId, job.jobId));
    }

    /**
     * 创建 PDF 导出任务。
     * 参数 userId 来自认证上下文，request.recordIds 必须全部属于当前用户；返回任务状态与下载入口。
     */
    public ExportJobResponse createPdf(Long userId, CreatePdfExportRequest request) {
        ExportFormat format = request.searchable() ? ExportFormat.SEARCHABLE_PDF : ExportFormat.PDF;
        return create(userId, new CreateExportRequest(request.recordIds(), format, request.fileName()));
    }

    /**
     * 查询当前用户的导出任务摘要。
     * 参数 userId 来自认证上下文；返回值按创建时间倒序排列，不返回文件 bytes。
     */
    public List<ExportJobResponse> listOwned(Long userId) {
        return jdbcTemplate.query("""
                        SELECT job_id, user_id, status, format, file_name, content_type, size_bytes,
                               progress, checksum_sha256, searchable, degraded, downgrade_reason, content, created_at
                        FROM export_jobs
                        WHERE user_id = ?
                        ORDER BY created_at DESC
                        """, EXPORT_JOB_ROW_MAPPER, userId)
                .stream()
                .map(this::toResponse)
                .toList();
    }

    /**
     * 查询当前用户拥有的导出任务摘要。
     * 参数 jobId 必须属于当前用户；越权和不存在统一返回 NOT_FOUND。
     */
    public ExportJobResponse detailOwned(Long userId, String jobId) {
        return toResponse(ownedJob(userId, jobId));
    }

    /**
     * 取消当前用户拥有的非终态导出任务。
     * 参数 jobId 必须属于当前用户；只更新任务状态和进度，不删除内容、不暴露路径或 objectKey。
     */
    public ExportJobResponse cancel(Long userId, String jobId) {
        MutableExportJob job = ownedJob(userId, jobId);
        if (job.status == ExportStatus.SUCCESS || job.status == ExportStatus.FAILED || job.status == ExportStatus.CANCELED) {
            throw new BusinessException(ErrorCode.VALIDATION_ERROR, "only pending or running export can be canceled");
        }
        jdbcTemplate.update("""
                UPDATE export_jobs
                SET status = 'CANCELED'
                WHERE job_id = ? AND user_id = ?
                """, jobId, userId);
        appendStatusEvent(jobId, ExportStatus.CANCELED, job.progress);
        return toResponse(ownedJob(userId, jobId));
    }

    /**
     * 下载当前用户拥有的导出任务文件。
     * 参数 jobId 必须属于当前用户；返回内存文件对象。不存在、失败或越权时统一按 NOT_FOUND 处理。
     */
    public ExportDownload download(Long userId, String jobId) {
        MutableExportJob job = ownedJob(userId, jobId);
        if (job.status != ExportStatus.SUCCESS || job.content == null) {
            throw new BusinessException(ErrorCode.NOT_FOUND);
        }
        return new ExportDownload(job.fileName, job.contentType, job.content.clone());
    }

    private MutableExportJob ownedJob(Long userId, String jobId) {
        List<MutableExportJob> rows = jdbcTemplate.query("""
                        SELECT job_id, user_id, status, format, file_name, content_type, size_bytes,
                               progress, checksum_sha256, searchable, degraded, downgrade_reason, content, created_at
                        FROM export_jobs
                        WHERE job_id = ? AND user_id = ?
                        """, EXPORT_JOB_ROW_MAPPER, jobId, userId);
        if (rows.isEmpty()) {
            throw new BusinessException(ErrorCode.NOT_FOUND);
        }
        return rows.getFirst();
    }

    /**
     * 持久化导出任务。
     * 参数 job 只包含导出文件 bytes 与脱敏元数据；不写对象存储 key、完整媒体 URI 或额外 OCR 日志。
     */
    private void saveJob(MutableExportJob job) {
        jdbcTemplate.update("""
                INSERT INTO export_jobs
                    (job_id, user_id, status, format, file_name, content_type, size_bytes,
                     progress, checksum_sha256, searchable, degraded, downgrade_reason, content, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                job.jobId,
                job.userId,
                job.status.name(),
                job.format.name(),
                job.fileName,
                job.contentType,
                job.content == null ? 0 : job.content.length,
                job.progress,
                job.checksumSha256,
                job.searchable,
                job.degraded,
                job.downgradeReason,
                job.content,
                java.sql.Timestamp.from(job.createdAt));
        appendStatusEvent(job.jobId, job.status, job.progress);
    }

    private void markJob(MutableExportJob job, ExportStatus status, int progress) {
        jdbcTemplate.update("""
                UPDATE export_jobs
                SET status = ?, progress = ?
                WHERE job_id = ? AND user_id = ?
                """, status.name(), progress, job.jobId, job.userId);
        appendStatusEvent(job.jobId, status, progress);
    }

    private List<Long> validateRecordIds(List<Long> recordIds) {
        if (recordIds == null || recordIds.isEmpty()) {
            throw new BusinessException(ErrorCode.VALIDATION_ERROR, "recordIds must not be empty");
        }
        if (recordIds.size() > MAX_RECORDS_PER_EXPORT) {
            throw new BusinessException(ErrorCode.VALIDATION_ERROR, "recordIds exceeds export limit");
        }
        if (recordIds.stream().anyMatch(id -> id == null || id <= 0)) {
            throw new BusinessException(ErrorCode.VALIDATION_ERROR, "recordIds contains invalid id");
        }
        return List.copyOf(recordIds);
    }

    private ExportJobResponse toResponse(MutableExportJob job) {
        return new ExportJobResponse(
                job.jobId,
                job.status,
                job.format,
                job.fileName,
                job.contentType,
                job.content == null ? 0 : job.content.length,
                job.progress,
                job.checksumSha256,
                job.searchable,
                job.degraded,
                job.downgradeReason,
                job.status == ExportStatus.SUCCESS ? "/api/v1/exports/" + job.jobId + "/download" : null,
                job.createdAt,
                statusHistory(job.jobId));
    }

    private MutableExportJob buildExportJob(Long userId, List<RecordResponse> records, ExportFormat format, String requestedName) {
        String fileName = safeFileName(requestedName, extension(format));
        String contentType = contentType(format);
        byte[] content = switch (format) {
            case TXT -> buildTxt(records);
            case MARKDOWN -> buildMarkdown(records);
            case JSON -> buildJson(records);
            case PDF, SEARCHABLE_PDF -> buildTextLayerPdf(records);
        };
        return new MutableExportJob(
                UUID.randomUUID().toString(),
                userId,
                ExportStatus.PENDING,
                format,
                fileName,
                contentType,
                0,
                sha256(content),
                format == ExportFormat.SEARCHABLE_PDF,
                false,
                null,
                Instant.now(),
                content);
    }

    /**
     * 写入导出任务的脱敏生命周期事件。
     * 参数 jobId 只对应本地任务编号，事件不携带文件 bytes、对象存储 key、媒体 URI 或 OCR 全文。
     */
    private void appendStatusEvent(String jobId, ExportStatus status, int progress) {
        jdbcTemplate.update("""
                INSERT INTO export_job_status_events (job_id, status, progress, created_at)
                VALUES (?, ?, ?, CURRENT_TIMESTAMP)
                """, jobId, status.name(), progress);
    }

    private List<ExportJobStatusEventResponse> statusHistory(String jobId) {
        return jdbcTemplate.query("""
                        SELECT status, progress, created_at
                        FROM export_job_status_events
                        WHERE job_id = ?
                        ORDER BY id ASC
                        """,
                (rs, rowNum) -> new ExportJobStatusEventResponse(
                        ExportStatus.valueOf(rs.getString("status")),
                        rs.getInt("progress"),
                        rs.getTimestamp("created_at").toInstant()),
                jobId);
    }

    private String safeFileName(String requestedName, String extension) {
        String fallback = "harmony-ocr-export." + extension;
        String candidate = requestedName == null || requestedName.isBlank() ? fallback : requestedName;
        candidate = candidate.replace('\\', '/');
        int slash = candidate.lastIndexOf('/');
        if (slash >= 0) {
            candidate = candidate.substring(slash + 1);
        }
        candidate = Normalizer.normalize(candidate.trim(), Normalizer.Form.NFKC)
                .replaceAll("[\\r\\n]+", "_")
                .replaceAll("[^\\p{IsAlphabetic}\\p{IsDigit}._-]+", "_")
                .replaceAll("_+", "_")
                .replaceAll("(?i)_*\\.(txt|md|json|pdf)_*$", "." + extension)
                .replaceAll("_+(?=\\.[A-Za-z0-9]+$)", "")
                .replaceAll("^[._-]+", "")
                .replaceAll("[._-]+$", "")
                .trim();
        if (candidate.isBlank()) {
            candidate = "harmony-ocr-export";
        }
        String suffix = "." + extension;
        if (!candidate.toLowerCase(Locale.ROOT).endsWith(suffix)) {
            candidate = candidate + suffix;
        }
        if (candidate.length() > 120) {
            candidate = candidate.substring(0, 119 - extension.length()) + suffix;
        }
        return candidate;
    }

    private String extension(ExportFormat format) {
        return switch (format) {
            case TXT -> "txt";
            case MARKDOWN -> "md";
            case JSON -> "json";
            case PDF, SEARCHABLE_PDF -> "pdf";
        };
    }

    private String contentType(ExportFormat format) {
        return switch (format) {
            case TXT -> "text/plain; charset=utf-8";
            case MARKDOWN -> "text/markdown; charset=utf-8";
            case JSON -> "application/json; charset=utf-8";
            case PDF, SEARCHABLE_PDF -> PDF_CONTENT_TYPE;
        };
    }

    private byte[] buildTxt(List<RecordResponse> records) {
        StringBuilder builder = new StringBuilder();
        for (RecordResponse record : records) {
            builder.append(blankToDefault(record.title(), "Untitled")).append(System.lineSeparator());
            builder.append(blankToDefault(record.editedText(), record.rawText())).append(System.lineSeparator());
        }
        return builder.toString().getBytes(StandardCharsets.UTF_8);
    }

    private byte[] buildMarkdown(List<RecordResponse> records) {
        StringBuilder builder = new StringBuilder();
        for (RecordResponse record : records) {
            builder.append("# ").append(blankToDefault(record.title(), "Untitled")).append(System.lineSeparator()).append(System.lineSeparator());
            builder.append(blankToDefault(record.editedText(), record.rawText())).append(System.lineSeparator()).append(System.lineSeparator());
        }
        return builder.toString().getBytes(StandardCharsets.UTF_8);
    }

    /**
     * 生成脱敏 JSON 导出。
     * 参数 records 已完成归属校验；输出只包含文本摘要和元数据，不包含对象存储 key、完整媒体 URI 或本地路径。
     */
    private byte[] buildJson(List<RecordResponse> records) {
        StringBuilder builder = new StringBuilder();
        builder.append("{\"records\":[");
        for (int index = 0; index < records.size(); index++) {
            if (index > 0) {
                builder.append(',');
            }
            RecordResponse record = records.get(index);
            String text = blankToDefault(record.editedText(), record.rawText());
            builder.append("{\"recordId\":").append(record.id())
                    .append(",\"title\":\"").append(jsonEscape(blankToDefault(record.title(), "Untitled"))).append('"')
                    .append(",\"engine\":\"").append(jsonEscape(blankToDefault(record.ocrEngine(), ""))).append('"')
                    .append(",\"language\":\"").append(jsonEscape(blankToDefault(record.language(), ""))).append('"')
                    .append(",\"confidence\":null")
                    .append(",\"textSummary\":\"").append(jsonEscape(summary(text))).append('"')
                    .append(",\"blocks\":[]}");
        }
        builder.append("]}");
        return builder.toString().getBytes(StandardCharsets.UTF_8);
    }

    private String summary(String value) {
        String normalized = blankToDefault(value, "").replaceAll("\\s+", " ").trim();
        return normalized.length() <= 80 ? normalized : normalized.substring(0, 80);
    }

    private String jsonEscape(String value) {
        return blankToDefault(value, "")
                .replace("\\", "\\\\")
                .replace("\"", "\\\"")
                .replace("\r", "\\r")
                .replace("\n", "\\n");
    }

    /**
     * 生成包含可抽取文本层的简易 PDF。
     * 参数 records 已完成归属校验；返回 PDF bytes，不写磁盘、不写日志，并把 OCR 文本放入标准 PDF text operator 中。
     */
    private byte[] buildTextLayerPdf(List<RecordResponse> records) {
        List<PdfExportPage> pages = buildPdfExportPages(records);
        Map<Integer, String> objects = new LinkedHashMap<>();
        int fontObjectId = 3;
        int nextObjectId = 4;
        List<Integer> pageObjectIds = new ArrayList<>();
        Map<Integer, String> pageObjects = new LinkedHashMap<>();
        for (PdfExportPage page : pages) {
            int pageObjectId = nextObjectId++;
            int contentObjectId = nextObjectId++;
            pageObjectIds.add(pageObjectId);
            String stream = buildPdfTextStream(page.lines);
            byte[] streamBytes = stream.getBytes(StandardCharsets.UTF_8);
            pageObjects.put(pageObjectId, "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Contents "
                    + contentObjectId
                    + " 0 R /Resources << /Font << /F1 "
                    + fontObjectId
                    + " 0 R >> >> >>");
            pageObjects.put(contentObjectId, "<< /Length " + streamBytes.length + " >>\nstream\n" + stream + "\nendstream");
        }
        objects.put(1, "<< /Type /Catalog /Pages 2 0 R >>");
        objects.put(2, "<< /Type /Pages /Kids [" + pdfPageKids(pageObjectIds) + "] /Count " + pages.size() + " >>");
        objects.put(fontObjectId, "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>");
        objects.putAll(pageObjects);
        return writePdf(objects);
    }

    /**
     * 将历史记录转换为 PDF 逻辑页。
     * 设计边界：批量 OCR/PDF OCR 的页级历史按原页导出；普通记录按一条记录一页导出，不暴露对象 key 或本地路径。
     */
    private List<PdfExportPage> buildPdfExportPages(List<RecordResponse> records) {
        List<PdfExportPage> exportPages = new ArrayList<>();
        for (RecordResponse record : records) {
            List<RecordPageResponse> recordPages = sortedRecordPages(record);
            if (recordPages.isEmpty()) {
                addPdfExportPageChunks(
                        exportPages,
                        recordTitle(record),
                        splitSearchableLines(blankToDefault(record.editedText(), record.rawText())));
                continue;
            }
            for (RecordPageResponse page : recordPages) {
                addPdfExportPageChunks(
                        exportPages,
                        recordPageTitle(record, page),
                        splitSearchableLines(recordPageText(page)));
            }
        }
        if (exportPages.isEmpty()) {
            addPdfExportPageChunks(exportPages, "Harmony OCR Export", List.of(""));
        }
        return exportPages;
    }

    private List<RecordPageResponse> sortedRecordPages(RecordResponse record) {
        if (record.pages() == null || record.pages().isEmpty()) {
            return List.of();
        }
        List<RecordPageResponse> pages = new ArrayList<>(record.pages());
        pages.sort(Comparator
                .comparing((RecordPageResponse page) -> page.pageIndex() == null ? Integer.MAX_VALUE : page.pageIndex())
                .thenComparing(page -> page.pageNumber() == null ? Integer.MAX_VALUE : page.pageNumber()));
        return pages;
    }

    private String recordTitle(RecordResponse record) {
        return "Record #" + record.id() + " " + blankToDefault(record.title(), "Untitled");
    }

    private String recordPageTitle(RecordResponse record, RecordPageResponse page) {
        String unit = "pdf".equals(record.sourceType()) ? "Page" : "Image";
        int number = page.pageNumber() == null ? page.pageIndex() == null ? 1 : page.pageIndex() + 1 : page.pageNumber();
        return recordTitle(record) + " - " + unit + " " + number;
    }

    private String recordPageText(RecordPageResponse page) {
        String text = blankToDefault(page.editedText(), page.rawText());
        if (!text.isBlank()) {
            return text;
        }
        if ("FAILED".equals(page.status())) {
            return blankToDefault(page.failureReason(), blankToDefault(page.errorCode(), ""));
        }
        return "";
    }

    private void addPdfExportPageChunks(List<PdfExportPage> exportPages, String title, List<String> bodyLines) {
        List<String> normalizedBodyLines = bodyLines == null || bodyLines.isEmpty() ? List.of("") : bodyLines;
        int offset = 0;
        int chunkIndex = 0;
        while (offset < normalizedBodyLines.size()) {
            int nextOffset = Math.min(offset + PDF_MAX_TEXT_LINES_PER_PAGE - 2, normalizedBodyLines.size());
            List<String> pageLines = new ArrayList<>();
            pageLines.add("Harmony OCR Export");
            pageLines.add(chunkIndex == 0 ? title : title + " (continued)");
            pageLines.addAll(normalizedBodyLines.subList(offset, nextOffset));
            exportPages.add(new PdfExportPage(pageLines));
            offset = nextOffset;
            chunkIndex++;
        }
    }

    private String pdfPageKids(List<Integer> pageObjectIds) {
        List<String> refs = new ArrayList<>();
        for (Integer pageObjectId : pageObjectIds) {
            refs.add(pageObjectId + " 0 R");
        }
        return String.join(" ", refs);
    }

    private String buildPdfTextStream(List<String> lines) {
        List<String> operators = new ArrayList<>();
        operators.add("BT");
        operators.add("/F1 12 Tf");
        operators.add("50 790 Td");
        for (int index = 0; index < lines.size(); index++) {
            if (index > 0) {
                operators.add("0 -16 Td");
            }
            operators.add(pdfUnicodeHexText(lines.get(index)) + " Tj");
        }
        operators.add("ET");
        return String.join("\n", operators);
    }

    private byte[] writePdf(Map<Integer, String> objects) {
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        writeAscii(output, "%PDF-1.4\n");
        List<Integer> offsets = new ArrayList<>();
        offsets.add(0);
        for (Map.Entry<Integer, String> object : objects.entrySet()) {
            offsets.add(output.size());
            writeAscii(output, object.getKey() + " 0 obj\n");
            writeAscii(output, object.getValue());
            writeAscii(output, "\nendobj\n");
        }
        int xrefOffset = output.size();
        writeAscii(output, "xref\n0 " + (objects.size() + 1) + "\n");
        writeAscii(output, "0000000000 65535 f \n");
        for (int index = 1; index < offsets.size(); index++) {
            writeAscii(output, "%010d 00000 n \n".formatted(offsets.get(index)));
        }
        writeAscii(output, "trailer\n<< /Size " + (objects.size() + 1) + " /Root 1 0 R >>\n");
        writeAscii(output, "startxref\n" + xrefOffset + "\n%%EOF\n");
        return output.toByteArray();
    }

    private void writeAscii(ByteArrayOutputStream output, String value) {
        output.writeBytes(value.getBytes(StandardCharsets.UTF_8));
    }

    /**
     * 计算导出文件 SHA-256。
     * 参数 content 为已生成的导出 bytes；返回值只用于完整性校验，不包含原始 OCR 文本或路径信息。
     */
    private String sha256(byte[] content) {
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256").digest(content == null ? new byte[0] : content);
            StringBuilder builder = new StringBuilder();
            for (byte value : digest) {
                builder.append("%02x".formatted(value & 0xFF));
            }
            return builder.toString();
        } catch (NoSuchAlgorithmException exception) {
            throw new IllegalStateException("SHA-256 digest unavailable", exception);
        }
    }

    /**
     * 将 OCR 文本按原始换行拆成 PDF 文本行。
     * 参数 value 为记录文本；返回值保留空文本占位，避免空 OCR 记录导致导出结构缺行。
     */
    private List<String> splitSearchableLines(String value) {
        String text = blankToDefault(value, "");
        if (text.isEmpty()) {
            return List.of("");
        }
        return Arrays.asList(text.split("\\R", -1));
    }

    /**
     * 将文本编码为 PDF Unicode hex string。
     * 参数 value 为单行文本；返回带 UTF-16BE BOM 的十六进制字面量，使中文和英文都进入可抽取文本层。
     */
    private String pdfUnicodeHexText(String value) {
        byte[] textBytes = blankToDefault(value, "").getBytes(StandardCharsets.UTF_16BE);
        StringBuilder hex = new StringBuilder("<FEFF");
        for (byte textByte : textBytes) {
            hex.append("%02X".formatted(textByte & 0xFF));
        }
        return hex.append(">").toString();
    }

    private String blankToDefault(String value, String defaultValue) {
        if (value == null || value.isBlank()) {
            return defaultValue == null ? "" : defaultValue;
        }
        return value;
    }

    private record PdfExportPage(List<String> lines) {
    }

    private static final class MutableExportJob {
        private final String jobId;
        private final Long userId;
        private final ExportStatus status;
        private final ExportFormat format;
        private final String fileName;
        private final String contentType;
        private final int progress;
        private final String checksumSha256;
        private final boolean searchable;
        private final boolean degraded;
        private final String downgradeReason;
        private final Instant createdAt;
        private final byte[] content;

        private MutableExportJob(
                String jobId,
                Long userId,
                ExportStatus status,
                ExportFormat format,
                String fileName,
                String contentType,
                int progress,
                String checksumSha256,
                boolean searchable,
                boolean degraded,
                String downgradeReason,
                Instant createdAt,
                byte[] content) {
            this.jobId = jobId;
            this.userId = userId;
            this.status = status;
            this.format = format;
            this.fileName = fileName;
            this.contentType = contentType;
            this.progress = progress;
            this.checksumSha256 = checksumSha256;
            this.searchable = searchable;
            this.degraded = degraded;
            this.downgradeReason = downgradeReason;
            this.createdAt = createdAt;
            this.content = content == null ? null : content.clone();
        }
    }
}
