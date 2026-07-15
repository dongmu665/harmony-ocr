import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { FileNameUtils } from '../../common/utils/FileNameUtils';
import { ExportTextResult } from './ExportTextService';

/**
 * MarkdownExportInput 描述一次 Markdown 导出的用户可见内容。
 * 安全边界：只包含当前用户主动导出的文本和脱敏元信息，不包含 Token、objectKey、URI 或 provider 密钥。
 */
export interface MarkdownExportInput {
  title: string;
  text: string;
  sourceType?: string;
  ocrEngine?: string;
  ocrMode?: string;
  durationMs?: number;
  createdAt?: string;
}

/**
 * MarkdownExportService 提供轻量 Markdown 导出能力，属于 export 功能模块。
 * 维护说明：导出文件只写入应用沙箱缓存目录，不上传 OCR 文本、不记录全文、不记录完整路径。
 */
export class MarkdownExportService {
  private static readonly EXPORT_PREFIX: string = 'harmony-ocr-export-';

  /**
   * 将 OCR 文本和元信息导出为 Markdown 文件。
   * 参数 context 用于定位缓存目录，input 包含标题、文本和非敏感元信息；返回脱敏文件元信息。
   */
  static async exportToMarkdown(
    context: common.UIAbilityContext,
    input: MarkdownExportInput
  ): Promise<ExportTextResult> {
    const normalizedText = input.text.trim();
    if (normalizedText.length === 0) {
      throw new Error('EMPTY_MARKDOWN_EXPORT_TEXT');
    }
    const fileName = `${MarkdownExportService.EXPORT_PREFIX}${FileNameUtils.safeMarkdownFileName(input.title)}`;
    const outputPath = `${context.cacheDir}/${fileName}`;
    const encoder = util.TextEncoder.create('utf-8');
    const content = encoder.encodeInto(MarkdownExportService.renderMarkdown(input));
    let outputFile: fileIo.File | undefined = undefined;
    try {
      outputFile = fileIo.openSync(
        outputPath,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC | fileIo.OpenMode.WRITE_ONLY
      );
      const bytes = fileIo.writeSync(outputFile.fd, content.buffer);
      return {
        fileName: fileName,
        path: outputPath,
        bytes: bytes
      };
    } finally {
      if (outputFile !== undefined) {
        fileIo.closeSync(outputFile);
      }
    }
  }

  /**
   * 渲染轻量 Markdown 内容。
   * 参数 input 为用户主动导出的 OCR 文本和元信息；返回 Markdown 字符串，不做 AI 排版或复杂文档解析。
   */
  static renderMarkdown(input: MarkdownExportInput): string {
    const lines: string[] = [];
    lines.push('# OCR 识别结果');
    lines.push('');
    lines.push(`- 来源：${MarkdownExportService.safeMeta(input.sourceType ?? 'unknown')}`);
    lines.push(`- 识别引擎：${MarkdownExportService.safeMeta(input.ocrEngine ?? 'unknown')}`);
    lines.push(`- 识别模式：${MarkdownExportService.safeMeta(input.ocrMode ?? 'single-image')}`);
    lines.push(`- 识别耗时：${input.durationMs !== undefined ? String(input.durationMs) + ' ms' : 'unknown'}`);
    lines.push(`- 创建时间：${MarkdownExportService.safeMeta(input.createdAt ?? 'unknown')}`);
    lines.push('');
    lines.push('## 文本内容');
    lines.push('');
    lines.push(MarkdownExportService.normalizeBody(input.text));
    lines.push('');
    return lines.join('\n');
  }

  /**
   * 判断文件是否属于本应用导出缓存。
   * 参数 fileName 为文件名而非完整路径；返回 true 表示可被缓存清理流程识别。
   */
  static isExportCacheFile(fileName: string): boolean {
    return fileName.startsWith(MarkdownExportService.EXPORT_PREFIX) && fileName.endsWith('.md');
  }

  private static safeMeta(value: string): string {
    return value.replace(/[\r\n|]/g, ' ').trim();
  }

  private static normalizeBody(text: string): string {
    return text.replace(/\r\n/g, '\n').replace(/\r/g, '\n').trim();
  }
}
