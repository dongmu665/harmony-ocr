package com.harmonyocr.ocr.service;

import com.harmonyocr.common.error.BusinessException;
import com.harmonyocr.common.error.ErrorCode;
import com.harmonyocr.file.validation.FileTypeDetector;
import com.harmonyocr.membership.service.MembershipService;
import com.harmonyocr.ocr.config.OcrProperties;
import com.harmonyocr.ocr.config.PdfOcrProperties;
import com.harmonyocr.ocr.dto.OcrRequest;
import com.harmonyocr.ocr.dto.OcrResult;
import com.harmonyocr.ocr.dto.OcrTextBlockResponse;
import com.harmonyocr.ocr.dto.PdfOcrPageResult;
import com.harmonyocr.ocr.dto.PdfOcrRecognizeResponse;
import com.harmonyocr.ocr.provider.OcrFailoverProvider;
import com.harmonyocr.ocr.provider.OcrProvider;
import com.harmonyocr.record.dto.CreateRecordRequest;
import com.harmonyocr.record.dto.RecordBlockRequest;
import com.harmonyocr.record.dto.RecordPageRequest;
import com.harmonyocr.record.dto.RecordResponse;
import com.harmonyocr.record.service.RecordService;
import java.awt.image.BufferedImage;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.Base64;
import java.util.List;
import java.util.Locale;
import javax.imageio.ImageIO;
import org.apache.pdfbox.Loader;
import org.apache.pdfbox.pdmodel.PDDocument;
import org.apache.pdfbox.pdmodel.PDPage;
import org.apache.pdfbox.pdmodel.common.PDRectangle;
import org.apache.pdfbox.rendering.PDFRenderer;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.core.env.Environment;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;

/**
 * 扫描型 PDF OCR 服务，属于 ocr 模块。
 * 维护说明：PDF 只在内存中校验和渲染，逐页转为图片后复用现有 OCR Provider，不保存 PDF 原文、渲染图片或本地路径。
 */
@Service
public class PdfOcrRecognitionService {

    private static final String PDF_CONTENT_TYPE = "application/pdf";
    private static final String RENDERED_CONTENT_TYPE = "image/png";
    private static final String MODE_PDF = "pdf";
    private static final String PAGE_SUCCESS = "SUCCESS";
    private static final String PAGE_FAILED = "FAILED";
    private static final int PREVIEW_RENDER_DPI = 72;

    private final OcrProvider ocrProvider;
    private final OcrProperties ocrProperties;
    private final PdfOcrProperties pdfProperties;
    private final MembershipService membershipService;
    private final RecordService recordService;

    @Autowired
    public PdfOcrRecognitionService(
            List<OcrProvider> ocrProviders,
            OcrProperties ocrProperties,
            PdfOcrProperties pdfProperties,
            MembershipService membershipService,
            RecordService recordService,
            Environment environment) {
        this(
                selectProvider(ocrProviders, environment),
                ocrProperties,
                pdfProperties,
                membershipService,
                recordService);
    }

    public PdfOcrRecognitionService(
            OcrProvider ocrProvider,
            OcrProperties ocrProperties,
            PdfOcrProperties pdfProperties,
            MembershipService membershipService,
            RecordService recordService) {
        this.ocrProvider = ocrProvider;
        this.ocrProperties = ocrProperties;
        this.pdfProperties = pdfProperties;
        this.membershipService = membershipService;
        this.recordService = recordService;
    }

    /**
     * 识别 multipart PDF。
     * 参数 userId 来自认证上下文，file 必须为扫描型 PDF；saveToHistory=true 时保存聚合文本和页级结果，不保存 PDF 文件。
     */
    public PdfOcrRecognizeResponse recognize(
            Long userId,
            MultipartFile file,
            String language,
            boolean saveToHistory,
            Integer maxPages) {
        byte[] content = validateAndReadPdf(file);
        String normalizedLanguage = language == null || language.isBlank() ? ocrProperties.language() : language;
        long startedAt = System.currentTimeMillis();
        try (PDDocument document = loadDocument(content)) {
            if (document.isEncrypted() && !pdfProperties.allowEncrypted()) {
                throw new BusinessException(ErrorCode.PDF_ENCRYPTED);
            }
            int pageCount = document.getNumberOfPages();
            int effectiveMaxPages = effectiveMaxPages(maxPages);
            if (pageCount <= 0) {
                throw new BusinessException(ErrorCode.PDF_INVALID, "PDF has no pages");
            }
            if (pageCount > effectiveMaxPages) {
                throw new BusinessException(ErrorCode.PDF_TOO_MANY_PAGES);
            }
            PDFRenderer renderer = new PDFRenderer(document);
            List<PdfOcrPageResult> pages = recognizePages(userId, document, renderer, normalizedLanguage);
            PdfOcrRecognizeResponse response = toResponse(pages, pageCount, normalizedLanguage, startedAt, null);
            if (saveToHistory && recordService != null) {
                RecordResponse record = recordService.create(userId, toCreateRecordRequest(response));
                return withRecordId(response, record.id());
            }
            return response;
        } catch (BusinessException ex) {
            throw ex;
        } catch (IOException ex) {
            throw new BusinessException(ErrorCode.PDF_INVALID);
        }
    }

    private List<PdfOcrPageResult> recognizePages(
            Long userId,
            PDDocument document,
            PDFRenderer renderer,
            String language) {
        List<PdfOcrPageResult> pages = new ArrayList<>();
        for (int pageIndex = 0; pageIndex < document.getNumberOfPages(); pageIndex++) {
            int pageNumber = pageIndex + 1;
            try {
                membershipService.consume(userId, "OCR");
            } catch (BusinessException ex) {
                if (ex.getErrorCode() == ErrorCode.QUOTA_EXCEEDED) {
                    addRemainingQuotaFailures(pages, pageIndex, document.getNumberOfPages());
                    break;
                }
                throw ex;
            }
            pages.add(recognizePage(document, renderer, pageIndex, pageNumber, language));
        }
        return pages;
    }

    private PdfOcrPageResult recognizePage(
            PDDocument document,
            PDFRenderer renderer,
            int pageIndex,
            int pageNumber,
            String language) {
        long startedAt = System.currentTimeMillis();
        String previewImageBase64 = "";
        String previewContentType = null;
        try {
            ensurePagePixelLimit(document.getPage(pageIndex));
            previewImageBase64 = renderPreviewImageBase64(renderer, pageIndex);
            previewContentType = previewImageBase64.isBlank() ? null : RENDERED_CONTENT_TYPE;
            byte[] imageBytes = renderPage(renderer, pageIndex);
            OcrResult result;
            try {
                result = recognizeRenderedImage(imageBytes, language, pageNumber);
            } catch (BusinessException ex) {
                return failedPage(
                        pageIndex,
                        pageNumber,
                        ex.getErrorCode(),
                        System.currentTimeMillis() - startedAt,
                        previewImageBase64,
                        previewContentType);
            }
            String rawText = normalizeText(result.rawText());
            return new PdfOcrPageResult(
                    pageIndex,
                    pageNumber,
                    PAGE_SUCCESS,
                    rawText,
                    rawText,
                    result.durationMs(),
                    result.confidence(),
                    result.errorCode(),
                    null,
                    previewImageBase64,
                    previewContentType,
                    safeBlocks(result.blocks()));
        } catch (BusinessException ex) {
            return failedPage(
                    pageIndex,
                    pageNumber,
                    ex.getErrorCode(),
                    System.currentTimeMillis() - startedAt,
                    previewImageBase64,
                    previewContentType);
        } catch (RuntimeException | IOException | LinkageError ex) {
            return failedPage(
                    pageIndex,
                    pageNumber,
                    ErrorCode.PDF_RENDER_FAILED,
                    System.currentTimeMillis() - startedAt,
                    previewImageBase64,
                    previewContentType);
        }
    }

    /**
     * 调用 OCR Provider 识别已渲染页面。
     * Provider 的运行时依赖异常不能冒泡成整份 PDF 500，统一转为页级 OCR_FAILED。
     */
    private OcrResult recognizeRenderedImage(byte[] imageBytes, String language, int pageNumber) {
        try {
            return ocrProvider.recognize(new OcrRequest(
                    imageBytes,
                    RENDERED_CONTENT_TYPE,
                    language,
                    "pdf-page-" + pageNumber));
        } catch (BusinessException ex) {
            throw ex;
        } catch (RuntimeException | LinkageError ex) {
            throw new BusinessException(ErrorCode.OCR_FAILED);
        }
    }

    private byte[] validateAndReadPdf(MultipartFile file) {
        if (file == null || file.isEmpty()) {
            throw new BusinessException(ErrorCode.VALIDATION_ERROR, "file must not be empty");
        }
        String contentType = normalizedContentType(file.getContentType());
        if (!PDF_CONTENT_TYPE.equals(contentType)) {
            throw new BusinessException(ErrorCode.FILE_TYPE_NOT_ALLOWED);
        }
        if (file.getSize() > pdfProperties.maxSizeBytes()) {
            throw new BusinessException(ErrorCode.FILE_TOO_LARGE);
        }
        try {
            byte[] content = file.getBytes();
            FileTypeDetector.requireContentMatches(PDF_CONTENT_TYPE, content);
            return content;
        } catch (BusinessException ex) {
            throw ex;
        } catch (IOException ex) {
            throw new BusinessException(ErrorCode.PDF_INVALID);
        }
    }

    private PDDocument loadDocument(byte[] content) {
        try {
            return Loader.loadPDF(content);
        } catch (org.apache.pdfbox.pdmodel.encryption.InvalidPasswordException ex) {
            throw new BusinessException(ErrorCode.PDF_ENCRYPTED);
        } catch (IOException ex) {
            throw new BusinessException(ErrorCode.PDF_INVALID);
        }
    }

    private int effectiveMaxPages(Integer requestedMaxPages) {
        if (requestedMaxPages == null) {
            return pdfProperties.maxPages();
        }
        if (requestedMaxPages <= 0 || requestedMaxPages > pdfProperties.maxPages()) {
            throw new BusinessException(ErrorCode.VALIDATION_ERROR, "maxPages exceeds configured limit");
        }
        return requestedMaxPages;
    }

    private void ensurePagePixelLimit(PDPage page) {
        PDRectangle box = page.getCropBox() == null ? page.getMediaBox() : page.getCropBox();
        double scale = pdfProperties.renderDpi() / 72.0d;
        long width = (long) Math.ceil(box.getWidth() * scale);
        long height = (long) Math.ceil(box.getHeight() * scale);
        if (width <= 0 || height <= 0 || width * height > pdfProperties.maxRenderedPixels()) {
            throw new BusinessException(ErrorCode.PDF_RENDER_FAILED);
        }
    }

    private byte[] renderPage(PDFRenderer renderer, int pageIndex) throws IOException {
        BufferedImage image = renderer.renderImageWithDPI(pageIndex, pdfProperties.renderDpi());
        return encodePng(image);
    }

    /**
     * 生成结果页使用的低 DPI PNG 预览。
     * 该预览只作为当前响应的脱敏页面图像，不复用高 DPI OCR 图片，避免响应体过大。
     */
    private String renderPreviewImageBase64(PDFRenderer renderer, int pageIndex) throws IOException {
        BufferedImage image = renderer.renderImageWithDPI(pageIndex, PREVIEW_RENDER_DPI);
        return Base64.getEncoder().encodeToString(encodePng(image));
    }

    private byte[] encodePng(BufferedImage image) throws IOException {
        try (ByteArrayOutputStream out = new ByteArrayOutputStream()) {
            boolean written = ImageIO.write(image, "png", out);
            if (!written || out.size() == 0) {
                throw new BusinessException(ErrorCode.PDF_RENDER_FAILED);
            }
            return out.toByteArray();
        }
    }

    private void addRemainingQuotaFailures(List<PdfOcrPageResult> pages, int startPageIndex, int pageCount) {
        for (int index = startPageIndex; index < pageCount; index++) {
            pages.add(failedPage(index, index + 1, ErrorCode.QUOTA_EXCEEDED, 0, "", null));
        }
    }

    private PdfOcrPageResult failedPage(int pageIndex, int pageNumber, ErrorCode errorCode, long durationMs) {
        return failedPage(pageIndex, pageNumber, errorCode, durationMs, "", null);
    }

    private PdfOcrPageResult failedPage(
            int pageIndex,
            int pageNumber,
            ErrorCode errorCode,
            long durationMs,
            String previewImageBase64,
            String previewContentType) {
        return new PdfOcrPageResult(
                pageIndex,
                pageNumber,
                PAGE_FAILED,
                "",
                "",
                durationMs,
                null,
                errorCode.getCode(),
                failureReason(errorCode),
                previewImageBase64 == null ? "" : previewImageBase64,
                previewContentType,
                List.of());
    }

    private PdfOcrRecognizeResponse toResponse(
            List<PdfOcrPageResult> pages,
            int pageCount,
            String language,
            long startedAt,
            Long recordId) {
        List<String> successTexts = pages.stream()
                .filter(page -> PAGE_SUCCESS.equals(page.status()))
                .map(PdfOcrPageResult::rawText)
                .filter(text -> text != null && !text.isBlank())
                .toList();
        String rawText = String.join("\n\n", successTexts);
        int successCount = (int) pages.stream().filter(page -> PAGE_SUCCESS.equals(page.status())).count();
        int failedCount = (int) pages.stream().filter(page -> PAGE_FAILED.equals(page.status())).count();
        return new PdfOcrRecognizeResponse(
                rawText,
                rawText,
                pageCount,
                successCount,
                failedCount,
                System.currentTimeMillis() - startedAt,
                language,
                blankToDefault(ocrProvider.providerName(), "unknown"),
                blankToDefault(ocrProvider.engineName(), "unknown"),
                MODE_PDF,
                pages,
                successCount == 0 && failedCount > 0 ? firstErrorCode(pages) : null,
                successCount > 0 && failedCount > 0,
                recordId);
    }

    private PdfOcrRecognizeResponse withRecordId(PdfOcrRecognizeResponse response, Long recordId) {
        return new PdfOcrRecognizeResponse(
                response.rawText(),
                response.editedText(),
                response.pageCount(),
                response.successPageCount(),
                response.failedPageCount(),
                response.durationMs(),
                response.language(),
                response.providerName(),
                response.engineName(),
                response.mode(),
                response.pages(),
                response.errorCode(),
                response.partial(),
                recordId);
    }

    private CreateRecordRequest toCreateRecordRequest(PdfOcrRecognizeResponse response) {
        return new CreateRecordRequest(
                "PDF OCR",
                "pdf",
                null,
                response.rawText(),
                response.editedText(),
                response.language(),
                response.engineName(),
                Math.toIntExact(Math.min(response.durationMs(), Integer.MAX_VALUE)),
                false,
                List.of(),
                response.pages().stream().map(this::toRecordPageRequest).toList());
    }

    private RecordPageRequest toRecordPageRequest(PdfOcrPageResult page) {
        return new RecordPageRequest(
                page.pageIndex(),
                page.pageNumber(),
                page.status(),
                page.rawText(),
                page.editedText(),
                Math.toIntExact(Math.min(page.durationMs(), Integer.MAX_VALUE)),
                page.confidence(),
                page.errorCode(),
                page.failureReason(),
                page.blocks().stream().map(this::toRecordBlockRequest).toList());
    }

    private RecordBlockRequest toRecordBlockRequest(OcrTextBlockResponse block) {
        return new RecordBlockRequest(
                block.order(),
                block.text(),
                block.confidence() == null ? null : BigDecimal.valueOf(block.confidence()),
                block.boundingBox());
    }

    private String normalizedContentType(String contentType) {
        if (contentType == null || contentType.isBlank()) {
            throw new BusinessException(ErrorCode.FILE_TYPE_NOT_ALLOWED);
        }
        return contentType.trim().toLowerCase(Locale.ROOT);
    }

    private String normalizeText(String text) {
        return text == null ? "" : text.trim();
    }

    private List<OcrTextBlockResponse> safeBlocks(List<OcrTextBlockResponse> blocks) {
        return blocks == null ? List.of() : blocks;
    }

    private String firstErrorCode(List<PdfOcrPageResult> pages) {
        return pages.stream()
                .map(PdfOcrPageResult::errorCode)
                .filter(code -> code != null && !code.isBlank())
                .findFirst()
                .orElse(ErrorCode.OCR_FAILED.getCode());
    }

    private String failureReason(ErrorCode errorCode) {
        return switch (errorCode) {
            case QUOTA_EXCEEDED -> "OCR 额度不足，后续页面未继续识别";
            case OCR_TIMEOUT -> "该页识别超时，请稍后重试";
            case OCR_FAILED -> "该页识别失败，请稍后重试";
            case PDF_RENDER_FAILED -> "该页渲染失败，请检查 PDF 页面内容";
            default -> "该页处理失败，请稍后重试";
        };
    }

    private String blankToDefault(String value, String defaultValue) {
        return value == null || value.isBlank() ? defaultValue : value;
    }

    private static OcrProvider selectProvider(List<OcrProvider> ocrProviders, Environment environment) {
        if (ocrProviders == null || ocrProviders.isEmpty()) {
            throw new BusinessException(ErrorCode.OCR_FAILED, "OCR provider is not configured");
        }
        boolean failoverEnabled = environment != null
                && environment.getProperty("app.ocr.failover-enabled", Boolean.class, false);
        if (failoverEnabled && ocrProviders.size() > 1) {
            return new OcrFailoverProvider(ocrProviders);
        }
        return ocrProviders.getFirst();
    }
}
