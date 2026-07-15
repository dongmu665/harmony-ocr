package com.harmonyocr.export.dto;

import jakarta.validation.constraints.NotEmpty;
import java.util.List;

/**
 * PDF 导出请求，属于 export 模块。
 * 维护说明：请求只接受记录 ID、展示文件名和 searchable 意图，不接受本地路径、对象存储 key 或用户 ID。
 */
public record CreatePdfExportRequest(
        @NotEmpty List<Long> recordIds,
        String fileName,
        boolean searchable
) {
}
