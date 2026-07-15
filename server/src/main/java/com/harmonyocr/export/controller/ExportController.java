package com.harmonyocr.export.controller;

import com.harmonyocr.auth.security.CurrentUser;
import com.harmonyocr.common.api.Result;
import com.harmonyocr.export.dto.CreateExportRequest;
import com.harmonyocr.export.dto.CreatePdfExportRequest;
import com.harmonyocr.export.dto.ExportDownload;
import com.harmonyocr.export.dto.ExportJobResponse;
import com.harmonyocr.export.service.ExportService;
import jakarta.validation.Valid;
import java.util.List;
import org.springframework.http.ContentDisposition;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * 文档导出控制器，属于 export 模块。
 * 维护说明：控制器只开放认证用户的导出任务创建和下载入口，不接收客户端 userId、磁盘路径或对象存储 key。
 */
@RestController
@RequestMapping("/api/v1/exports")
public class ExportController {

    private final ExportService exportService;

    public ExportController(ExportService exportService) {
        this.exportService = exportService;
    }

    /**
     * 创建 TXT、Markdown、JSON、PDF 或 searchable PDF 导出任务。
     * 参数 request 只包含记录 ID、格式和展示文件名；记录归属和格式安全由服务层校验。
     */
    @PostMapping
    public Result<ExportJobResponse> create(
            @AuthenticationPrincipal CurrentUser currentUser,
            @Valid @RequestBody CreateExportRequest request) {
        return Result.success(exportService.create(currentUser.userId(), request));
    }

    /**
     * 创建 PDF 或 searchable PDF 导出任务。
     * 参数 request 只包含记录 ID、文件名和 searchable 意图；所有记录归属由服务层按当前用户校验。
     */
    @PostMapping("/pdf")
    public Result<ExportJobResponse> createPdf(
            @AuthenticationPrincipal CurrentUser currentUser,
            @Valid @RequestBody CreatePdfExportRequest request) {
        return Result.success(exportService.createPdf(currentUser.userId(), request));
    }

    /**
     * 查询当前用户的导出任务摘要。
     * 返回值只包含任务元数据和下载入口，不返回导出文件 bytes。
     */
    @GetMapping
    public Result<List<ExportJobResponse>> exports(@AuthenticationPrincipal CurrentUser currentUser) {
        return Result.success(exportService.listOwned(currentUser.userId()));
    }

    /**
     * 查询当前用户拥有的单个导出任务摘要。
     * 参数 jobId 必须属于当前用户；越权任务按不存在处理。
     */
    @GetMapping("/{jobId}")
    public Result<ExportJobResponse> export(
            @AuthenticationPrincipal CurrentUser currentUser,
            @PathVariable String jobId) {
        return Result.success(exportService.detailOwned(currentUser.userId(), jobId));
    }

    /**
     * 取消当前用户拥有的待处理或执行中导出任务。
     * 参数 jobId 必须归属当前用户；取消结果不返回文件 bytes、下载路径或存储 key。
     */
    @PostMapping("/{jobId}/cancel")
    public Result<ExportJobResponse> cancel(
            @AuthenticationPrincipal CurrentUser currentUser,
            @PathVariable String jobId) {
        return Result.success(exportService.cancel(currentUser.userId(), jobId));
    }

    /**
     * 下载导出文件。
     * 参数 jobId 必须属于当前用户；响应只设置安全文件名和 PDF content type，不暴露临时路径。
     */
    @GetMapping("/{jobId}/download")
    public ResponseEntity<byte[]> download(
            @AuthenticationPrincipal CurrentUser currentUser,
            @PathVariable String jobId) {
        ExportDownload download = exportService.download(currentUser.userId(), jobId);
        return ResponseEntity.ok()
                .contentType(MediaType.parseMediaType(download.contentType()))
                .header(HttpHeaders.CONTENT_DISPOSITION, ContentDisposition.attachment()
                        .filename(download.fileName())
                        .build()
                        .toString())
                .body(download.content());
    }
}
