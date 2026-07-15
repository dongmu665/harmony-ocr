package com.harmonyocr.ocr;

import com.harmonyocr.common.error.BusinessException;
import com.harmonyocr.common.error.ErrorCode;
import com.harmonyocr.membership.service.MembershipService;
import com.harmonyocr.ocr.config.OcrProperties;
import com.harmonyocr.ocr.config.PdfOcrProperties;
import com.harmonyocr.ocr.dto.OcrRequest;
import com.harmonyocr.ocr.dto.OcrResult;
import com.harmonyocr.ocr.dto.OcrTextBlockResponse;
import com.harmonyocr.ocr.dto.PdfOcrRecognizeResponse;
import com.harmonyocr.ocr.provider.OcrProvider;
import com.harmonyocr.ocr.service.PdfOcrRecognitionService;
import java.awt.Color;
import java.awt.Graphics2D;
import java.awt.image.BufferedImage;
import java.io.ByteArrayOutputStream;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Base64;
import java.util.List;
import org.apache.pdfbox.pdmodel.PDDocument;
import org.apache.pdfbox.pdmodel.PDPage;
import org.apache.pdfbox.pdmodel.PDPageContentStream;
import org.apache.pdfbox.pdmodel.common.PDRectangle;
import org.apache.pdfbox.pdmodel.encryption.AccessPermission;
import org.apache.pdfbox.pdmodel.encryption.StandardProtectionPolicy;
import org.apache.pdfbox.pdmodel.graphics.image.LosslessFactory;
import org.apache.pdfbox.pdmodel.graphics.image.PDImageXObject;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.mock.web.MockMultipartFile;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
/**
 * PDF OCR 识别服务单元测试。
 * 维护说明：验证 PDF 页数/大小/加密校验、逐页 OCR、部分失败和历史保存逻辑，不依赖真实用户文件。
 */
class PdfOcrRecognitionServiceTest {

    private static final Long USER_ID = 1001L;

    @Mock
    private OcrProvider ocrProvider;

    @Mock
    private MembershipService membershipService;

    private PdfOcrRecognitionService service;

    @BeforeEach
    void setUp() {
        service = new PdfOcrRecognitionService(
                ocrProvider,
                new OcrProperties(true, "fake", "fake", "eng", 15000, 10 * 1024 * 1024L, "", ""),
                new PdfOcrProperties(10 * 1024 * 1024L, 2, 72, 5_000_000L, false),
                membershipService,
                null);
    }

    @Test
    void emptyFileRejectedBeforeProviderRuns() {
        MockMultipartFile file = new MockMultipartFile("file", "empty.pdf", "application/pdf", new byte[0]);

        assertThatThrownBy(() -> service.recognize(USER_ID, file, "eng", false, null))
                .isInstanceOf(BusinessException.class)
                .extracting("errorCode")
                .isEqualTo(ErrorCode.VALIDATION_ERROR);

        verify(ocrProvider, never()).recognize(any());
    }

    @Test
    void nonPdfContentTypeRejectedBeforeProviderRuns() {
        MockMultipartFile file = new MockMultipartFile("file", "note.txt", "text/plain", "hello".getBytes(StandardCharsets.UTF_8));

        assertThatThrownBy(() -> service.recognize(USER_ID, file, "eng", false, null))
                .isInstanceOf(BusinessException.class)
                .extracting("errorCode")
                .isEqualTo(ErrorCode.FILE_TYPE_NOT_ALLOWED);

        verify(ocrProvider, never()).recognize(any());
    }

    @Test
    void pdfMimeWithNonPdfSignatureRejectedBeforeProviderRuns() {
        MockMultipartFile file = new MockMultipartFile("file", "fake.pdf", "application/pdf", "not pdf".getBytes(StandardCharsets.UTF_8));

        assertThatThrownBy(() -> service.recognize(USER_ID, file, "eng", false, null))
                .isInstanceOf(BusinessException.class)
                .extracting("errorCode")
                .isEqualTo(ErrorCode.FILE_TYPE_NOT_ALLOWED);

        verify(ocrProvider, never()).recognize(any());
    }

    @Test
    void encryptedPdfRejectedByDefault() throws Exception {
        MockMultipartFile file = pdfFile(encryptedPdfBytes(1));

        assertThatThrownBy(() -> service.recognize(USER_ID, file, "eng", false, null))
                .isInstanceOf(BusinessException.class)
                .extracting("errorCode")
                .isEqualTo(ErrorCode.PDF_ENCRYPTED);

        verify(ocrProvider, never()).recognize(any());
    }

    @Test
    void tooManyPagesRejectedBeforeQuotaOrProviderRuns() throws Exception {
        MockMultipartFile file = pdfFile(scannedPdfBytes(3));

        assertThatThrownBy(() -> service.recognize(USER_ID, file, "eng", false, null))
                .isInstanceOf(BusinessException.class)
                .extracting("errorCode")
                .isEqualTo(ErrorCode.PDF_TOO_MANY_PAGES);

        verify(membershipService, never()).consume(any(), any());
        verify(ocrProvider, never()).recognize(any());
    }

    @Test
    void onePageScannedPdfRendersAndCallsProviderOnce() throws Exception {
        when(ocrProvider.recognize(any(OcrRequest.class))).thenReturn(result("page-1-text", 11, "pdf-page-1"));

        PdfOcrRecognizeResponse response = service.recognize(USER_ID, pdfFile(scannedPdfBytes(1)), "eng", false, null);

        assertThat(response.pageCount()).isEqualTo(1);
        assertThat(response.successPageCount()).isEqualTo(1);
        assertThat(response.failedPageCount()).isZero();
        assertThat(response.rawText()).isEqualTo("page-1-text");
        assertThat(response.mode()).isEqualTo("pdf");
        assertThat(response.partial()).isFalse();
        assertThat(response.pages()).hasSize(1);
        assertThat(response.pages().getFirst().pageNumber()).isEqualTo(1);
        assertThat(response.pages().getFirst().status()).isEqualTo("SUCCESS");
        assertThat(response.pages().getFirst().previewContentType()).isEqualTo("image/png");
        assertThat(decodedPreview(response.pages().getFirst().previewImageBase64())).startsWith(pngMagic());

        ArgumentCaptor<OcrRequest> requestCaptor = ArgumentCaptor.forClass(OcrRequest.class);
        verify(membershipService).consume(USER_ID, "OCR");
        verify(ocrProvider).recognize(requestCaptor.capture());
        assertThat(requestCaptor.getValue().contentType()).isEqualTo("image/png");
        assertThat(requestCaptor.getValue().mode()).isEqualTo("pdf-page-1");
        assertThat(requestCaptor.getValue().content()).isNotEmpty();
    }

    @Test
    void multiPageScannedPdfCallsProviderForEachPageAndAggregatesInOrder() throws Exception {
        when(ocrProvider.recognize(any(OcrRequest.class)))
                .thenReturn(result("page-1-text", 10, "pdf-page-1"))
                .thenReturn(result("page-2-text", 20, "pdf-page-2"));

        PdfOcrRecognizeResponse response = service.recognize(USER_ID, pdfFile(scannedPdfBytes(2)), "eng", false, null);

        assertThat(response.pageCount()).isEqualTo(2);
        assertThat(response.successPageCount()).isEqualTo(2);
        assertThat(response.rawText()).isEqualTo("page-1-text\n\npage-2-text");
        assertThat(response.pages()).extracting("pageNumber").containsExactly(1, 2);
        assertThat(response.pages()).allSatisfy(page -> {
            assertThat(page.previewContentType()).isEqualTo("image/png");
            assertThat(decodedPreview(page.previewImageBase64())).startsWith(pngMagic());
        });

        verify(membershipService, times(2)).consume(USER_ID, "OCR");
        verify(ocrProvider, times(2)).recognize(any(OcrRequest.class));
    }

    @Test
    void onePageOcrFailureReturnsPartialResultWithoutFakeSuccess() throws Exception {
        when(ocrProvider.recognize(any(OcrRequest.class)))
                .thenReturn(result("page-1-text", 10, "pdf-page-1"))
                .thenThrow(new BusinessException(ErrorCode.OCR_FAILED, "provider text should be sanitized"));

        PdfOcrRecognizeResponse response = service.recognize(USER_ID, pdfFile(scannedPdfBytes(2)), "eng", false, null);

        assertThat(response.partial()).isTrue();
        assertThat(response.successPageCount()).isEqualTo(1);
        assertThat(response.failedPageCount()).isEqualTo(1);
        assertThat(response.rawText()).isEqualTo("page-1-text");
        assertThat(response.pages().get(0).status()).isEqualTo("SUCCESS");
        assertThat(response.pages().get(1).status()).isEqualTo("FAILED");
        assertThat(response.pages().get(1).errorCode()).isEqualTo("OCR_FAILED");
        assertThat(response.pages().get(1).rawText()).isEmpty();
        assertThat(response.pages().get(1).failureReason()).doesNotContain("provider text");
    }

    @Test
    void providerLinkageFailureReturnsPageFailureInsteadOfEscaping() throws Exception {
        when(ocrProvider.recognize(any(OcrRequest.class)))
                .thenThrow(new NoClassDefFoundError("missing-provider-runtime"));

        PdfOcrRecognizeResponse response = service.recognize(USER_ID, pdfFile(scannedPdfBytes(1)), "eng", false, null);

        assertThat(response.successPageCount()).isZero();
        assertThat(response.failedPageCount()).isEqualTo(1);
        assertThat(response.errorCode()).isEqualTo("OCR_FAILED");
        assertThat(response.pages().getFirst().status()).isEqualTo("FAILED");
        assertThat(response.pages().getFirst().errorCode()).isEqualTo("OCR_FAILED");
        assertThat(response.pages().getFirst().failureReason()).doesNotContain("missing-provider-runtime");
    }

    @Test
    void quotaFailureStopsRemainingProviderCallsAndMarksPagesFailed() throws Exception {
        doThrow(new BusinessException(ErrorCode.QUOTA_EXCEEDED, "OCR quota exceeded"))
                .when(membershipService).consume(USER_ID, "OCR");

        PdfOcrRecognizeResponse response = service.recognize(USER_ID, pdfFile(scannedPdfBytes(2)), "eng", false, null);

        assertThat(response.successPageCount()).isZero();
        assertThat(response.failedPageCount()).isEqualTo(2);
        assertThat(response.pages()).extracting("errorCode").containsExactly("QUOTA_EXCEEDED", "QUOTA_EXCEEDED");
        verify(ocrProvider, never()).recognize(any());
    }

    private MockMultipartFile pdfFile(byte[] content) {
        return new MockMultipartFile("file", "scan.pdf", "application/pdf", content);
    }

    private byte[] decodedPreview(String previewImageBase64) {
        assertThat(previewImageBase64).isNotBlank();
        return Base64.getDecoder().decode(previewImageBase64);
    }

    private byte[] pngMagic() {
        return new byte[]{(byte) 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A};
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
                addScannedPage(document, i + 1);
            }
            document.save(out);
            return out.toByteArray();
        }
    }

    private byte[] encryptedPdfBytes(int pages) throws Exception {
        try (PDDocument document = new PDDocument();
             ByteArrayOutputStream out = new ByteArrayOutputStream()) {
            for (int i = 0; i < pages; i++) {
                addScannedPage(document, i + 1);
            }
            AccessPermission permission = new AccessPermission();
            StandardProtectionPolicy policy = new StandardProtectionPolicy("owner-password", "user-password", permission);
            policy.setEncryptionKeyLength(128);
            document.protect(policy);
            document.save(out);
            return out.toByteArray();
        }
    }

    private void addScannedPage(PDDocument document, int pageNumber) throws Exception {
        PDPage page = new PDPage(PDRectangle.A6);
        document.addPage(page);
        BufferedImage image = new BufferedImage(160, 80, BufferedImage.TYPE_INT_RGB);
        Graphics2D graphics = image.createGraphics();
        try {
            graphics.setColor(Color.WHITE);
            graphics.fillRect(0, 0, image.getWidth(), image.getHeight());
            graphics.setColor(Color.BLACK);
            graphics.drawString("page " + pageNumber, 16, 40);
        } finally {
            graphics.dispose();
        }
        PDImageXObject xObject = LosslessFactory.createFromImage(document, image);
        try (PDPageContentStream contentStream = new PDPageContentStream(document, page)) {
            contentStream.drawImage(xObject, 20, 120, 160, 80);
        }
    }
}
