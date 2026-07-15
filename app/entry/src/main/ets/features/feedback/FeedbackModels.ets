/**
 * FeedbackModels 定义用户反馈接口的前端数据契约，属于 features/feedback 模块。
 *
 * 维护说明：反馈内容和联系方式可能包含个人信息，页面和服务层不得把请求体打印到日志或持久化到本地缓存。
 */
export type FeedbackType = 'bug' | 'suggestion' | 'complaint' | 'other';

/**
 * 用户反馈提交请求。
 *
 * 安全边界：content/contact/deviceInfo 只用于发送到后端反馈接口，不应写入调试输出。
 */
export interface FeedbackSubmitRequest {
  feedbackType: FeedbackType;
  content: string;
  contact?: string;
  deviceInfo?: string;
  appVersion?: string;
}

/**
 * 用户反馈提交后的脱敏响应。
 *
 * 维护说明：响应只保留反馈编号、类型、状态和创建时间，不包含反馈正文或联系方式。
 */
export interface FeedbackSubmitResponse {
  id: string;
  feedbackType: FeedbackType;
  status: string;
  createdAt: string;
}
