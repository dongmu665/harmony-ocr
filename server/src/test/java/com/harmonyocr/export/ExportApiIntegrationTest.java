package com.harmonyocr.export;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.io.ByteArrayOutputStream;
import java.nio.charset.Charset;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.apache.pdfbox.Loader;
import org.apache.pdfbox.pdmodel.PDDocument;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@ActiveProfiles("test")
@AutoConfigureMockMvc
@SpringBootTest
/**
 * 导出 API 集成测试。
 * 维护说明：验证当前用户只能导出自己拥有的 OCR 记录，并检查导出任务状态、下载和脱敏元数据契约。
 */
class ExportApiIntegrationTest {

    private static final Charset UTF_16BE = StandardCharsets.UTF_16BE;
    private static final Pattern UNICODE_TEXT_OPERATOR = Pattern.compile("<([0-9A-Fa-f]+)>\\s*Tj");

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    @Autowired
    private JdbcTemplate jdbcTemplate;

    @BeforeEach
    void cleanDatabase() {
        jdbcTemplate.update("DELETE FROM export_jobs");
        jdbcTemplate.update("DELETE FROM object_storage_cleanup_tasks");
        jdbcTemplate.update("DELETE FROM file_objects");
        jdbcTemplate.update("DELETE FROM recognition_record_tags");
        jdbcTemplate.update("DELETE FROM recognition_tags");
        jdbcTemplate.update("DELETE FROM recognition_blocks");
        jdbcTemplate.update("DELETE FROM recognition_records");
        jdbcTemplate.update("DELETE FROM refresh_tokens");
        jdbcTemplate.update("DELETE FROM user_devices");
        jdbcTemplate.update("DELETE FROM batch_ocr_items");
        jdbcTemplate.update("DELETE FROM batch_ocr_jobs");
        jdbcTemplate.update("DELETE FROM users");
    }

    @Test
    void createPdfExportUsesSafeFilenameAndAuthenticatedDownload() throws Exception {
        String password = testPassword();
        register("alice", password);
        Long recordId = insertRecord(userId("alice"), "Receipt", "camera", "raw sample text", "edited sample text");

        MvcResult result = mockMvc.perform(post("/api/v1/exports/pdf")
                        .header(HttpHeaders.AUTHORIZATION, bearer(accessToken("alice", password)))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of(
                                "recordIds", List.of(recordId),
                                "fileName", "../private:receipt?.pdf",
                                "searchable", false))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.status").value("SUCCESS"))
                .andExpect(jsonPath("$.data.format").value("PDF"))
                .andExpect(jsonPath("$.data.fileName").value("private_receipt.pdf"))
                .andExpect(jsonPath("$.data.contentType").value("application/pdf"))
                .andExpect(jsonPath("$.data.searchable").value(false))
                .andExpect(jsonPath("$.data.degraded").value(false))
                .andExpect(jsonPath("$.data.downloadPath").value(org.hamcrest.Matchers.startsWith("/api/v1/exports/")))
                .andReturn();

        String jobId = jsonNode(result).path("data").path("jobId").asText();
        MvcResult download = mockMvc.perform(get("/api/v1/exports/{jobId}/download", jobId)
                        .header(HttpHeaders.AUTHORIZATION, bearer(accessToken("alice", password))))
                .andExpect(status().isOk())
                .andExpect(header().string(HttpHeaders.CONTENT_TYPE, "application/pdf"))
                .andExpect(header().string(HttpHeaders.CONTENT_DISPOSITION, "attachment; filename=\"private_receipt.pdf\""))
                .andReturn();

        assertThat(download.getResponse().getContentAsByteArray()).startsWith("%PDF-1.4".getBytes(StandardCharsets.US_ASCII));
    }

    @Test
    void searchablePdfIncludesExtractableTextLayerAndOwnershipCheck() throws Exception {
        String alicePassword = testPassword();
        String bobPassword = testPassword();
        register("alice", alicePassword);
        register("bob", bobPassword);
        Long aliceRecord = insertRecord(userId("alice"), "Notice", "album", "notice raw searchable alpha", null);

        mockMvc.perform(post("/api/v1/exports/pdf")
                        .header(HttpHeaders.AUTHORIZATION, bearer(accessToken("bob", bobPassword)))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of(
                                "recordIds", List.of(aliceRecord),
                                "fileName", "bob.pdf",
                                "searchable", true))))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.code").value("NOT_FOUND"));

        MvcResult result = mockMvc.perform(post("/api/v1/exports/pdf")
                        .header(HttpHeaders.AUTHORIZATION, bearer(accessToken("alice", alicePassword)))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of(
                                "recordIds", List.of(aliceRecord),
                                "fileName", "searchable.pdf",
                                "searchable", true))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.status").value("SUCCESS"))
                .andExpect(jsonPath("$.data.format").value("SEARCHABLE_PDF"))
                .andExpect(jsonPath("$.data.searchable").value(true))
                .andExpect(jsonPath("$.data.degraded").value(false))
                .andExpect(jsonPath("$.data.downgradeReason").doesNotExist())
                .andReturn();

        String jobId = jsonNode(result).path("data").path("jobId").asText();
        MvcResult download = mockMvc.perform(get("/api/v1/exports/{jobId}/download", jobId)
                        .header(HttpHeaders.AUTHORIZATION, bearer(accessToken("alice", alicePassword))))
                .andExpect(status().isOk())
                .andExpect(header().string(HttpHeaders.CONTENT_TYPE, "application/pdf"))
                .andReturn();

        String pdfSyntax = new String(download.getResponse().getContentAsByteArray(), StandardCharsets.ISO_8859_1);
        assertThat(extractUnicodeTextLayer(pdfSyntax)).contains("notice raw searchable alpha");
    }

    @Test
    void pdfExportCreatesOnePdfPagePerBatchHistoryPage() throws Exception {
        String password = testPassword();
        register("batch-export", password);
        Long userId = userId("batch-export");
        Long batchRecord = insertRecord(
                userId,
                "批量 OCR",
                "batch",
                "first image aggregate text\n\nsecond image aggregate text",
                null);
        insertRecordPage(batchRecord, 0, 1, "SUCCESS", "first image raw text", "first image edited text", null, null);
        insertRecordPage(batchRecord, 1, 2, "SUCCESS", "second image raw text", "second image edited text", null, null);

        MvcResult result = mockMvc.perform(post("/api/v1/exports/pdf")
                        .header(HttpHeaders.AUTHORIZATION, bearer(accessToken("batch-export", password)))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of(
                                "recordIds", List.of(batchRecord),
                                "fileName", "batch-pages.pdf",
                                "searchable", true))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.status").value("SUCCESS"))
                .andExpect(jsonPath("$.data.format").value("SEARCHABLE_PDF"))
                .andReturn();

        String jobId = jsonNode(result).path("data").path("jobId").asText();
        MvcResult download = mockMvc.perform(get("/api/v1/exports/{jobId}/download", jobId)
                        .header(HttpHeaders.AUTHORIZATION, bearer(accessToken("batch-export", password))))
                .andExpect(status().isOk())
                .andExpect(header().string(HttpHeaders.CONTENT_TYPE, "application/pdf"))
                .andReturn();

        byte[] pdfBytes = download.getResponse().getContentAsByteArray();
        String pdfSyntax = new String(pdfBytes, StandardCharsets.ISO_8859_1);
        assertThat(pdfPageCount(pdfBytes)).isEqualTo(2);
        assertThat(pdfSyntax).contains("/Count 2");
        assertThat(extractUnicodeTextLayer(pdfSyntax))
                .contains("first image edited text")
                .contains("second image edited text");
    }

    @Test
    void pdfExportCreatesOnePdfPagePerSelectedRecord() throws Exception {
        String password = testPassword();
        register("multi-export", password);
        Long userId = userId("multi-export");
        Long firstRecord = insertRecord(userId, "First", "album", "first selected record text", null);
        Long secondRecord = insertRecord(userId, "Second", "camera", "second selected record text", null);

        MvcResult result = mockMvc.perform(post("/api/v1/exports/pdf")
                        .header(HttpHeaders.AUTHORIZATION, bearer(accessToken("multi-export", password)))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of(
                                "recordIds", List.of(firstRecord, secondRecord),
                                "fileName", "multi-record.pdf",
                                "searchable", false))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.status").value("SUCCESS"))
                .andExpect(jsonPath("$.data.format").value("PDF"))
                .andReturn();

        String jobId = jsonNode(result).path("data").path("jobId").asText();
        MvcResult download = mockMvc.perform(get("/api/v1/exports/{jobId}/download", jobId)
                        .header(HttpHeaders.AUTHORIZATION, bearer(accessToken("multi-export", password))))
                .andExpect(status().isOk())
                .andExpect(header().string(HttpHeaders.CONTENT_TYPE, "application/pdf"))
                .andReturn();

        byte[] pdfBytes = download.getResponse().getContentAsByteArray();
        String pdfSyntax = new String(pdfBytes, StandardCharsets.ISO_8859_1);
        assertThat(pdfPageCount(pdfBytes)).isEqualTo(2);
        assertThat(pdfSyntax).contains("/Count 2");
        assertThat(extractUnicodeTextLayer(pdfSyntax))
                .contains("first selected record text")
                .contains("second selected record text");
    }

    @Test
    void exportReadModelListsOnlyCurrentUserMetadataWithoutFileBytes() throws Exception {
        String alicePassword = testPassword();
        String bobPassword = testPassword();
        register("alice", alicePassword);
        register("bob", bobPassword);
        Long aliceRecord = insertRecord(userId("alice"), "Summary export", "camera", "export summary raw text", null);
        String aliceToken = bearer(accessToken("alice", alicePassword));
        String bobToken = bearer(accessToken("bob", bobPassword));

        MvcResult result = mockMvc.perform(post("/api/v1/exports/pdf")
                        .header(HttpHeaders.AUTHORIZATION, aliceToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of(
                                "recordIds", List.of(aliceRecord),
                                "fileName", "summary.pdf",
                                "searchable", true))))
                .andExpect(status().isOk())
                .andReturn();
        String jobId = jsonNode(result).path("data").path("jobId").asText();

        mockMvc.perform(get("/api/v1/exports")
                        .header(HttpHeaders.AUTHORIZATION, aliceToken))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data[0].jobId").value(jobId))
                .andExpect(jsonPath("$.data[0].status").value("SUCCESS"))
                .andExpect(jsonPath("$.data[0].fileName").value("summary.pdf"))
                .andExpect(jsonPath("$.data[0].downloadPath").value("/api/v1/exports/" + jobId + "/download"))
                .andExpect(jsonPath("$.data[0].content").doesNotExist())
                .andExpect(jsonPath("$.data[0].bytes").doesNotExist());

        mockMvc.perform(get("/api/v1/exports/{jobId}", jobId)
                        .header(HttpHeaders.AUTHORIZATION, aliceToken))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.jobId").value(jobId))
                .andExpect(jsonPath("$.data.sizeBytes").isNumber())
                .andExpect(jsonPath("$.data.content").doesNotExist());

        mockMvc.perform(get("/api/v1/exports/{jobId}", jobId)
                        .header(HttpHeaders.AUTHORIZATION, bobToken))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.code").value("NOT_FOUND"));

        mockMvc.perform(get("/api/v1/exports"))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.code").value("UNAUTHORIZED"));
    }

    @Test
    void createTextMarkdownAndJsonExportsExposeQueueMetadataAndDownloads() throws Exception {
        String password = testPassword();
        register("formats", password);
        Long recordId = insertRecord(
                userId("formats"),
                "Contract",
                "album",
                "contract raw text amount 42",
                "contract edited text amount 42");
        String token = bearer(accessToken("formats", password));

        Map<String, String> expectedContent = Map.of(
                "TXT", "contract edited text amount 42",
                "MARKDOWN", "# Contract",
                "JSON", "\"recordId\"");

        for (String format : List.of("TXT", "MARKDOWN", "JSON")) {
            MvcResult result = mockMvc.perform(post("/api/v1/exports")
                            .header(HttpHeaders.AUTHORIZATION, token)
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(json(Map.of(
                                    "recordIds", List.of(recordId),
                                    "fileName", "safe-" + format.toLowerCase(Locale.ROOT),
                                    "format", format))))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.data.status").value("SUCCESS"))
                    .andExpect(jsonPath("$.data.format").value(format))
                    .andExpect(jsonPath("$.data.downloadPath").value(org.hamcrest.Matchers.startsWith("/api/v1/exports/")))
                    .andReturn();

            String jobId = jsonNode(result).path("data").path("jobId").asText();
            MvcResult download = mockMvc.perform(get("/api/v1/exports/{jobId}/download", jobId)
                            .header(HttpHeaders.AUTHORIZATION, token))
                    .andExpect(status().isOk())
                    .andReturn();
            assertThat(download.getResponse().getContentAsString(StandardCharsets.UTF_8))
                    .contains(expectedContent.get(format))
                    .doesNotContain("objectKey")
                    .doesNotContain("file://media");
        }

        mockMvc.perform(get("/api/v1/exports")
                        .header(HttpHeaders.AUTHORIZATION, token))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data", org.hamcrest.Matchers.hasSize(3)))
                .andExpect(jsonPath("$.data[0].status").value("SUCCESS"))
                .andExpect(jsonPath("$.data[0].sizeBytes").isNumber());
    }

    @Test
    void exportJobsPersistProgressAndChecksumMetadataForAllFormats() throws Exception {
        String password = testPassword();
        register("metadata", password);
        Long recordId = insertRecord(
                userId("metadata"),
                "Metadata export",
                "album",
                "metadata export raw text",
                "metadata export edited text");
        String token = bearer(accessToken("metadata", password));

        for (String format : List.of("TXT", "MARKDOWN", "JSON", "PDF", "SEARCHABLE_PDF")) {
            MvcResult result = mockMvc.perform(post("/api/v1/exports")
                            .header(HttpHeaders.AUTHORIZATION, token)
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(json(Map.of(
                                    "recordIds", List.of(recordId),
                                    "fileName", "metadata-" + format.toLowerCase(Locale.ROOT),
                                    "format", format))))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.data.status").value("SUCCESS"))
                    .andExpect(jsonPath("$.data.progress").value(100))
                    .andExpect(jsonPath("$.data.checksumSha256").isString())
                    .andReturn();

            JsonNode data = jsonNode(result).path("data");
            String jobId = data.path("jobId").asText();
            String checksum = data.path("checksumSha256").asText();
            assertThat(checksum).matches("[0-9a-f]{64}");

            Map<String, Object> persisted = jdbcTemplate.queryForMap(
                    "SELECT progress, checksum_sha256 FROM export_jobs WHERE job_id = ?",
                    jobId);
            assertThat(persisted.get("PROGRESS")).isEqualTo(100);
            assertThat(persisted.get("CHECKSUM_SHA256")).isEqualTo(checksum);

            MvcResult detail = mockMvc.perform(get("/api/v1/exports/{jobId}", jobId)
                            .header(HttpHeaders.AUTHORIZATION, token))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.data.progress").value(100))
                    .andExpect(jsonPath("$.data.checksumSha256").value(checksum))
                    .andReturn();
            assertThat(jsonNode(detail).path("data").path("checksumSha256").asText()).isEqualTo(checksum);

            MvcResult download = mockMvc.perform(get("/api/v1/exports/{jobId}/download", jobId)
                            .header(HttpHeaders.AUTHORIZATION, token))
                    .andExpect(status().isOk())
                    .andReturn();
            assertThat(sha256(download.getResponse().getContentAsByteArray())).isEqualTo(checksum);
        }
    }

    @Test
    void exportJobResponseIncludesPersistedSanitizedStatusHistory() throws Exception {
        String password = testPassword();
        register("lifecycle", password);
        Long recordId = insertRecord(
                userId("lifecycle"),
                "Lifecycle export",
                "album",
                "lifecycle raw text",
                "lifecycle edited text");
        String token = bearer(accessToken("lifecycle", password));

        MvcResult result = mockMvc.perform(post("/api/v1/exports")
                        .header(HttpHeaders.AUTHORIZATION, token)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of(
                                "recordIds", List.of(recordId),
                                "fileName", "lifecycle.txt",
                                "format", "TXT"))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.status").value("SUCCESS"))
                .andExpect(jsonPath("$.data.statusHistory[0].status").value("PENDING"))
                .andExpect(jsonPath("$.data.statusHistory[0].progress").value(0))
                .andExpect(jsonPath("$.data.statusHistory[1].status").value("RUNNING"))
                .andExpect(jsonPath("$.data.statusHistory[1].progress").value(10))
                .andExpect(jsonPath("$.data.statusHistory[2].status").value("SUCCESS"))
                .andExpect(jsonPath("$.data.statusHistory[2].progress").value(100))
                .andExpect(jsonPath("$.data.statusHistory[0].objectKey").doesNotExist())
                .andExpect(jsonPath("$.data.statusHistory[0].content").doesNotExist())
                .andReturn();

        String jobId = jsonNode(result).path("data").path("jobId").asText();
        Long persistedEvents = jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM export_job_status_events WHERE job_id = ?",
                Long.class,
                jobId);
        assertThat(persistedEvents).isEqualTo(3L);

        mockMvc.perform(get("/api/v1/exports/{jobId}", jobId)
                        .header(HttpHeaders.AUTHORIZATION, token))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.statusHistory[0].status").value("PENDING"))
                .andExpect(jsonPath("$.data.statusHistory[1].status").value("RUNNING"))
                .andExpect(jsonPath("$.data.statusHistory[2].status").value("SUCCESS"));
    }

    @Test
    void exportJobsPersistInDatabaseAndRemainReadableThroughPublicApi() throws Exception {
        String password = testPassword();
        register("durable", password);
        Long recordId = insertRecord(userId("durable"), "Durable export", "camera", "durable export text", null);
        String token = bearer(accessToken("durable", password));

        MvcResult result = mockMvc.perform(post("/api/v1/exports")
                        .header(HttpHeaders.AUTHORIZATION, token)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of(
                                "recordIds", List.of(recordId),
                                "fileName", "durable.txt",
                                "format", "TXT"))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.status").value("SUCCESS"))
                .andReturn();
        String jobId = jsonNode(result).path("data").path("jobId").asText();

        Long persistedJobs = jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM export_jobs WHERE job_id = ? AND user_id = ?",
                Long.class,
                jobId,
                userId("durable"));
        assertThat(persistedJobs).isEqualTo(1L);

        mockMvc.perform(get("/api/v1/exports")
                        .header(HttpHeaders.AUTHORIZATION, token))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data[0].jobId").value(jobId))
                .andExpect(jsonPath("$.data[0].status").value("SUCCESS"))
                .andExpect(jsonPath("$.data[0].sizeBytes").isNumber())
                .andExpect(jsonPath("$.data[0].content").doesNotExist());

        mockMvc.perform(get("/api/v1/exports/{jobId}", jobId)
                        .header(HttpHeaders.AUTHORIZATION, token))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.jobId").value(jobId))
                .andExpect(jsonPath("$.data.fileName").value("durable.txt"));

        MvcResult download = mockMvc.perform(get("/api/v1/exports/{jobId}/download", jobId)
                        .header(HttpHeaders.AUTHORIZATION, token))
                .andExpect(status().isOk())
                .andReturn();
        assertThat(download.getResponse().getContentAsString(StandardCharsets.UTF_8))
                .contains("durable export text");
    }

    @Test
    void pendingExportJobCanBeCanceledByOwnerAndCannotBeDownloadedOrCanceledByOtherUsers() throws Exception {
        String ownerPassword = testPassword();
        String otherPassword = testPassword();
        register("cancel-owner", ownerPassword);
        register("cancel-other", otherPassword);
        String jobId = "export-cancel-" + UUID.randomUUID();
        jdbcTemplate.update("""
                        INSERT INTO export_jobs
                            (job_id, user_id, status, format, file_name, content_type, size_bytes,
                             searchable, degraded, content, progress, checksum_sha256, created_at)
                        VALUES (?, ?, 'PENDING', 'TXT', 'cancel.txt', 'text/plain; charset=utf-8', 0,
                                FALSE, FALSE, ?, 0, '', CURRENT_TIMESTAMP)
                        """,
                jobId,
                userId("cancel-owner"),
                new byte[0]);

        mockMvc.perform(post("/api/v1/exports/{jobId}/cancel", jobId)
                        .header(HttpHeaders.AUTHORIZATION, bearer(accessToken("cancel-other", otherPassword))))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.code").value("NOT_FOUND"));

        mockMvc.perform(post("/api/v1/exports/{jobId}/cancel", jobId)
                        .header(HttpHeaders.AUTHORIZATION, bearer(accessToken("cancel-owner", ownerPassword))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.jobId").value(jobId))
                .andExpect(jsonPath("$.data.status").value("CANCELED"))
                .andExpect(jsonPath("$.data.progress").value(0))
                .andExpect(jsonPath("$.data.downloadPath").doesNotExist());

        assertThat(jdbcTemplate.queryForObject(
                "SELECT status FROM export_jobs WHERE job_id = ?",
                String.class,
                jobId)).isEqualTo("CANCELED");

        mockMvc.perform(get("/api/v1/exports/{jobId}/download", jobId)
                        .header(HttpHeaders.AUTHORIZATION, bearer(accessToken("cancel-owner", ownerPassword))))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.code").value("NOT_FOUND"));
    }

    @Test
    void searchablePdfMatrixExportsUnicodeTextLayerWithoutLeakingFullTextToLogs() throws Exception {
        String password = testPassword();
        register("matrix", password);
        Long userId = userId("matrix");
        Long englishRecord = insertRecord(userId, "English receipt", "camera", "English searchable receipt total 18.50", null);
        Long chineseRecord = insertRecord(userId, "中文票据", "album", "中文可搜索文本 合计一百二十三元", null);
        Long emptyRecord = insertRecord(userId, "Empty source", "camera", "", null);
        Long multilineRecord = insertRecord(userId, "Multiline note", "album", "first line\nsecond searchable line\r\nthird line", null);
        Long longRecord = insertRecord(
                userId,
                "Long OCR",
                "camera",
                "long-prefix " + "segment-".repeat(220) + "long-search-tail",
                null);
        Long wideImageRecord = insertRecord(userId, "Wide image fixture 4000x1000", "album", "wide image searchable text", null);
        Long tallImageRecord = insertRecord(userId, "Tall image fixture 900x3200", "camera", "tall image searchable text", null);

        MvcResult result = mockMvc.perform(post("/api/v1/exports/pdf")
                        .header(HttpHeaders.AUTHORIZATION, bearer(accessToken("matrix", password)))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of(
                                "recordIds", List.of(
                                        englishRecord,
                                        chineseRecord,
                                        emptyRecord,
                                        multilineRecord,
                                        longRecord,
                                        wideImageRecord,
                                        tallImageRecord),
                                "fileName", " ..\\unsafe 中文 matrix?.pdf ",
                                "searchable", true))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.status").value("SUCCESS"))
                .andExpect(jsonPath("$.data.format").value("SEARCHABLE_PDF"))
                .andExpect(jsonPath("$.data.fileName").value("unsafe_中文_matrix.pdf"))
                .andExpect(jsonPath("$.data.searchable").value(true))
                .andExpect(jsonPath("$.data.degraded").value(false))
                .andReturn();

        String jobId = jsonNode(result).path("data").path("jobId").asText();
        MvcResult download = mockMvc.perform(get("/api/v1/exports/{jobId}/download", jobId)
                        .header(HttpHeaders.AUTHORIZATION, bearer(accessToken("matrix", password))))
                .andExpect(status().isOk())
                .andExpect(header().string(HttpHeaders.CONTENT_TYPE, "application/pdf"))
                .andExpect(header().string(
                        HttpHeaders.CONTENT_DISPOSITION,
                        "attachment; filename=\"unsafe_中文_matrix.pdf\""))
                .andReturn();

        byte[] pdfBytes = download.getResponse().getContentAsByteArray();
        String pdfSyntax = new String(pdfBytes, StandardCharsets.ISO_8859_1);
        String searchableText = extractUnicodeTextLayer(pdfSyntax);
        assertThat(searchableText)
                .contains("English searchable receipt total 18.50")
                .contains("中文可搜索文本 合计一百二十三元")
                .contains("Empty source")
                .contains("first line")
                .contains("second searchable line")
                .contains("third line")
                .contains("long-search-tail")
                .contains("Wide image fixture 4000x1000")
                .contains("Tall image fixture 900x3200")
                .contains("wide image searchable text")
                .contains("tall image searchable text");
        assertThat(pdfSyntax).contains("/Count 7");
        assertThat(pdfPageCount(pdfBytes)).isEqualTo(7);
        assertThat(UNICODE_TEXT_OPERATOR.matcher(pdfSyntax).results().count()).isGreaterThanOrEqualTo(14);
    }

    private String extractUnicodeTextLayer(String pdfSyntax) {
        Matcher matcher = UNICODE_TEXT_OPERATOR.matcher(pdfSyntax);
        List<String> fragments = new ArrayList<>();
        while (matcher.find()) {
            fragments.add(decodePdfUnicodeHex(matcher.group(1)));
        }
        return String.join("\n", fragments);
    }

    private String decodePdfUnicodeHex(String hex) {
        ByteArrayOutputStream bytes = new ByteArrayOutputStream();
        for (int index = 0; index < hex.length(); index += 2) {
            bytes.write(Integer.parseInt(hex.substring(index, index + 2), 16));
        }
        byte[] data = bytes.toByteArray();
        int offset = data.length >= 2 && (data[0] & 0xFF) == 0xFE && (data[1] & 0xFF) == 0xFF ? 2 : 0;
        return new String(data, offset, data.length - offset, UTF_16BE);
    }

    private Long insertRecord(Long userId, String title, String sourceType, String rawText, String editedText) {
        jdbcTemplate.update("""
                INSERT INTO recognition_records
                    (user_id, title, source_type, raw_text, edited_text, favorite, deleted, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, 0, 0, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
                """, userId, title, sourceType, rawText, editedText);
        return jdbcTemplate.queryForObject("SELECT MAX(id) FROM recognition_records", Long.class);
    }

    private void insertRecordPage(
            Long recordId,
            int pageIndex,
            int pageNumber,
            String status,
            String rawText,
            String editedText,
            String errorCode,
            String failureReason) {
        jdbcTemplate.update("""
                INSERT INTO recognition_record_pages
                    (record_id, page_index, page_number, status, raw_text, edited_text,
                     duration_ms, confidence, error_code, failure_reason, created_at)
                VALUES (?, ?, ?, ?, ?, ?, NULL, NULL, ?, ?, CURRENT_TIMESTAMP)
                """,
                recordId,
                pageIndex,
                pageNumber,
                status,
                rawText,
                editedText,
                errorCode,
                failureReason);
    }

    private int pdfPageCount(byte[] pdfBytes) throws Exception {
        try (PDDocument document = Loader.loadPDF(pdfBytes)) {
            return document.getNumberOfPages();
        }
    }

    private void register(String username, String password) throws Exception {
        mockMvc.perform(post("/api/v1/auth/register")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of("username", username, "password", password))))
                .andExpect(status().isOk());
    }

    private String accessToken(String username, String password) throws Exception {
        MvcResult result = mockMvc.perform(post("/api/v1/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of("username", username, "password", password))))
                .andExpect(status().isOk())
                .andReturn();
        return jsonNode(result).path("data").path("accessToken").asText();
    }

    private Long userId(String username) {
        return jdbcTemplate.queryForObject("SELECT id FROM users WHERE username = ?", Long.class, username);
    }

    private String testPassword() {
        return "test-" + UUID.randomUUID();
    }

    private String bearer(String accessToken) {
        return "Bearer " + accessToken;
    }

    private String sha256(byte[] content) throws Exception {
        byte[] digest = MessageDigest.getInstance("SHA-256").digest(content);
        StringBuilder builder = new StringBuilder();
        for (byte value : digest) {
            builder.append("%02x".formatted(value & 0xFF));
        }
        return builder.toString();
    }

    private String json(Object value) throws Exception {
        return objectMapper.writeValueAsString(value);
    }

    private JsonNode jsonNode(MvcResult result) throws Exception {
        return objectMapper.readTree(result.getResponse().getContentAsString());
    }
}
