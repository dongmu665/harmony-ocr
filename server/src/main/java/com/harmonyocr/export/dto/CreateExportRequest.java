package com.harmonyocr.export.dto;

import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.NotNull;
import java.util.List;

/**
 * 通用导出请求，属于 export 模块。
 * 维护说明：仅接收记录 ID、目标格式和展示文件名；不接收本地路径、对象存储 key、用户 ID 或导出文件内容。
 */
public record CreateExportRequest(
        @NotEmpty List<Long> recordIds,
        @NotNull ExportFormat format,
        String fileName
) {
}
