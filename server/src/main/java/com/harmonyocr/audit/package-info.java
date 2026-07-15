/**
 * 审计模块边界。
 *
 * 维护说明：审计日志只能保存操作元数据、目标类型和脱敏状态，不得写入密码、Token、API Key、请求体全文或 OCR 文本。
 */
package com.harmonyocr.audit;
