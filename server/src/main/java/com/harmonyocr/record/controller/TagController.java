package com.harmonyocr.record.controller;

import com.harmonyocr.auth.security.CurrentUser;
import com.harmonyocr.common.api.Result;
import com.harmonyocr.record.dto.CreateTagRequest;
import com.harmonyocr.record.dto.TagResponse;
import com.harmonyocr.record.dto.UpdateTagRequest;
import com.harmonyocr.record.service.TagService;
import jakarta.validation.Valid;
import java.util.List;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * OCR 历史标签接口控制器，属于 record 模块。
 * 维护说明：控制器只接收标签元数据，用户归属一律来自 SecurityContext，不信任客户端 userId。
 */
@RestController
@RequestMapping("/api/v1/tags")
public class TagController {

    private final TagService tagService;

    public TagController(TagService tagService) {
        this.tagService = tagService;
    }

    /**
     * 创建当前用户的历史标签。
     * 参数为标签名和可选颜色；返回标签元信息。安全注意：标签内容不得用于保存 OCR 全文。
     */
    @PostMapping
    public Result<TagResponse> create(
            @AuthenticationPrincipal CurrentUser currentUser,
            @Valid @RequestBody CreateTagRequest request) {
        return Result.success(tagService.create(currentUser.userId(), request));
    }

    /**
     * 查询当前用户的历史标签列表。
     * 参数为认证主体；返回当前用户全部标签，不返回其他用户标签。
     */
    @GetMapping
    public Result<List<TagResponse>> list(@AuthenticationPrincipal CurrentUser currentUser) {
        return Result.success(tagService.list(currentUser.userId()));
    }

    /**
     * 更新当前用户拥有的历史标签。
     * 参数为标签 ID 和更新请求；不存在或非本人标签统一返回 NOT_FOUND。
     */
    @PatchMapping("/{id}")
    public Result<TagResponse> update(
            @AuthenticationPrincipal CurrentUser currentUser,
            @PathVariable Long id,
            @Valid @RequestBody UpdateTagRequest request) {
        return Result.success(tagService.update(currentUser.userId(), id, request));
    }

    /**
     * 删除当前用户拥有的历史标签。
     * 参数为标签 ID；删除标签会删除绑定关系，但不会删除 OCR 历史记录。
     */
    @DeleteMapping("/{id}")
    public Result<Void> delete(
            @AuthenticationPrincipal CurrentUser currentUser,
            @PathVariable Long id) {
        tagService.delete(currentUser.userId(), id);
        return Result.success(null);
    }
}
