package com.harmonyocr.ocr;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.harmonyocr.ocr.dto.OcrRequest;
import com.harmonyocr.ocr.dto.OcrResult;
import com.harmonyocr.ocr.dto.OcrTextBlockResponse;
import com.harmonyocr.ocr.provider.OcrProvider;
import java.awt.Color;
import java.awt.Graphics2D;
import java.awt.image.BufferedImage;
import java.io.ByteArrayOutputStream;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.apache.pdfbox.pdmodel.PDDocument;
import org.apache.pdfbox.pdmodel.PDPage;
import org.apache.pdfbox.pdmodel.PDPageContentStream;
import org.apache.pdfbox.pdmodel.common.PDRectangle;
import org.apache.pdfbox.pdmodel.graphics.image.LosslessFactory;
import org.apache.pdfbox.pdmodel.graphics.image.PDImageXObject;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
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

import static org.assertj.core.api.Assertions.assertThat;
import static org.hamcrest.Matchers.containsString;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@ActiveProfiles("test")
@AutoConfigureMockMvc
@SpringBootTest
/**
 * PDF OCR 控制器集成测试。
 * 维护说明：覆盖扫描型 PDF 上传、页级结果、历史记录保存和错误码映射，确保 PDF bytes 不落入响应或日志。
 */
class PdfOcrControllerIntegrationTest {

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
        jdbcTemplate.update("DELETE FROM recognition_record_page_blocks");
        jdbcTemplate.update("DELETE FROM recognition_record_pages");
        jdbcTemplate.update("DELETE FROM batch_ocr_items");
        jdbcTemplate.update("DELETE FROM batch_ocr_jobs");
        jdbcTemplate.update("DELETE FROM object_storage_cleanup_tasks");
        jdbcTemplate.update("DELETE FROM file_objects");
        jdbcTemplate.update("DELETE FROM recognition_record_tags");
        jdbcTemplate.update("DELETE FROM recognition_tags");
        jdbcTemplate.update("DELETE FROM recognition_blocks");
        jdbcTemplate.update("DELETE FROM recognition_records");
        jdbcTemplate.update("DELETE FROM refresh_tokens");
        jdbcTemplate.update("DELETE FROM user_devices");
        jdbcTemplate.update("DELETE FROM export_jobs");
        jdbcTemplate.update("DELETE FROM users");
    }

    @Test
    void recognizePdfRequiresAuthentication() throws Exception {
        mockMvc.perform(multipart("/api/v1/ocr/pdf/recognize")
                        .file(pdfFile(scannedPdfBytes(1))))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.success").value(false))
                .andExpect(jsonPath("$.code").value("UNAUTHORIZED"));

        verify(ocrProvider, never()).recognize(any());
    }

    @Test
    void recognizeValidPdfReturnsPageCountAndCallsProviderPerPage() throws Exception {
        String password = testPassword();
        register("pdf-user", password);
        when(ocrProvider.providerName()).thenReturn("fake-provider");
        when(ocrProvider.engineName()).thenReturn("fake-engine");
        when(ocrProvider.recognize(any(OcrRequest.class)))
                .thenReturn(result("page-1-text", 10, "pdf-page-1"))
                .thenReturn(result("page-2-text", 12, "pdf-page-2"));

        mockMvc.perform(multipart("/api/v1/ocr/pdf/recognize")
                        .file(pdfFile(scannedPdfBytes(2)))
                        .param("language", "eng")
                        .header(HttpHeaders.AUTHORIZATION, bearer(accessToken("pdf-user", password))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.success").value(true))
                .andExpect(jsonPath("$.data.mode").value("pdf"))
                .andExpect(jsonPath("$.data.pageCount").value(2))
                .andExpect(jsonPath("$.data.successPageCount").value(2))
                .andExpect(jsonPath("$.data.failedPageCount").value(0))
                .andExpect(jsonPath("$.data.rawText").value("page-1-text\n\npage-2-text"))
                .andExpect(jsonPath("$.data.pages[0].pageNumber").value(1))
                .andExpect(jsonPath("$.data.pages[0].status").value("SUCCESS"))
                .andExpect(jsonPath("$.data.pages[0].previewImageBase64").isNotEmpty())
                .andExpect(jsonPath("$.data.pages[0].previewContentType").value("image/png"))
                .andExpect(jsonPath("$.data.pages[1].pageNumber").value(2));

        ArgumentCaptor<OcrRequest> requestCaptor = ArgumentCaptor.forClass(OcrRequest.class);
        verify(ocrProvider, org.mockito.Mockito.times(2)).recognize(requestCaptor.capture());
        assertThat(requestCaptor.getAllValues()).extracting(OcrRequest::contentType)
                .containsExactly("image/png", "image/png");
        assertThat(requestCaptor.getAllValues()).extracting(OcrRequest::mode)
                .containsExactly("pdf-page-1", "pdf-page-2");
    }

    @Test
    void invalidPdfReturnsUnifiedErrorResponse() throws Exception {
        String password = testPassword();
        register("pdf-invalid", password);

        mockMvc.perform(multipart("/api/v1/ocr/pdf/recognize")
                        .file(new MockMultipartFile("file", "broken.pdf", "application/pdf", "%PDF-broken".getBytes()))
                        .header(HttpHeaders.AUTHORIZATION, bearer(accessToken("pdf-invalid", password))))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.success").value(false))
                .andExpect(jsonPath("$.code").value("PDF_INVALID"));

        verify(ocrProvider, never()).recognize(any());
    }

    @Test
    void recognizePdfSaveToHistoryCreatesPdfRecordWithPages() throws Exception {
        String password = testPassword();
        register("pdf-history", password);
        when(ocrProvider.providerName()).thenReturn("fake-provider");
        when(ocrProvider.engineName()).thenReturn("fake-engine");
        when(ocrProvider.recognize(any(OcrRequest.class)))
                .thenReturn(result("page-1-text", 10, "pdf-page-1"))
                .thenReturn(result("page-2-text", 12, "pdf-page-2"));

        MvcResult result = mockMvc.perform(multipart("/api/v1/ocr/pdf/recognize")
                        .file(pdfFile(scannedPdfBytes(2)))
                        .param("language", "eng")
                        .param("saveToHistory", "true")
                        .header(HttpHeaders.AUTHORIZATION, bearer(accessToken("pdf-history", password))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.recordId").isNumber())
                .andExpect(jsonPath("$.data.pageCount").value(2))
                .andReturn();

        long recordId = objectMapper.readTree(result.getResponse().getContentAsString())
                .path("data")
                .path("recordId")
                .asLong();

        mockMvc.perform(get("/api/v1/records/{id}", recordId)
                        .header(HttpHeaders.AUTHORIZATION, bearer(accessToken("pdf-history", password))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.sourceType").value("pdf"))
                .andExpect(jsonPath("$.data.pageCount").value(2))
                .andExpect(jsonPath("$.data.successPageCount").value(2))
                .andExpect(jsonPath("$.data.failedPageCount").value(0))
                .andExpect(jsonPath("$.data.partial").value(false))
                .andExpect(jsonPath("$.data.pages[0].pageNumber").value(1))
                .andExpect(jsonPath("$.data.pages[0].rawText").value("page-1-text"))
                .andExpect(jsonPath("$.data.pages[1].pageNumber").value(2));

        assertThat(jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM recognition_record_pages WHERE record_id = ?",
                Long.class,
                recordId)).isEqualTo(2L);
    }

    @Test
    void existingImageRecognitionStillWorksAndRejectsPdfOnImageEndpoint() throws Exception {
        String password = testPassword();
        register("image-user", password);
        String token = bearer(accessToken("image-user", password));
        when(ocrProvider.providerName()).thenReturn("fake-provider");
        when(ocrProvider.engineName()).thenReturn("fake-engine");
        when(ocrProvider.recognize(any(OcrRequest.class)))
                .thenReturn(result("image-text", 5, "single-image"));

        mockMvc.perform(multipart("/api/v1/ocr/recognize")
                        .file(new MockMultipartFile("file", "image.png", "image/png", validPng()))
                        .param("language", "eng")
                        .header(HttpHeaders.AUTHORIZATION, token))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.rawText").value("image-text"))
                .andExpect(jsonPath("$.data.mode").value("single-image"));

        mockMvc.perform(multipart("/api/v1/ocr/recognize")
                        .file(pdfFile(scannedPdfBytes(1)))
                        .header(HttpHeaders.AUTHORIZATION, token))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("FILE_TYPE_NOT_ALLOWED"));

        verify(ocrProvider).recognize(any(OcrRequest.class));
    }

    @Test
    void accountDeletionRemovesPdfPageText() throws Exception {
        String password = testPassword();
        register("pdf-delete", password);
        String token = bearer(accessToken("pdf-delete", password));
        when(ocrProvider.providerName()).thenReturn("fake-provider");
        when(ocrProvider.engineName()).thenReturn("fake-engine");
        when(ocrProvider.recognize(any(OcrRequest.class)))
                .thenReturn(result("private page text", 10, "pdf-page-1"));

        MvcResult result = mockMvc.perform(multipart("/api/v1/ocr/pdf/recognize")
                        .file(pdfFile(scannedPdfBytes(1)))
                        .param("saveToHistory", "true")
                        .header(HttpHeaders.AUTHORIZATION, token))
                .andExpect(status().isOk())
                .andReturn();
        long recordId = objectMapper.readTree(result.getResponse().getContentAsString())
                .path("data")
                .path("recordId")
                .asLong();

        mockMvc.perform(delete("/api/v1/users/me")
                        .header(HttpHeaders.AUTHORIZATION, token))
                .andExpect(status().isOk());

        assertThat(jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM recognition_record_pages WHERE record_id = ?",
                Long.class,
                recordId)).isZero();
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

    private String bearer(String token) {
        return "Bearer " + token;
    }

    private MockMultipartFile pdfFile(byte[] content) {
        return new MockMultipartFile("file", "scan.pdf", "application/pdf", content);
    }

    private OcrResult result(String text, long durationMs, String mode) {
        return new OcrResult(
                "fake-provider",
                "fake-engine",
                mode,
                text,
                durationMs,
                "eng",
                0.91,
                null,
                List.of(new OcrTextBlockResponse(1, text, 0.91, null)),
                null);
    }

    private byte[] scannedPdfBytes(int pages) throws Exception {
        try (PDDocument document = new PDDocument();
             ByteArrayOutputStream out = new ByteArrayOutputStream()) {
            for (int i = 0; i < pages; i++) {
                PDPage page = new PDPage(PDRectangle.A6);
                document.addPage(page);
                BufferedImage image = new BufferedImage(160, 80, BufferedImage.TYPE_INT_RGB);
                Graphics2D graphics = image.createGraphics();
                try {
                    graphics.setColor(Color.WHITE);
                    graphics.fillRect(0, 0, image.getWidth(), image.getHeight());
                    graphics.setColor(Color.BLACK);
                    graphics.drawString("page " + (i + 1), 16, 40);
                } finally {
                    graphics.dispose();
                }
                PDImageXObject xObject = LosslessFactory.createFromImage(document, image);
                try (PDPageContentStream contentStream = new PDPageContentStream(document, page)) {
                    contentStream.drawImage(xObject, 20, 120, 160, 80);
                }
            }
            document.save(out);
            return out.toByteArray();
        }
    }

    private byte[] validPng() {
        return new byte[]{
                (byte) 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
                0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52
        };
    }
}
