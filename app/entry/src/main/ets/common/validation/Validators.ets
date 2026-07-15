/**
 * Validators 提供前端表单基础校验，属于 common 层。
 * 维护说明：这里只返回用户可读错误信息，不记录输入的密码、Token 或其他敏感内容。
 */
export class Validators {
  /**
   * 校验用户名。
   * 参数为用户输入的账号名；返回空字符串代表通过，否则返回可直接展示的错误信息。
   */
  static validateUsername(username: string): string {
    const value = username.trim();
    if (value.length === 0) {
      return '请输入用户名';
    }
    if (value.length < 3 || value.length > 64) {
      return '用户名长度需为 3 到 64 个字符';
    }
    return '';
  }

  /**
   * 校验密码。
   * 参数为用户输入的密码；只检查长度，不返回或记录密码原文。
   */
  static validatePassword(password: string): string {
    if (password.length === 0) {
      return '请输入密码';
    }
    if (password.length < 8 || password.length > 128) {
      return '密码长度需为 8 到 128 个字符';
    }
    return '';
  }

  /**
   * 校验登录密码。
   * 登录只验证本次凭据非空与请求长度边界，避免把注册/改密复杂度策略误用于已有账号登录；不记录密码原文。
   */
  static validateLoginPassword(password: string): string {
    if (password.length === 0) {
      return '请输入密码';
    }
    if (password.length > 128) {
      return '密码长度不能超过 128 个字符';
    }
    return '';
  }

  /**
   * 校验昵称。
   * 参数为可选昵称；空值允许通过，非空时限制长度避免后端校验失败。
   */
  static validateNickname(nickname: string): string {
    if (nickname.trim().length > 64) {
      return '昵称最多 64 个字符';
    }
    return '';
  }
}
