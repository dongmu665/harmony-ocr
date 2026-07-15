package com.harmonyocr.record.dto;

import jakarta.validation.constraints.Size;

/**
 * 更新 OCR 历史标签请求，属于 record 模块。
 * 维护说明：只允许修改标签名和颜色，不允许客户端指定 userId 或绑定关系。
 */
public record UpdateTagRequest(
        @Size(max = 64) String name,
        @Size(max = 32) String color
) {
}
