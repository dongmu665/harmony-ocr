package com.harmonyocr.ocr.dto;

/**
 * 批量 OCR item 状态枚举，属于 ocr 模块。
 * 维护说明：状态仅描述当前批量任务内单个图片的处理进度，不包含图片内容、对象 key 或用户隐私文本。
 */
public enum BatchOcrItemStatus {
    QUEUED,
    PENDING,
    RUNNING,
    RETRYING,
    CANCELED,
    SUCCESS,
    FAILED
}
