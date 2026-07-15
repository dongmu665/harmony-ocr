package com.harmonyocr.record.dto;

import jakarta.validation.constraints.Size;

/**
 * OCR 历史记录更新请求，属于 record 模块。
 * 维护说明：只允许修改标题、编辑后文本和收藏状态，不允许客户端修改 userId、sourceType 或删除标记。
 */
public record UpdateRecordRequest(
        @Size(max = 128) String title,
        String editedText,
        Boolean favorite
) {
}
