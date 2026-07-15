import { common } from '@kit.AbilityKit';
import { fileIo, picker } from '@kit.CoreFileKit';
import { ApiError } from '../../common/network/ApiTypes';

/**
 * DevicePdfSelection 表示用户本轮通过系统文件选择器授权的 PDF。
 * 安全边界：uri 只在内存中用于读取和上传，页面只能展示 displayName/size 等脱敏信息。
 */
export interface DevicePdfSelection {
  displayName: string;
  size: number;
  mimeType: string;
  uri: string;
}

/**
 * DevicePdfPickerService 负责扫描型 PDF 的系统文件选择与字节读取。
 * 维护说明：URI 只在内存中用于本轮上传，UI 只能展示脱敏文件名和大小，不能展示完整 URI 或本地路径。
 */
export class DevicePdfPickerService {
  /**
   * 打开系统 DocumentViewPicker 选择单个 PDF。
   * 参数 context 来自当前 UIAbility；返回 undefined 表示用户取消，不写入任何本地状态。
   */
  static async selectPdf(context: common.UIAbilityContext): Promise<DevicePdfSelection | undefined> {
    const options = new picker.DocumentSelectOptions();
    options.fileSuffixFilters = ['PDF|.pdf'];
    options.maxSelectNumber = 1;
    const documentPicker = new picker.DocumentViewPicker(context);
    const uris: Array<string> = await documentPicker.select(options);
    if (uris.length === 0) {
      return undefined;
    }
    const uri = uris[0];
    const size = DevicePdfPickerService.statSize(uri);
    return {
      displayName: DevicePdfPickerService.safeDisplayName(uri),
      size: size,
      mimeType: 'application/pdf',
      uri: uri
    };
  }

  /**
   * 读取本轮授权 PDF 的字节。
   * 参数 selection 必须来自 selectPdf；方法只返回内存字节，不记录 uri、路径或文件内容。
   */
  static readPdfBytes(selection: DevicePdfSelection): Uint8Array {
    if (selection.mimeType !== 'application/pdf') {
      throw new ApiError('FILE_TYPE_NOT_ALLOWED', '请选择 PDF 文件', 0);
    }
    try {
      return DevicePdfPickerService.readPdfBytesByRandomAccessFile(selection.uri);
    } catch (_) {
      return DevicePdfPickerService.readPdfBytesByOpenSync(selection.uri);
    }
  }

  /**
   * 优先使用 RandomAccessFile 读取 picker URI；失败时由外层尝试 fd 兜底。
   */
  private static readPdfBytesByRandomAccessFile(uri: string): Uint8Array {
    let file: fileIo.RandomAccessFile | undefined = undefined;
    try {
      file = fileIo.createRandomAccessFileSync(uri, fileIo.OpenMode.READ_ONLY);
      const stat = fileIo.statSync(file.fd);
      if (stat.size <= 0) {
        throw new ApiError('VALIDATION_ERROR', 'PDF 文件为空，请重新选择', 0);
      }
      const buffer = new ArrayBuffer(stat.size);
      const readLength = file.readSync(buffer, { offset: 0, length: stat.size });
      if (readLength <= 0) {
        throw new ApiError('PDF_READ_FAILED', '无法读取 PDF 文件，请重新选择', 0);
      }
      return new Uint8Array(buffer, 0, readLength);
    } catch (error) {
      if (error instanceof ApiError) {
        throw error;
      }
      throw new ApiError('PDF_READ_FAILED', '无法读取 PDF 文件，请重新选择', 0);
    } finally {
      if (file !== undefined) {
        try {
          file.close();
        } catch (_) {
        }
      }
    }
  }

  /**
   * 兜底使用 fileIo.openSync + fd 读取 DocumentViewPicker URI。
   * 部分系统文件服务不支持 createRandomAccessFileSync(uri)，但允许 openSync(uri) 后按 fd 读取。
   */
  private static readPdfBytesByOpenSync(uri: string): Uint8Array {
    let file: fileIo.File | undefined = undefined;
    try {
      file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
      const stat = fileIo.statSync(file.fd);
      if (stat.size <= 0) {
        throw new ApiError('VALIDATION_ERROR', 'PDF 文件为空，请重新选择', 0);
      }
      const buffer = new ArrayBuffer(stat.size);
      const readLength = fileIo.readSync(file.fd, buffer, { offset: 0, length: stat.size });
      if (readLength <= 0) {
        throw new ApiError('PDF_READ_FAILED', '无法读取 PDF 文件，请重新选择', 0);
      }
      return new Uint8Array(buffer, 0, readLength);
    } catch (error) {
      if (error instanceof ApiError) {
        throw error;
      }
      throw new ApiError('PDF_READ_FAILED', '无法读取 PDF 文件，请重新选择', 0);
    } finally {
      if (file !== undefined) {
        try {
          fileIo.closeSync(file);
        } catch (_) {
        }
      }
    }
  }

  /**
   * 读取 PDF 文件大小。
   * 说明：仅用于 UI 展示和基本校验，失败时返回 0 由调用方按未知大小处理。
   */
  private static statSize(uri: string): number {
    const randomAccessSize = DevicePdfPickerService.readPdfSizeByRandomAccessFile(uri);
    if (randomAccessSize > 0) {
      return randomAccessSize;
    }
    return DevicePdfPickerService.readPdfSizeByOpenSync(uri);
  }

  /**
   * 使用 RandomAccessFile 读取 PDF 大小。
   * 安全边界：不把 uri 或 fd 写入日志，失败只返回 0。
   */
  private static readPdfSizeByRandomAccessFile(uri: string): number {
    let file: fileIo.RandomAccessFile | undefined = undefined;
    try {
      file = fileIo.createRandomAccessFileSync(uri, fileIo.OpenMode.READ_ONLY);
      const stat = fileIo.statSync(file.fd);
      return stat.size;
    } catch (_) {
      return 0;
    } finally {
      if (file !== undefined) {
        try {
          file.close();
        } catch (_) {
        }
      }
    }
  }

  /**
   * 使用 openSync + fd 兜底读取 PDF 大小。
   * 维护说明：部分 DocumentViewPicker URI 只支持该路径，失败仍按未知大小处理。
   */
  private static readPdfSizeByOpenSync(uri: string): number {
    let file: fileIo.File | undefined = undefined;
    try {
      file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
      const stat = fileIo.statSync(file.fd);
      return stat.size;
    } catch (_) {
      return 0;
    } finally {
      if (file !== undefined) {
        try {
          fileIo.closeSync(file);
        } catch (_) {
        }
      }
    }
  }

  /**
   * 从 URI 派生安全展示名。
   * 返回值限制为短文件名；不展示完整 URI、目录路径或系统文件服务标识。
   */
  private static safeDisplayName(uri: string): string {
    const normalized = uri.replace(/\\/g, '/');
    const parts = normalized.split('/');
    const last = parts.length > 0 ? parts[parts.length - 1] : '';
    const safe = last.replace(/["'\r\n]/g, '_');
    if (safe.toLowerCase().endsWith('.pdf') && safe.length <= 80) {
      return safe;
    }
    return `scan-${Date.now()}.pdf`;
  }
}
