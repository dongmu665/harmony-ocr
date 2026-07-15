package com.harmonyocr.record.dto;

import jakarta.validation.constraints.NotNull;

/**
 * OCR 历史记录收藏状态请求，属于 record 模块。
 * 维护说明：使用显式布尔值而不是盲目切换，便于移动端云同步时保持幂等。
 */
public record FavoriteRecordRequest(
        @NotNull Boolean favorite
) {
}
