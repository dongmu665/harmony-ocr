package com.harmonyocr.record.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

/**
 * 创建 OCR 历史标签请求，属于 record 模块。
 * 维护说明：标签名称只保存用户可见分类名，不允许携带 OCR 全文、文件路径或对象存储 key。
 */
public record CreateTagRequest(
        @NotBlank @Size(max = 64) String name,
        @Size(max = 32) String color
) {
}
