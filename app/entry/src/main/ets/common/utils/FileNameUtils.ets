/**
 * FileNameUtils 负责生成本地导出文件名，属于通用工具层。
 * 维护说明：只处理用户可见标题的字符清理，不读取 OCR 全文、不拼接账号、Token 或本地路径。
 */
export class FileNameUtils {
  /**
   * 生成安全 TXT 文件名。
   * 参数 title 来自页面标题或记录标题；返回值去除路径分隔符和控制字符，避免写入异常路径。
   */
  static safeTxtFileName(title: string): string {
    return FileNameUtils.safeFileName(title, 'txt');
  }

  /**
   * 生成安全 Markdown 文件名。
   * 参数 title 来自页面标题或记录标题；返回值固定 .md 后缀，避免调用方传入任意扩展名。
   */
  static safeMarkdownFileName(title: string): string {
    return FileNameUtils.safeFileName(title, 'md');
  }

  private static safeFileName(title: string, extension: string): string {
    const normalized = title
      .replace(/[\\/:*?"<>|\r\n\t]/g, '_')
      .replace(/\s+/g, '_')
      .replace(/_+/g, '_')
      .trim();
    const baseName = normalized.length > 0 ? normalized : 'ocr_text';
    const compactBaseName = baseName.length > 48 ? baseName.substring(0, 48) : baseName;
    return `${compactBaseName}_${FileNameUtils.timestamp()}.${extension}`;
  }

  private static timestamp(): string {
    const now = new Date();
    return `${now.getFullYear()}${FileNameUtils.pad2(now.getMonth() + 1)}${FileNameUtils.pad2(now.getDate())}` +
      `_${FileNameUtils.pad2(now.getHours())}${FileNameUtils.pad2(now.getMinutes())}${FileNameUtils.pad2(now.getSeconds())}` +
      `_${FileNameUtils.pad3(now.getMilliseconds())}`;
  }

  private static pad2(value: number): string {
    return value < 10 ? `0${value}` : String(value);
  }

  /**
   * 将毫秒补齐为三位，降低同一秒内连续导出覆盖前一个文件的概率。
   */
  private static pad3(value: number): string {
    if (value < 10) {
      return `00${value}`;
    }
    if (value < 100) {
      return `0${value}`;
    }
    return String(value);
  }
}
