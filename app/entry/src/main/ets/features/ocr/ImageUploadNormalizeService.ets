import { image } from '@kit.ImageKit';
import { ApiError } from '../../common/network/ApiTypes';
import { DeviceImageSelection } from './DeviceOcrModels';

/**
 * ImageUploadNormalizeService 统一处理 OCR 图片上传前的格式判定与转码。
 * 维护说明：本服务只在内存中检查图片魔数和执行 ImageKit 解码/打包，不记录 URI、图片 bytes、base64、Token 或 OCR 文本。
 */
export interface NormalizedImageUpload {
  fileName: string;
  mimeType: string;
  content: Uint8Array;
}

export class ImageUploadNormalizeService {
  static readonly UPLOAD_JPEG_MIME: string = 'image/jpeg';
  static readonly UPLOAD_PNG_MIME: string = 'image/png';
  static readonly UPLOAD_WEBP_MIME: string = 'image/webp';
  private static readonly JPEG_QUALITY: number = 88;

  /**
   * 将用户选择的图片规范化为后端允许的 JPEG/PNG/WebP 上传片段。
   * JPEG/PNG/WebP 保留原 bytes；HEIC/HEIF、BMP、GIF、TIFF 等 ImageKit 可解码格式转为 JPEG。
   */
  static async normalizeSelectionForUpload(
    selection: DeviceImageSelection,
    content: Uint8Array
  ): Promise<NormalizedImageUpload> {
    const detectedMimeType = ImageUploadNormalizeService.detectSupportedImageMimeType(content);
    if (detectedMimeType.length > 0) {
      return {
        fileName: ImageUploadNormalizeService.normalizeFileName(selection.fileName, detectedMimeType),
        mimeType: detectedMimeType,
        content: content
      };
    }
    return ImageUploadNormalizeService.repackImageAsJpeg(selection.fileName, content);
  }

  /**
   * 按魔数识别后端直接支持的图片格式，避免把真实 bytes 错声明成另一个 MIME。
   */
  static detectSupportedImageMimeType(content: Uint8Array): string {
    if (content.length >= 3 &&
      content[0] === 0xFF &&
      content[1] === 0xD8 &&
      content[2] === 0xFF) {
      return ImageUploadNormalizeService.UPLOAD_JPEG_MIME;
    }
    if (content.length >= 8 &&
      content[0] === 0x89 &&
      content[1] === 0x50 &&
      content[2] === 0x4E &&
      content[3] === 0x47 &&
      content[4] === 0x0D &&
      content[5] === 0x0A &&
      content[6] === 0x1A &&
      content[7] === 0x0A) {
      return ImageUploadNormalizeService.UPLOAD_PNG_MIME;
    }
    if (content.length >= 12 &&
      content[0] === 0x52 &&
      content[1] === 0x49 &&
      content[2] === 0x46 &&
      content[3] === 0x46 &&
      content[8] === 0x57 &&
      content[9] === 0x45 &&
      content[10] === 0x42 &&
      content[11] === 0x50) {
      return ImageUploadNormalizeService.UPLOAD_WEBP_MIME;
    }
    return '';
  }

  /**
   * 使用 ImageKit 解码系统可读照片格式，并转成后端稳定接受的 JPEG。
   */
  private static async repackImageAsJpeg(fileName: string, content: Uint8Array): Promise<NormalizedImageUpload> {
    const source = image.createImageSource(ImageUploadNormalizeService.toExactArrayBuffer(content));
    let pixelMap: image.PixelMap | undefined = undefined;
    let packer: image.ImagePacker | undefined = undefined;
    try {
      pixelMap = await source.createPixelMap();
      packer = image.createImagePacker();
      const packed = await packer.packToData(pixelMap, {
        format: ImageUploadNormalizeService.UPLOAD_JPEG_MIME,
        quality: ImageUploadNormalizeService.JPEG_QUALITY
      });
      return {
        fileName: ImageUploadNormalizeService.normalizeFileName(fileName, ImageUploadNormalizeService.UPLOAD_JPEG_MIME),
        mimeType: ImageUploadNormalizeService.UPLOAD_JPEG_MIME,
        content: new Uint8Array(packed)
      };
    } catch (_) {
      throw new ApiError('INVALID_IMAGE', '图片格式暂不支持，请重新选择常见照片格式', 400);
    } finally {
      if (packer !== undefined) {
        await packer.release();
      }
      if (pixelMap !== undefined) {
        await pixelMap.release();
      }
      await source.release();
    }
  }

  /**
   * 生成与真实上传 MIME 匹配的安全文件名，避免扩展名和 Content-Type 不一致。
   */
  private static normalizeFileName(fileName: string, mimeType: string): string {
    const extension = ImageUploadNormalizeService.extensionForMimeType(mimeType);
    const baseName = fileName.length > 0 ? fileName.replace(/\.[A-Za-z0-9]{1,8}$/g, '') : 'image';
    const safeBaseName = baseName.replace(/["\r\n\\/]+/g, '_');
    return `${safeBaseName.length > 0 ? safeBaseName : 'image'}${extension}`;
  }

  private static extensionForMimeType(mimeType: string): string {
    if (mimeType === ImageUploadNormalizeService.UPLOAD_PNG_MIME) {
      return '.png';
    }
    if (mimeType === ImageUploadNormalizeService.UPLOAD_WEBP_MIME) {
      return '.webp';
    }
    return '.jpg';
  }

  /**
   * 为 ImageKit 解码准备精确长度的 ArrayBuffer，避免 Uint8Array 视图携带额外缓冲区内容。
   */
  private static toExactArrayBuffer(content: Uint8Array): ArrayBuffer {
    const copied = new Uint8Array(content.length);
    copied.set(content, 0);
    return copied.buffer;
  }
}
