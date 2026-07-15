package com.harmonyocr.file.controller;

import com.harmonyocr.auth.security.CurrentUser;
import com.harmonyocr.common.api.Result;
import com.harmonyocr.file.dto.FileObjectResponse;
import com.harmonyocr.file.service.FileObjectService;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

/**
 * 文件对象接口控制器，属于 file 模块。
 * 维护说明：控制器只接收 multipart 文件和路径参数，当前用户 ID 必须来自 SecurityContext，不接受客户端传入 userId、bucket 或 objectKey。
 */
@RestController
@RequestMapping("/api/v1/files")
public class FileController {

    private final FileObjectService fileObjectService;

    public FileController(FileObjectService fileObjectService) {
        this.fileObjectService = fileObjectService;
    }

    /**
     * 上传当前登录用户的文件对象。
     * 参数为认证主体和 `file` 表单字段；返回文件对象元数据。安全注意：文件类型、大小、文件名和 objectKey 均由服务端校验或生成。
     */
    @PostMapping("/upload")
    public Result<FileObjectResponse> upload(
            @AuthenticationPrincipal CurrentUser currentUser,
            @RequestParam("file") MultipartFile file) {
        return Result.success(fileObjectService.upload(currentUser.userId(), file));
    }

    /**
     * 查询当前登录用户拥有的文件对象元数据。
     * 参数为认证主体和文件对象 ID；返回不含签名 URL 和二进制内容的元数据，不存在或越权统一按 NOT_FOUND 处理。
     */
    @GetMapping("/{id}")
    public Result<FileObjectResponse> detail(
            @AuthenticationPrincipal CurrentUser currentUser,
            @PathVariable Long id) {
        return Result.success(fileObjectService.detail(currentUser.userId(), id));
    }

    /**
     * 软删除当前登录用户拥有的文件对象。
     * 参数为认证主体和文件对象 ID；返回统一空成功响应。安全注意：对象存储删除失败不暴露底层异常或密钥信息。
     */
    @DeleteMapping("/{id}")
    public Result<Void> delete(
            @AuthenticationPrincipal CurrentUser currentUser,
            @PathVariable Long id) {
        fileObjectService.softDelete(currentUser.userId(), id);
        return Result.success(null);
    }
}
