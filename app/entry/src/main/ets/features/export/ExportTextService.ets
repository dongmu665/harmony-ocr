import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { FileNameUtils } from '../../common/utils/FileNameUtils';

/**
 * ExportTextResult 描述本地导出文件的脱敏结果。
 * 维护说明：path 仅供当前应用沙箱内后续分享/清理使用，不应展示完整路径或上传到后端。
 */
export interface ExportTextResult {
  fileName: string;
  path: string;
  bytes: number;
}

/**
 * ExportTextService 提供 V1.1 TXT 导出能力，属于 export 功能模块。
 * 维护说明：导出只由用户主动触发，文件写入应用沙箱缓存目录，不上传 OCR 文本、不记录全文。
 */
export class ExportTextService {
  private static readonly EXPORT_PREFIX: string = 'harmony-ocr-export-';

  /**
   * 将当前编辑文本导出为 TXT 文件。
   * 参数 context 用于定位应用缓存目录，title 只用于文件名，text 为用户当前可见文本；返回脱敏文件元信息。
   */
  static async exportToTxt(
    context: common.UIAbilityContext,
    title: string,
    text: string
  ): Promise<ExportTextResult> {
    const normalized = text.trim();
    if (normalized.length === 0) {
      throw new Error('EMPTY_EXPORT_TEXT');
    }
    const fileName = `${ExportTextService.EXPORT_PREFIX}${FileNameUtils.safeTxtFileName(title)}`;
    const outputPath = `${context.cacheDir}/${fileName}`;
    const encoder = util.TextEncoder.create('utf-8');
    const content = encoder.encodeInto(text);
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
   * 判断文件名是否属于本应用 TXT 导出缓存。
   * 参数只接收文件名，不接收完整路径，避免清理流程越过应用 cacheDir 边界。
   */
  static isExportCacheFile(fileName: string): boolean {
    return fileName.startsWith(ExportTextService.EXPORT_PREFIX);
  }
}
