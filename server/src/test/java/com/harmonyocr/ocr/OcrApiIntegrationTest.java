package com.harmonyocr.ocr;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.harmonyocr.common.error.BusinessException;
import com.harmonyocr.common.error.ErrorCode;
import com.harmonyocr.ocr.dto.OcrRequest;
import com.harmonyocr.ocr.dto.OcrRecognizeResponse;
import com.harmonyocr.ocr.dto.OcrResult;
import com.harmonyocr.ocr.dto.OcrTextBlockResponse;
import com.harmonyocr.ocr.provider.OcrProvider;
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;

import static org.hamcrest.Matchers.containsString;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.doAnswer;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@ActiveProfiles("test")
@AutoConfigureMockMvc
@SpringBootTest
/**
 * OCR API 集成测试。
 * 维护说明：覆盖图片上传识别、额度消耗、错误响应和 provider 结果映射，不调用真实外部 OCR 服务。
 */
class OcrApiIntegrationTest {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    @Autowired
    private JdbcTemplate jdbcTemplate;

    @MockBean
    private OcrProvider ocrProvider;

    @BeforeEach
    void cleanDatabase() {
        jdbcTemplate.update("DELETE FROM batch_ocr_items");
        jdbcTemplate.update("DELETE FROM batch_ocr_jobs");
        jdbcTemplate.update("DELETE FROM object_storage_cleanup_tasks");
        jdbcTemplate.update("DELETE FROM file_objects");
        jdbcTemplate.update("DELETE FROM recognition_blocks");
        jdbcTemplate.update("DELETE FROM recognition_records");
        jdbcTemplate.update("DELETE FROM refresh_tokens");
        jdbcTemplate.update("DELETE FROM user_devices");
        jdbcTemplate.update("DELETE FROM export_jobs");
        jdbcTemplate.update("DELETE FROM users");
    }

    @Test
    void recognizeRequiresAuthentication() throws Exception {
        mockMvc.perform(multipart("/api/v1/ocr/recognize")
                        .file(pngFile()))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.success").value(false))
                .andExpect(jsonPath("$.code").value("UNAUTHORIZED"));

        verify(ocrProvider, never()).recognize(any());
    }

    @Test
    void recognizeValidImageReturnsUnifiedRealProviderResult() throws Exception {
        String password = testPassword();
        register("alice", password);
        when(ocrProvider.recognize(any(OcrRequest.class)))
                .thenReturn(new OcrResult(
                        "backend-fallback",
                        "tesseract",
                        "single-image",
                        "V1 OCR TEST 123 Harmony OCR",
                        42,
                        "eng",
                        0.88,
                        "{\"x\":1,\"y\":2,\"width\":120,\"height\":32}",
                        List.of(new OcrTextBlockResponse(1, "V1 OCR TEST 123 Harmony OCR", 0.88, "{\"x\":1,\"y\":2}")),
                        null));

        mockMvc.perform(multipart("/api/v1/ocr/recognize")
                        .file(pngFile())
                        .param("language", "eng")
                        .header(HttpHeaders.AUTHORIZATION, bearer(accessToken("alice", password))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.success").value(true))
                .andExpect(jsonPath("$.code").value("OK"))
                .andExpect(jsonPath("$.data.rawText", containsString("OCR")))
                .andExpect(jsonPath("$.data.editedText", containsString("123")))
                .andExpect(jsonPath("$.data.durationMs").value(42))
                .andExpect(jsonPath("$.data.language").value("eng"))
                .andExpect(jsonPath("$.data.ocrEngine").value("tesseract"))
                .andExpect(jsonPath("$.data.providerName").value("backend-fallback"))
                .andExpect(jsonPath("$.data.engineName").value("tesseract"))
                .andExpect(jsonPath("$.data.mode").value("single-image"))
                .andExpect(jsonPath("$.data.confidence").value(0.88))
                .andExpect(jsonPath("$.data.boundingBox").value("{\"x\":1,\"y\":2,\"width\":120,\"height\":32}"))
                .andExpect(jsonPath("$.data.blocks[0].order").value(1))
                .andExpect(jsonPath("$.data.blocks[0].boundingBox").value("{\"x\":1,\"y\":2}"));

        verify(ocrProvider).recognize(any(OcrRequest.class));
    }

    @Test
    void recognizeRejectsNonImageAndMismatchedImageBeforeProviderRuns() throws Exception {
        String password = testPassword();
        register("alice", password);
        String token = accessToken("alice", password);

        mockMvc.perform(multipart("/api/v1/ocr/recognize")
                        .file(new MockMultipartFile("file", "note.txt", "text/plain", "hello".getBytes(StandardCharsets.UTF_8)))
                        .header(HttpHeaders.AUTHORIZATION, bearer(token)))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("FILE_TYPE_NOT_ALLOWED"));

        mockMvc.perform(multipart("/api/v1/ocr/recognize")
                        .file(new MockMultipartFile("file", "fake.png", "image/png", "not png".getBytes(StandardCharsets.UTF_8)))
                        .header(HttpHeaders.AUTHORIZATION, bearer(token)))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("FILE_TYPE_NOT_ALLOWED"));

        verify(ocrProvider, never()).recognize(any());
    }

    @Test
    void healthUsesProviderWithoutExposingRuntimePath() throws Exception {
        String password = testPassword();
        register("alice", password);
        when(ocrProvider.isAvailable()).thenReturn(true);
        when(ocrProvider.engineName()).thenReturn("tesseract");

        mockMvc.perform(get("/api/v1/ocr/health")
                        .header(HttpHeaders.AUTHORIZATION, bearer(accessToken("alice", password))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.available").value(true))
                .andExpect(jsonPath("$.data.ocrEngine").value("tesseract"));
    }

    @Test
    void batchRecognizeTracksItemStatusAndRetriesFailedItem() throws Exception {
        String password = testPassword();
        register("alice", password);
        when(ocrProvider.recognize(any(OcrRequest.class)))
                .thenReturn(new OcrResult(
                        "backend-fallback",
                        "tesseract",
                        "single-image",
                        "First OCR",
                        12,
                        "eng",
                        null,
                        null,
                        List.of(new OcrTextBlockResponse(1, "First OCR", null, null)),
                        null))
                .thenThrow(new BusinessException(ErrorCode.OCR_FAILED, "provider failed"))
                .thenReturn(new OcrResult(
                        "backend-fallback",
                        "tesseract",
                        "single-image",
                        "Retry OCR",
                        18,
                        "eng",
                        null,
                        null,
                        List.of(new OcrTextBlockResponse(1, "Retry OCR", null, null)),
                        null));

        MvcResult batchResult = mockMvc.perform(multipart("/api/v1/ocr/batches")
                        .file(new MockMultipartFile("files", "first.png", "image/png", validPng()))
                        .file(new MockMultipartFile("files", "second.png", "image/png", validPng()))
                        .param("language", "eng")
                        .param("saveToHistory", "true")
                        .header(HttpHeaders.AUTHORIZATION, bearer(accessToken("alice", password))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.status").value("FAILED"))
                .andExpect(jsonPath("$.data.total").value(2))
                .andExpect(jsonPath("$.data.completed").value(1))
                .andExpect(jsonPath("$.data.failed").value(1))
                .andExpect(jsonPath("$.data.progress").value(50))
                .andExpect(jsonPath("$.data.recordId").isNumber())
                .andExpect(jsonPath("$.data.items[0].status").value("SUCCESS"))
                .andExpect(jsonPath("$.data.items[0].recordId").isNumber())
                .andExpect(jsonPath("$.data.items[1].status").value("FAILED"))
                .andExpect(jsonPath("$.data.items[1].errorCode").value("OCR_FAILED"))
                .andReturn();

        String jobId = objectMapper.readTree(batchResult.getResponse().getContentAsString())
                .path("data")
                .path("jobId")
                .asText();
        long aggregateRecordId = objectMapper.readTree(batchResult.getResponse().getContentAsString())
                .path("data")
                .path("recordId")
                .asLong();

        mockMvc.perform(get("/api/v1/records/{id}", aggregateRecordId)
                        .header(HttpHeaders.AUTHORIZATION, bearer(accessToken("alice", password))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.sourceType").value("batch"))
                .andExpect(jsonPath("$.data.pageCount").value(2))
                .andExpect(jsonPath("$.data.successPageCount").value(1))
                .andExpect(jsonPath("$.data.failedPageCount").value(1))
                .andExpect(jsonPath("$.data.pages[0].status").value("SUCCESS"))
                .andExpect(jsonPath("$.data.pages[1].status").value("FAILED"));

        mockMvc.perform(multipart("/api/v1/ocr/batches/{jobId}/items/{itemIndex}/retry", jobId, 1)
                        .file(new MockMultipartFile("file", "retry.png", "image/png", validPng()))
                        .param("language", "eng")
                        .param("saveToHistory", "true")
                        .header(HttpHeaders.AUTHORIZATION, bearer(accessToken("alice", password))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.status").value("SUCCESS"))
                .andExpect(jsonPath("$.data.completed").value(2))
                .andExpect(jsonPath("$.data.failed").value(0))
                .andExpect(jsonPath("$.data.progress").value(100))
                .andExpect(jsonPath("$.data.recordId").value((int) aggregateRecordId))
                .andExpect(jsonPath("$.data.items[0].recordId").value((int) aggregateRecordId))
                .andExpect(jsonPath("$.data.items[1].status").value("SUCCESS"))
                .andExpect(jsonPath("$.data.items[1].recordId").value((int) aggregateRecordId));

        mockMvc.perform(get("/api/v1/records/{id}", aggregateRecordId)
                        .header(HttpHeaders.AUTHORIZATION, bearer(accessToken("alice", password))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.pageCount").value(2))
                .andExpect(jsonPath("$.data.successPageCount").value(2))
                .andExpect(jsonPath("$.data.failedPageCount").value(0))
                .andExpect(jsonPath("$.data.editedText").value(containsString("First OCR")))
                .andExpect(jsonPath("$.data.editedText").value(containsString("Retry OCR")));

        org.assertj.core.api.Assertions.assertThat(jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM recognition_records WHERE user_id = ? AND source_type = 'batch'",
                Long.class,
                userId("alice"))).isEqualTo(1L);
    }

    @Test
    void batchReadModelListsOnlyCurrentUserSummaryWithoutOcrText() throws Exception {
        String alicePassword = testPassword();
        String bobPassword = testPassword();
        register("alice", alicePassword);
        register("bob", bobPassword);
        when(ocrProvider.recognize(any(OcrRequest.class)))
                .thenReturn(new OcrResult(
                        "backend-fallback",
                        "tesseract",
                        "single-image",
                        "Batch summary should not leak full OCR text",
                        15,
                        "eng",
                        null,
                        null,
                        List.of(new OcrTextBlockResponse(1, "Batch summary should not leak full OCR text", null, null)),
                        null));
        String aliceToken = bearer(accessToken("alice", alicePassword));
        String bobToken = bearer(accessToken("bob", bobPassword));

        MvcResult batchResult = mockMvc.perform(multipart("/api/v1/ocr/batches")
                        .file(new MockMultipartFile("files", "summary-seed.png", "image/png", validPng()))
                        .param("language", "eng")
                        .param("saveToHistory", "true")
                        .header(HttpHeaders.AUTHORIZATION, aliceToken))
                .andExpect(status().isOk())
                .andReturn();
        String jobId = objectMapper.readTree(batchResult.getResponse().getContentAsString())
                .path("data")
                .path("jobId")
                .asText();

        mockMvc.perform(get("/api/v1/ocr/batches")
                        .header(HttpHeaders.AUTHORIZATION, aliceToken))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data[0].jobId").value(jobId))
                .andExpect(jsonPath("$.data[0].status").value("SUCCESS"))
                .andExpect(jsonPath("$.data[0].recordId").isNumber())
                .andExpect(jsonPath("$.data[0].total").value(1))
                .andExpect(jsonPath("$.data[0].completed").value(1))
                .andExpect(jsonPath("$.data[0].items[0].fileName").value("summary-seed.png"))
                .andExpect(jsonPath("$.data[0].items[0].recordId").isNumber())
                .andExpect(jsonPath("$.data[0].items[0].result").doesNotExist())
                .andExpect(jsonPath("$.data[0].items[0].rawText").doesNotExist())
                .andExpect(jsonPath("$.data[0].items[0].editedText").doesNotExist());

        mockMvc.perform(get("/api/v1/ocr/batches/{jobId}", jobId)
                        .header(HttpHeaders.AUTHORIZATION, aliceToken))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.jobId").value(jobId))
                .andExpect(jsonPath("$.data.recordId").isNumber())
                .andExpect(jsonPath("$.data.items[0].status").value("SUCCESS"))
                .andExpect(jsonPath("$.data.items[0].result").doesNotExist());

        mockMvc.perform(get("/api/v1/ocr/batches/{jobId}", jobId)
                        .header(HttpHeaders.AUTHORIZATION, bobToken))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.code").value("NOT_FOUND"));

        mockMvc.perform(get("/api/v1/ocr/batches"))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.code").value("UNAUTHORIZED"));
    }

    @Test
    void legacyPerItemBatchRecordsAreConsolidatedWhenBatchIsRead() throws Exception {
        String password = testPassword();
        register("legacy-batch", password);
        Long userId = userId("legacy-batch");
        Long firstLegacyRecord = insertRecord(userId, "Batch OCR", "import", "legacy first raw", "legacy first edited");
        Long secondLegacyRecord = insertRecord(userId, "Batch OCR", "import", "legacy second raw", "legacy second edited");
        String jobId = "legacy-batch-" + UUID.randomUUID();
        jdbcTemplate.update("""
                        INSERT INTO batch_ocr_jobs
                            (job_id, user_id, status, progress, record_id, created_at, updated_at)
                        VALUES (?, ?, 'SUCCESS', 100, NULL, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
                        """,
                jobId,
                userId);
        jdbcTemplate.update("""
                        INSERT INTO batch_ocr_items
                            (job_id, item_index, file_name, status, record_id, error_code, failure_reason, retry_count, updated_at)
                        VALUES (?, 0, 'legacy-first.png', 'SUCCESS', ?, NULL, NULL, 0, CURRENT_TIMESTAMP)
                        """,
                jobId,
                firstLegacyRecord);
        jdbcTemplate.update("""
                        INSERT INTO batch_ocr_items
                            (job_id, item_index, file_name, status, record_id, error_code, failure_reason, retry_count, updated_at)
                        VALUES (?, 1, 'legacy-second.png', 'SUCCESS', ?, NULL, NULL, 0, CURRENT_TIMESTAMP)
                        """,
                jobId,
                secondLegacyRecord);

        MvcResult detailResult = mockMvc.perform(get("/api/v1/ocr/batches/{jobId}", jobId)
                        .header(HttpHeaders.AUTHORIZATION, bearer(accessToken("legacy-batch", password))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.recordId").isNumber())
                .andExpect(jsonPath("$.data.items[0].recordId").isNumber())
                .andExpect(jsonPath("$.data.items[1].recordId").isNumber())
                .andReturn();
        long aggregateRecordId = objectMapper.readTree(detailResult.getResponse().getContentAsString())
                .path("data")
                .path("recordId")
                .asLong();

        org.assertj.core.api.Assertions.assertThat(aggregateRecordId)
                .isNotEqualTo(firstLegacyRecord)
                .isNotEqualTo(secondLegacyRecord);
        org.assertj.core.api.Assertions.assertThat(jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM recognition_records WHERE id IN (?, ?) AND deleted = 0",
                Long.class,
                firstLegacyRecord,
                secondLegacyRecord)).isEqualTo(0L);
        org.assertj.core.api.Assertions.assertThat(jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM recognition_records WHERE user_id = ? AND source_type = 'batch' AND deleted = 0",
                Long.class,
                userId)).isEqualTo(1L);

        mockMvc.perform(get("/api/v1/records/{id}", aggregateRecordId)
                        .header(HttpHeaders.AUTHORIZATION, bearer(accessToken("legacy-batch", password))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.sourceType").value("batch"))
                .andExpect(jsonPath("$.data.pageCount").value(2))
                .andExpect(jsonPath("$.data.editedText").value(containsString("legacy first edited")))
                .andExpect(jsonPath("$.data.editedText").value(containsString("legacy second edited")));
    }

    @Test
    void batchJobsPersistInDatabaseAndRemainReadableAndRetryableThroughPublicApi() throws Exception {
        String password = testPassword();
        register("durable-batch", password);
        when(ocrProvider.recognize(any(OcrRequest.class)))
                .thenReturn(new OcrResult(
                        "backend-fallback",
                        "tesseract",
                        "single-image",
                        "Durable first OCR",
                        12,
                        "eng",
                        null,
                        null,
                        List.of(new OcrTextBlockResponse(1, "Durable first OCR", null, null)),
                        null))
                .thenThrow(new BusinessException(ErrorCode.OCR_FAILED, "provider failed before persistence"))
                .thenReturn(new OcrResult(
                        "backend-fallback",
                        "tesseract",
                        "single-image",
                        "Durable retry OCR",
                        18,
                        "eng",
                        null,
                        null,
                        List.of(new OcrTextBlockResponse(1, "Durable retry OCR", null, null)),
                        null));
        String token = bearer(accessToken("durable-batch", password));

        MvcResult batchResult = mockMvc.perform(multipart("/api/v1/ocr/batches")
                        .file(new MockMultipartFile("files", "first.png", "image/png", validPng()))
                        .file(new MockMultipartFile("files", "second.png", "image/png", validPng()))
                        .param("language", "eng")
                        .param("saveToHistory", "true")
                        .header(HttpHeaders.AUTHORIZATION, token))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.status").value("FAILED"))
                .andExpect(jsonPath("$.data.progress").value(50))
                .andReturn();

        String jobId = objectMapper.readTree(batchResult.getResponse().getContentAsString())
                .path("data")
                .path("jobId")
                .asText();
        long aggregateRecordId = objectMapper.readTree(batchResult.getResponse().getContentAsString())
                .path("data")
                .path("recordId")
                .asLong();

        Long persistedJobs = jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM batch_ocr_jobs WHERE job_id = ?",
                Long.class,
                jobId);
        Long persistedItems = jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM batch_ocr_items WHERE job_id = ?",
                Long.class,
                jobId);
        Long persistedFailedItems = jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM batch_ocr_items WHERE job_id = ? AND status = 'FAILED'",
                Long.class,
                jobId);
        org.assertj.core.api.Assertions.assertThat(persistedJobs).isEqualTo(1L);
        org.assertj.core.api.Assertions.assertThat(persistedItems).isEqualTo(2L);
        org.assertj.core.api.Assertions.assertThat(persistedFailedItems).isEqualTo(1L);

        mockMvc.perform(get("/api/v1/ocr/batches")
                        .header(HttpHeaders.AUTHORIZATION, token))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data[0].jobId").value(jobId))
                .andExpect(jsonPath("$.data[0].status").value("FAILED"))
                .andExpect(jsonPath("$.data[0].recordId").value((int) aggregateRecordId))
                .andExpect(jsonPath("$.data[0].progress").value(50))
                .andExpect(jsonPath("$.data[0].items[1].status").value("FAILED"))
                .andExpect(jsonPath("$.data[0].items[1].failureReason").value("provider failed before persistence"))
                .andExpect(jsonPath("$.data[0].items[0].result").doesNotExist())
                .andExpect(jsonPath("$.data[0].items[0].rawText").doesNotExist());

        mockMvc.perform(get("/api/v1/ocr/batches/{jobId}", jobId)
                        .header(HttpHeaders.AUTHORIZATION, token))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.jobId").value(jobId))
                .andExpect(jsonPath("$.data.items[0].status").value("SUCCESS"))
                .andExpect(jsonPath("$.data.items[1].status").value("FAILED"));

        mockMvc.perform(multipart("/api/v1/ocr/batches/{jobId}/items/{itemIndex}/retry", jobId, 1)
                        .file(new MockMultipartFile("file", "retry.png", "image/png", validPng()))
                        .param("language", "eng")
                        .param("saveToHistory", "true")
                        .header(HttpHeaders.AUTHORIZATION, token))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.status").value("SUCCESS"))
                .andExpect(jsonPath("$.data.completed").value(2))
                .andExpect(jsonPath("$.data.failed").value(0))
                .andExpect(jsonPath("$.data.progress").value(100))
                .andExpect(jsonPath("$.data.recordId").value((int) aggregateRecordId))
                .andExpect(jsonPath("$.data.items[0].recordId").value((int) aggregateRecordId))
                .andExpect(jsonPath("$.data.items[1].status").value("SUCCESS"))
                .andExpect(jsonPath("$.data.items[1].recordId").value((int) aggregateRecordId));

        org.assertj.core.api.Assertions.assertThat(jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM recognition_records WHERE user_id = ? AND source_type = 'batch'",
                Long.class,
                userId("durable-batch"))).isEqualTo(1L);
    }

    @Test
    void batchWorkerPersistsJobProgressQueueStateAndRetryAttemptState() throws Exception {
        String password = testPassword();
        register("worker-batch", password);
        String token = bearer(accessToken("worker-batch", password));
        final String[] currentJobId = new String[1];

        doAnswer(invocation -> {
                    String jobId = currentJobId[0] == null ? latestBatchJobIdForUser("worker-batch") : currentJobId[0];
                    currentJobId[0] = jobId;
                    org.assertj.core.api.Assertions.assertThat(jobId).isNotBlank();
                    org.assertj.core.api.Assertions.assertThat(jdbcTemplate.queryForObject(
                            "SELECT status FROM batch_ocr_jobs WHERE job_id = ?",
                            String.class,
                            jobId)).isEqualTo("RUNNING");
                    org.assertj.core.api.Assertions.assertThat(jdbcTemplate.queryForObject(
                            "SELECT progress FROM batch_ocr_jobs WHERE job_id = ?",
                            Integer.class,
                            jobId)).isZero();
                    org.assertj.core.api.Assertions.assertThat(jdbcTemplate.queryForObject(
                            "SELECT status FROM batch_ocr_items WHERE job_id = ? AND item_index = 0",
                            String.class,
                            jobId)).isEqualTo("RUNNING");
                    org.assertj.core.api.Assertions.assertThat(jdbcTemplate.queryForObject(
                            "SELECT status FROM batch_ocr_items WHERE job_id = ? AND item_index = 1",
                            String.class,
                            jobId)).isEqualTo("QUEUED");
                    return new OcrResult(
                            "backend-fallback",
                            "tesseract",
                            "single-image",
                            "Queued worker first OCR",
                            12,
                            "eng",
                            null,
                            null,
                            List.of(new OcrTextBlockResponse(1, "Queued worker first OCR", null, null)),
                            null);
                })
                .doThrow(new BusinessException(ErrorCode.OCR_FAILED, "provider failed in durable worker"))
                .doAnswer(invocation -> {
                    String jobId = currentJobId[0] == null ? latestBatchJobIdForUser("worker-batch") : currentJobId[0];
                    currentJobId[0] = jobId;
                    org.assertj.core.api.Assertions.assertThat(jdbcTemplate.queryForObject(
                            "SELECT status FROM batch_ocr_jobs WHERE job_id = ?",
                            String.class,
                            jobId)).isEqualTo("RETRYING");
                    org.assertj.core.api.Assertions.assertThat(jdbcTemplate.queryForObject(
                            "SELECT status FROM batch_ocr_items WHERE job_id = ? AND item_index = 1",
                            String.class,
                            jobId)).isEqualTo("RETRYING");
                    org.assertj.core.api.Assertions.assertThat(jdbcTemplate.queryForObject(
                            "SELECT retry_count FROM batch_ocr_items WHERE job_id = ? AND item_index = 1",
                            Integer.class,
                            jobId)).isEqualTo(1);
                    return new OcrResult(
                            "backend-fallback",
                            "tesseract",
                            "single-image",
                            "Queued worker retry OCR",
                            18,
                            "eng",
                            null,
                            null,
                            List.of(new OcrTextBlockResponse(1, "Queued worker retry OCR", null, null)),
                            null);
                })
                .when(ocrProvider).recognize(any(OcrRequest.class));

        MvcResult batchResult = mockMvc.perform(multipart("/api/v1/ocr/batches")
                        .file(new MockMultipartFile("files", "first.png", "image/png", validPng()))
                        .file(new MockMultipartFile("files", "second.png", "image/png", validPng()))
                        .param("language", "eng")
                        .param("saveToHistory", "true")
                        .header(HttpHeaders.AUTHORIZATION, token))
                .andExpect(status().isOk())
                .andReturn();
        currentJobId[0] = objectMapper.readTree(batchResult.getResponse().getContentAsString())
                .path("data")
                .path("jobId")
                .asText();

        org.assertj.core.api.Assertions.assertThat(jdbcTemplate.queryForObject(
                "SELECT status FROM batch_ocr_jobs WHERE job_id = ?",
                String.class,
                currentJobId[0])).isEqualTo("FAILED");
        org.assertj.core.api.Assertions.assertThat(jdbcTemplate.queryForObject(
                "SELECT progress FROM batch_ocr_jobs WHERE job_id = ?",
                Integer.class,
                currentJobId[0])).isEqualTo(50);

        mockMvc.perform(multipart("/api/v1/ocr/batches/{jobId}/items/{itemIndex}/retry", currentJobId[0], 1)
                        .file(new MockMultipartFile("file", "retry.png", "image/png", validPng()))
                        .param("language", "eng")
                        .param("saveToHistory", "true")
                        .header(HttpHeaders.AUTHORIZATION, token))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.status").value("SUCCESS"))
                .andExpect(jsonPath("$.data.progress").value(100));

        org.assertj.core.api.Assertions.assertThat(jdbcTemplate.queryForObject(
                "SELECT status FROM batch_ocr_jobs WHERE job_id = ?",
                String.class,
                currentJobId[0])).isEqualTo("SUCCESS");
        org.assertj.core.api.Assertions.assertThat(jdbcTemplate.queryForObject(
                "SELECT progress FROM batch_ocr_jobs WHERE job_id = ?",
                Integer.class,
                currentJobId[0])).isEqualTo(100);
    }

    @Test
    void queuedBatchJobCanBeCanceledByOwnerAndCanceledItemsCannotBeRetried() throws Exception {
        String ownerPassword = testPassword();
        String otherPassword = testPassword();
        register("batch-cancel-owner", ownerPassword);
        register("batch-cancel-other", otherPassword);
        String jobId = "batch-cancel-" + UUID.randomUUID();
        Long ownerId = userId("batch-cancel-owner");

        jdbcTemplate.update("""
                        INSERT INTO batch_ocr_jobs (job_id, user_id, status, progress, created_at, updated_at)
                        VALUES (?, ?, 'QUEUED', 0, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
                        """,
                jobId,
                ownerId);
        jdbcTemplate.update("""
                        INSERT INTO batch_ocr_items
                            (job_id, item_index, file_name, status, record_id, error_code, failure_reason, retry_count, updated_at)
                        VALUES (?, 0, 'queued.png', 'QUEUED', NULL, NULL, NULL, 0, CURRENT_TIMESTAMP)
                        """,
                jobId);
        jdbcTemplate.update("""
                        INSERT INTO batch_ocr_items
                            (job_id, item_index, file_name, status, record_id, error_code, failure_reason, retry_count, updated_at)
                        VALUES (?, 1, 'running.png', 'RUNNING', NULL, NULL, NULL, 0, CURRENT_TIMESTAMP)
                        """,
                jobId);

        mockMvc.perform(post("/api/v1/ocr/batches/{jobId}/cancel", jobId)
                        .header(HttpHeaders.AUTHORIZATION, bearer(accessToken("batch-cancel-other", otherPassword))))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.code").value("NOT_FOUND"));

        mockMvc.perform(post("/api/v1/ocr/batches/{jobId}/cancel", jobId)
                        .header(HttpHeaders.AUTHORIZATION, bearer(accessToken("batch-cancel-owner", ownerPassword))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.status").value("CANCELED"))
                .andExpect(jsonPath("$.data.progress").value(0))
                .andExpect(jsonPath("$.data.items[0].status").value("CANCELED"))
                .andExpect(jsonPath("$.data.items[1].status").value("CANCELED"));

        mockMvc.perform(multipart("/api/v1/ocr/batches/{jobId}/items/{itemIndex}/retry", jobId, 0)
                        .file(new MockMultipartFile("file", "retry.png", "image/png", validPng()))
                        .header(HttpHeaders.AUTHORIZATION, bearer(accessToken("batch-cancel-owner", ownerPassword))))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("VALIDATION_ERROR"));

        org.assertj.core.api.Assertions.assertThat(jdbcTemplate.queryForObject(
                "SELECT status FROM batch_ocr_jobs WHERE job_id = ?",
                String.class,
                jobId)).isEqualTo("CANCELED");
        org.assertj.core.api.Assertions.assertThat(jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM batch_ocr_items WHERE job_id = ? AND status = 'CANCELED'",
                Long.class,
                jobId)).isEqualTo(2L);
    }

    @Test
    void freeMembershipRejectsBatchAboveConcurrencyLimitBeforeProviderRuns() throws Exception {
        String password = testPassword();
        register("alice", password);

        mockMvc.perform(multipart("/api/v1/ocr/batches")
                        .file(new MockMultipartFile("files", "first.png", "image/png", validPng()))
                        .file(new MockMultipartFile("files", "second.png", "image/png", validPng()))
                        .file(new MockMultipartFile("files", "third.png", "image/png", validPng()))
                        .param("language", "eng")
                        .header(HttpHeaders.AUTHORIZATION, bearer(accessToken("alice", password))))
                .andExpect(status().isTooManyRequests())
                .andExpect(jsonPath("$.success").value(false))
                .andExpect(jsonPath("$.code").value("QUOTA_EXCEEDED"));

        verify(ocrProvider, never()).recognize(any());
    }

    private void register(String username, String password) throws Exception {
        mockMvc.perform(post("/api/v1/auth/register")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(Map.of(
                                "username", username,
                                "password", password,
                                "nickname", username))))
                .andExpect(status().isOk());
    }

    private String accessToken(String username, String password) throws Exception {
        MvcResult result = mockMvc.perform(post("/api/v1/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(Map.of(
                                "username", username,
                                "password", password,
                                "deviceId", "test-device",
                                "deviceName", "JUnit"))))
                .andExpect(status().isOk())
                .andReturn();
        return objectMapper.readTree(result.getResponse().getContentAsString())
                .path("data")
                .path("accessToken")
                .asText();
    }

    private String testPassword() {
        return "test-" + UUID.randomUUID();
    }

    private String latestBatchJobIdForUser(String username) {
        return jdbcTemplate.queryForObject("""
                        SELECT bj.job_id
                        FROM batch_ocr_jobs bj
                        JOIN users u ON bj.user_id = u.id
                        WHERE u.username = ?
                        ORDER BY bj.created_at DESC
                        LIMIT 1
                        """,
                String.class,
                username);
    }

    private Long userId(String username) {
        return jdbcTemplate.queryForObject("SELECT id FROM users WHERE username = ?", Long.class, username);
    }

    private Long insertRecord(Long userId, String title, String sourceType, String rawText, String editedText) {
        jdbcTemplate.update("""
                INSERT INTO recognition_records
                    (user_id, title, source_type, raw_text, edited_text, favorite, deleted, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, 0, 0, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
                """, userId, title, sourceType, rawText, editedText);
        return jdbcTemplate.queryForObject("SELECT MAX(id) FROM recognition_records", Long.class);
    }

    private MockMultipartFile pngFile() {
        return new MockMultipartFile("file", "v1-ocr-test-123.png", "image/png", validPng());
    }

    private byte[] validPng() {
        return new byte[]{
                (byte) 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
                0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52
        };
    }

    private String bearer(String token) {
        return "Bearer " + token;
    }
}
