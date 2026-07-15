import { HttpClient } from '../../common/network/HttpClient';
import { TokenStorage } from '../../common/storage/TokenStorage';
import { FeedbackSubmitRequest, FeedbackSubmitResponse } from './FeedbackModels';

/**
 * FeedbackService 封装用户反馈 API，属于 feedback 功能模块。
 * 维护说明：服务只提交用户主动填写内容，不读取 OCR 全文、不输出联系方式或设备信息到日志。
 */
export class FeedbackService {
  /**
   * 提交用户反馈。
   * 参数 request 仅包含反馈类型、正文和可选联系方式；登录用户会携带认证态，游客反馈不强制登录。
   */
  static async submitFeedback(request: FeedbackSubmitRequest): Promise<FeedbackSubmitResponse> {
    const hasSession = await TokenStorage.hasSession();
    return HttpClient.post<FeedbackSubmitResponse>('/feedback', request, { authorized: hasSession });
  }
}
