package com.harmonyocr.record.controller;

import com.harmonyocr.auth.security.CurrentUser;
import com.harmonyocr.common.api.PageResult;
import com.harmonyocr.common.api.Result;
import com.harmonyocr.record.dto.CreateRecordRequest;
import com.harmonyocr.record.dto.FavoriteRecordRequest;
import com.harmonyocr.record.dto.RecordResponse;
import com.harmonyocr.record.dto.RecordSearchQuery;
import com.harmonyocr.record.dto.UpdateRecordRequest;
import com.harmonyocr.record.service.RecordService;
import jakarta.validation.Valid;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * OCR 历史记录接口控制器，属于 record 模块。
 * 维护说明：控制器只负责参数接收和统一 Result 封装，当前用户 ID 必须来自 SecurityContext，不得信任请求体中的 userId。
 */
@RestController
@RequestMapping("/api/v1/records")
public class RecordController {

    private final RecordService recordService;

    public RecordController(RecordService recordService) {
        this.recordService = recordService;
    }

    /**
     * 创建当前登录用户的 OCR 历史记录。
     * 参数为请求体和认证主体；返回记录详情。安全注意：记录归属由 CurrentUser.userId 决定，客户端传入的 userId 会被忽略。
     */
    @PostMapping
    public Result<RecordResponse> create(
            @AuthenticationPrincipal CurrentUser currentUser,
            @Valid @RequestBody CreateRecordRequest request) {
        return Result.success(recordService.create(currentUser.userId(), request));
    }

    /**
     * 分页查询当前登录用户的 OCR 历史记录。
     * 参数为分页、收藏、来源和关键词筛选；返回当前用户未删除记录分页。安全注意：所有筛选只在当前用户范围内生效。
     */
    @GetMapping
    public Result<PageResult<RecordResponse>> list(
            @AuthenticationPrincipal CurrentUser currentUser,
            @RequestParam(required = false) Integer page,
            @RequestParam(required = false) Integer size,
            @RequestParam(required = false) Boolean favorite,
            @RequestParam(required = false) String sourceType,
            @RequestParam(required = false) String keyword,
            @RequestParam(required = false) String createdFrom,
            @RequestParam(required = false) String createdTo,
            @RequestParam(required = false) String dateFrom,
            @RequestParam(required = false) String dateTo,
            @RequestParam(required = false) Long tagId,
            @RequestParam(required = false) String ocrEngine,
            @RequestParam(required = false) String sort) {
        RecordSearchQuery query = new RecordSearchQuery(
                page, size, favorite, sourceType, keyword, createdFrom, createdTo, dateFrom, dateTo, tagId, ocrEngine, sort);
        return Result.success(recordService.list(currentUser.userId(), query));
    }

    /**
     * 查询当前登录用户拥有的单条 OCR 历史详情。
     * 参数为认证主体和记录 ID；返回包含 blocks 的详情。不存在、已删除或非本人记录统一返回 NOT_FOUND。
     */
    @GetMapping("/{id}")
    public Result<RecordResponse> detail(
            @AuthenticationPrincipal CurrentUser currentUser,
            @PathVariable Long id) {
        return Result.success(recordService.detail(currentUser.userId(), id));
    }

    /**
     * 修改当前登录用户拥有的 OCR 历史记录。
     * 参数为记录 ID 和允许修改字段；返回更新后详情。安全注意：不能修改 userId、来源或删除状态。
     */
    @PatchMapping("/{id}")
    public Result<RecordResponse> update(
            @AuthenticationPrincipal CurrentUser currentUser,
            @PathVariable Long id,
            @Valid @RequestBody UpdateRecordRequest request) {
        return Result.success(recordService.update(currentUser.userId(), id, request));
    }

    /**
     * 兼容 HarmonyOS HTTP SDK 在部分模拟器环境中 PATCH 请求失败的记录编辑入口。
     * 业务语义、字段校验和归属校验与 PATCH /records/{id} 完全一致；仅替换传输动词，不放宽安全边界。
     */
    @PostMapping("/{id}/update")
    public Result<RecordResponse> updateByPost(
            @AuthenticationPrincipal CurrentUser currentUser,
            @PathVariable Long id,
            @Valid @RequestBody UpdateRecordRequest request) {
        return Result.success(recordService.update(currentUser.userId(), id, request));
    }

    /**
     * 软删除当前登录用户拥有的 OCR 历史记录。
     * 参数为记录 ID；返回统一空成功响应。安全注意：删除只设置 deleted/deletedAt，不处理 MinIO 文件对象。
     */
    @DeleteMapping("/{id}")
    public Result<Void> delete(
            @AuthenticationPrincipal CurrentUser currentUser,
            @PathVariable Long id) {
        recordService.softDelete(currentUser.userId(), id);
        return Result.success(null);
    }

    /**
     * 设置当前登录用户拥有记录的收藏状态。
     * 参数为记录 ID 和目标收藏值；返回更新后详情。不存在、已删除或非本人记录统一返回 NOT_FOUND。
     */
    @PatchMapping("/{id}/favorite")
    public Result<RecordResponse> favorite(
            @AuthenticationPrincipal CurrentUser currentUser,
            @PathVariable Long id,
            @Valid @RequestBody FavoriteRecordRequest request) {
        return Result.success(recordService.favorite(currentUser.userId(), id, request.favorite()));
    }

    /**
     * 兼容 HarmonyOS HTTP SDK 缺少 PATCH 枚举的收藏状态更新入口。
     * 参数和 PATCH 版本完全一致；安全边界仍由 CurrentUser.userId 和 RecordService 的归属校验保证。
     */
    @PostMapping("/{id}/favorite")
    public Result<RecordResponse> favoriteByPost(
            @AuthenticationPrincipal CurrentUser currentUser,
            @PathVariable Long id,
            @Valid @RequestBody FavoriteRecordRequest request) {
        return Result.success(recordService.favorite(currentUser.userId(), id, request.favorite()));
    }

    /**
     * 给当前用户拥有的 OCR 历史记录绑定标签。
     * 参数为记录 ID 与标签 ID；重复绑定按幂等成功返回当前详情。不存在或越权统一返回 NOT_FOUND。
     */
    @PostMapping("/{id}/tags/{tagId}")
    public Result<RecordResponse> addTag(
            @AuthenticationPrincipal CurrentUser currentUser,
            @PathVariable Long id,
            @PathVariable Long tagId) {
        return Result.success(recordService.addTag(currentUser.userId(), id, tagId));
    }

    /**
     * 移除当前用户拥有记录上的标签绑定。
     * 参数为记录 ID 与标签 ID；不存在或越权统一返回 NOT_FOUND，未绑定时按幂等成功返回当前详情。
     */
    @DeleteMapping("/{id}/tags/{tagId}")
    public Result<RecordResponse> removeTag(
            @AuthenticationPrincipal CurrentUser currentUser,
            @PathVariable Long id,
            @PathVariable Long tagId) {
        return Result.success(recordService.removeTag(currentUser.userId(), id, tagId));
    }

    /**
     * 搜索当前登录用户的 OCR 历史记录。
     * 参数为关键词和分页；空关键词按普通分页列表处理。安全注意：搜索仅匹配当前用户未删除记录。
     */
    @GetMapping("/search")
    public Result<PageResult<RecordResponse>> search(
            @AuthenticationPrincipal CurrentUser currentUser,
            @RequestParam(required = false) String keyword,
            @RequestParam(required = false) Integer page,
            @RequestParam(required = false) Integer size) {
        return Result.success(recordService.search(currentUser.userId(), keyword, page, size));
    }
}
