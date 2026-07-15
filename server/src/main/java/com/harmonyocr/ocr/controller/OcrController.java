package com.harmonyocr.ocr.controller;

import com.harmonyocr.auth.security.CurrentUser;
import com.harmonyocr.common.api.Result;
import com.harmonyocr.membership.service.MembershipService;
import com.harmonyocr.ocr.dto.BatchOcrJobResponse;
import com.harmonyocr.ocr.dto.BatchOcrTaskSummaryResponse;
import com.harmonyocr.ocr.dto.OcrHealthResponse;
import com.harmonyocr.ocr.dto.OcrRecognizeResponse;
import com.harmonyocr.ocr.dto.PdfOcrRecognizeResponse;
import com.harmonyocr.ocr.service.BatchOcrService;
import com.harmonyocr.ocr.service.OcrRecognitionService;
import com.harmonyocr.ocr.service.PdfOcrRecognitionService;
import java.util.List;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

/**
 * 后端 OCR 控制器，属于 ocr 模块。
 * 维护说明：控制器只编排认证用户的 OCR fallback、批量 OCR 和 Provider 健康检查，不接入 PaddleOCR runtime 或第三方云 OCR。
 */
@RestController
@RequestMapping("/api/v1/ocr")
public class OcrController {

    private final OcrRecognitionService ocrRecognitionService;
    private final PdfOcrRecognitionService pdfOcrRecognitionService;
    private final BatchOcrService batchOcrService;
    private final MembershipService membershipService;

    public OcrController(
            OcrRecognitionService ocrRecognitionService,
            PdfOcrRecognitionService pdfOcrRecognitionService,
            BatchOcrService batchOcrService,
            MembershipService membershipService) {
        this.ocrRecognitionService = ocrRecognitionService;
        this.pdfOcrRecognitionService = pdfOcrRecognitionService;
        this.batchOcrService = batchOcrService;
        this.membershipService = membershipService;
    }

    /**
     * 识别单张图片。
     * 参数 file 为 multipart 图片，language 为可选语言；返回统一 Result 包装的真实 OCR 文本。
     */
    @PostMapping("/recognize")
    public Result<OcrRecognizeResponse> recognize(
            @AuthenticationPrincipal CurrentUser currentUser,
            @RequestParam("file") MultipartFile file,
            @RequestParam(value = "language", required = false) String language) {
        membershipService.consume(currentUser.userId(), "OCR");
        return Result.success(ocrRecognitionService.recognize(file, language));
    }

    /**
     * 识别扫描型 PDF。
     * 参数 file 必须为 application/pdf；服务层会逐页渲染并按页扣减 OCR 额度，不保存 PDF 原文件。
     */
    @PostMapping("/pdf/recognize")
    public Result<PdfOcrRecognizeResponse> recognizePdf(
            @AuthenticationPrincipal CurrentUser currentUser,
            @RequestParam("file") MultipartFile file,
            @RequestParam(value = "language", required = false) String language,
            @RequestParam(value = "saveToHistory", defaultValue = "false") boolean saveToHistory,
            @RequestParam(value = "maxPages", required = false) Integer maxPages) {
        return Result.success(pdfOcrRecognitionService.recognize(
                currentUser.userId(),
                file,
                language,
                saveToHistory,
                maxPages));
    }

    /**
     * 批量识别多张图片。
     * 参数 files 为 multipart 图片数组，saveToHistory 控制成功项是否写入当前用户历史；失败项返回脱敏原因并不中断其他图片。
     */
    @PostMapping("/batches")
    public Result<BatchOcrJobResponse> createBatch(
            @AuthenticationPrincipal CurrentUser currentUser,
            @RequestParam("files") MultipartFile[] files,
            @RequestParam(value = "language", required = false) String language,
            @RequestParam(value = "saveToHistory", defaultValue = "false") boolean saveToHistory) {
        membershipService.requireBatchConcurrency(currentUser.userId(), files == null ? 0 : files.length);
        return Result.success(batchOcrService.create(currentUser.userId(), files, language, saveToHistory));
    }

    /**
     * 查询当前用户的批量 OCR 任务摘要。
     * 返回值只包含任务状态和脱敏 item 元数据，不返回 OCR 全文。
     */
    @GetMapping("/batches")
    public Result<List<BatchOcrTaskSummaryResponse>> batches(@AuthenticationPrincipal CurrentUser currentUser) {
        return Result.success(batchOcrService.listOwned(currentUser.userId()));
    }

    /**
     * 查询当前用户拥有的批量 OCR 任务详情摘要。
     * 参数 jobId 必须属于当前用户；越权任务按不存在处理。
     */
    @GetMapping("/batches/{jobId}")
    public Result<BatchOcrTaskSummaryResponse> batch(
            @AuthenticationPrincipal CurrentUser currentUser,
            @PathVariable String jobId) {
        return Result.success(batchOcrService.detailOwned(currentUser.userId(), jobId));
    }

    /**
     * 取消当前用户拥有的未完成批量 OCR 任务。
     * 仅允许取消 QUEUED/RUNNING/RETRYING 任务；越权任务仍按 NOT_FOUND 处理，避免泄露任务归属。
     */
    @PostMapping("/batches/{jobId}/cancel")
    public Result<BatchOcrJobResponse> cancelBatch(
            @AuthenticationPrincipal CurrentUser currentUser,
            @PathVariable String jobId) {
        return Result.success(batchOcrService.cancel(currentUser.userId(), jobId));
    }

    /**
     * 重试批量 OCR 中的失败 item。
     * 参数 jobId 和 itemIndex 必须属于当前用户的持久化任务；file 为用户重新上传的图片。
     */
    @PostMapping("/batches/{jobId}/items/{itemIndex}/retry")
    public Result<BatchOcrJobResponse> retryBatchItem(
            @AuthenticationPrincipal CurrentUser currentUser,
            @PathVariable String jobId,
            @PathVariable int itemIndex,
            @RequestParam("file") MultipartFile file,
            @RequestParam(value = "language", required = false) String language,
            @RequestParam(value = "saveToHistory", defaultValue = "false") boolean saveToHistory) {
        return Result.success(batchOcrService.retry(currentUser.userId(), jobId, itemIndex, file, language, saveToHistory));
    }

    /**
     * 查询 OCR Provider 健康状态。
     */
    @GetMapping("/health")
    public Result<OcrHealthResponse> health() {
        return Result.success(ocrRecognitionService.health());
    }
}
