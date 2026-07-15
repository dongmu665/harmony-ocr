package com.harmonyocr.common.api;

import java.util.List;

/**
 * 后端统一分页响应结构，属于 common/api 模块。
 *
 * 维护说明：items 必须已经在业务层按当前用户或管理员权限过滤；分页对象本身不负责权限判断。
 */
public record PageResult<T>(
        List<T> items,
        long total,
        int page,
        int size
) {
}
