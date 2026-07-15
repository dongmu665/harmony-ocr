import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { dataSharePredicates } from '@kit.ArkData';
import { image } from '@kit.ImageKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { DeviceImageSelection } from './DeviceOcrModels';

/**
 * CropRect 使用 0-1 归一化坐标描述裁剪区域。
 * 维护说明：输入会在服务层二次夹紧，避免 UI 手势异常造成越界或空裁剪。
 */
export interface CropRect {
  x: number;
  y: number;
  width: number;
  height: number;
}

/**
 * 裁剪页只需要图片原始宽高来换算可见区域，不暴露图片路径、URI 或二进制内容。
 */
export interface CropImageSize {
  width: number;
  height: number;
}

/**
 * ImageCropService 负责设备图片的真实裁剪输出，属于 features/ocr 设备图片处理层。
 * 维护说明：本服务只处理本轮用户通过系统 picker 授权的 media URI，或明确标注的开发测试 rawfile；输出写入应用 cache。
 * 隐私边界：不记录完整 URI、真实路径、图片内容、objectKey、Token 或 Authorization；失败时只向上抛出脱敏错误。
 */
export class ImageCropService {
  private static readonly CROP_OUTPUT_PREFIX: string = 'ocr-crop-output-';
  private static readonly CROP_OUTPUT_MIME: string = 'image/jpeg';
  private static readonly JPEG_QUALITY: number = 88;

  /**
   * 生成真实裁剪输出并返回可供后续上传的缓存文件选择对象。
   * 参数 selection 必须来自本轮用户确认的图片；返回值会指向应用 cache 中新生成的 JPEG，不复用原始 picker URI。
   */
  static async createCenterCrop(
    context: common.UIAbilityContext,
    selection: DeviceImageSelection,
    cropRatio: number = 0.8
  ): Promise<DeviceImageSelection> {
    return ImageCropService.createRectCrop(
      context,
      selection,
      ImageCropService.createCenterCropRect(cropRatio)
    );
  }

  /**
   * 按归一化矩形生成真实裁剪输出。
   * rect 使用 0-1 坐标表达用户在裁剪框中选择的区域，服务端会再次夹紧边界，避免 UI 异常造成越界或空裁剪。
   */
  static async createRectCrop(
    context: common.UIAbilityContext,
    selection: DeviceImageSelection,
    rect: CropRect
  ): Promise<DeviceImageSelection> {
    if (selection.uri.length === 0) {
      throw new Error('未找到可裁剪的图片，请重新选择后再试');
    }
    const sourceBytes = await ImageCropService.readSelectionBytes(context, selection);
    const source = image.createImageSource(sourceBytes.buffer);
    let pixelMap: image.PixelMap | undefined = undefined;
    let packer: image.ImagePacker | undefined = undefined;
    let outputFile: fileIo.File | undefined = undefined;
    try {
      const info = await source.getImageInfo();
      const region = ImageCropService.createRegion(info.size, rect);
      pixelMap = await source.createPixelMap({ desiredRegion: region });
      const outputName = `${ImageCropService.CROP_OUTPUT_PREFIX}${Date.now()}.jpg`;
      const outputPath = `${context.cacheDir}/${outputName}`;
      outputFile = fileIo.openSync(
        outputPath,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC | fileIo.OpenMode.WRITE_ONLY
      );
      packer = image.createImagePacker();
      await packer.packToFile(pixelMap, outputFile.fd, {
        format: ImageCropService.CROP_OUTPUT_MIME,
        quality: ImageCropService.JPEG_QUALITY
      });
      return {
        sourceType: selection.sourceType,
        uri: `file://${outputPath}`,
        fileName: outputName,
        mimeType: ImageCropService.CROP_OUTPUT_MIME,
        uploadSource: 'generated_crop_cache'
      };
    } catch (_) {
      throw new Error('真实裁剪输出失败，请重新选择图片后再试');
    } finally {
      if (outputFile !== undefined) {
        fileIo.closeSync(outputFile);
      }
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
   * 为真实 OCR 创建 PixelMap 输入。
   * 参数 selection 必须来自本轮用户授权的拍照、相册或裁剪缓存；返回值由调用方在 OCR 完成后释放，避免泄露图片内存。
   */
  static async createPixelMapFromSelection(
    context: common.UIAbilityContext,
    selection: DeviceImageSelection
  ): Promise<image.PixelMap> {
    if (selection.uri.length === 0) {
      throw new Error('未找到可识别的图片，请重新选择后再试');
    }
    const sourceBytes = await ImageCropService.readSelectionBytes(context, selection);
    const source = image.createImageSource(sourceBytes.buffer);
    try {
      return await source.createPixelMap();
    } catch (_) {
      throw new Error('图片解码失败，请重新选择清晰图片后再试');
    } finally {
      await source.release();
    }
  }

  /**
   * 读取图片原始尺寸，供裁剪页按 ImageFit.Contain 计算可见图片区域。
   * 只返回宽高数字，不暴露 URI、路径、图片内容或媒体库标识。
   */
  static async getImageSize(
    context: common.UIAbilityContext,
    selection: DeviceImageSelection
  ): Promise<CropImageSize> {
    if (selection.uri.length === 0) {
      throw new Error('未找到可裁剪的图片，请重新选择后再试');
    }
    const sourceBytes = await ImageCropService.readSelectionBytes(context, selection);
    const source = image.createImageSource(sourceBytes.buffer);
    try {
      const info = await source.getImageInfo();
      return {
        width: info.size.width,
        height: info.size.height
      };
    } catch (_) {
      throw new Error('图片尺寸读取失败，请重新选择清晰图片后再试');
    } finally {
      await source.release();
    }
  }

  /**
   * 生成居中裁剪矩形，保留 60/80/100 预设的原有语义。
   */
  private static createCenterCropRect(cropRatio: number): CropRect {
    const safeRatio = ImageCropService.clampCropRatio(cropRatio);
    return {
      x: (1 - safeRatio) / 2,
      y: (1 - safeRatio) / 2,
      width: safeRatio,
      height: safeRatio
    };
  }

  /**
   * 计算实际像素裁剪区域。
   * 坐标来自 UI 手势矩形，但最终以解码后的图片尺寸为准二次校验，保证输出 JPEG 是真实矩形裁剪结果。
   */
  private static createRegion(size: image.Size, rect: CropRect): image.Region {
    const safeRect = ImageCropService.normalizeCropRect(rect);
    const cropWidth = Math.max(1, Math.floor(size.width * safeRect.width));
    const cropHeight = Math.max(1, Math.floor(size.height * safeRect.height));
    const maxX = Math.max(0, size.width - cropWidth);
    const maxY = Math.max(0, size.height - cropHeight);
    return {
      size: {
        width: cropWidth,
        height: cropHeight
      },
      x: Math.min(maxX, Math.max(0, Math.floor(size.width * safeRect.x))),
      y: Math.min(maxY, Math.max(0, Math.floor(size.height * safeRect.y)))
    };
  }

  /**
   * 限制裁剪比例，避免 UI 状态异常导致空裁剪或越界裁剪。
   */
  private static clampCropRatio(cropRatio: number): number {
    if (cropRatio < 0.3) {
      return 0.3;
    }
    if (cropRatio > 1) {
      return 1;
    }
    return cropRatio;
  }

  /**
   * 归一化裁剪矩形，防止手势状态异常导致越界、负数尺寸或过小区域。
   */
  private static normalizeCropRect(rect: CropRect): CropRect {
    const minSize = 0.08;
    const safeWidth = ImageCropService.clampUnit(rect.width, minSize, 1);
    const safeHeight = ImageCropService.clampUnit(rect.height, minSize, 1);
    return {
      x: ImageCropService.clampUnit(rect.x, 0, 1 - safeWidth),
      y: ImageCropService.clampUnit(rect.y, 0, 1 - safeHeight),
      width: safeWidth,
      height: safeHeight
    };
  }

  /**
   * 将数值限制在给定区间内。
   * 说明：用于裁剪坐标归一化，保证最终区域宽高始终可解码。
   */
  private static clampUnit(value: number, min: number, max: number): number {
    if (value < min) {
      return min;
    }
    if (value > max) {
      return max;
    }
    return value;
  }

  /**
   * 读取待裁剪图片内容。
   * picker media URI 只通过系统授权路径读取；开发测试 rawfile 仅用于已标注的测试入口，不会被记录为真实相册能力。
   */
  static async readSelectionBytes(
    context: common.UIAbilityContext,
    selection: DeviceImageSelection
  ): Promise<Uint8Array> {
    if (selection.rawFileName !== undefined && selection.rawFileName.length > 0) {
      return context.resourceManager.getRawFileContent(selection.rawFileName);
    }
    if (selection.uri.startsWith('file://media/') && selection.uploadSource === 'system_picker') {
      return ImageCropService.readPickerUriBytesWithFallback(context, selection.uri);
    }
    if (selection.uploadSource === 'document_picker_image') {
      return ImageCropService.readDocumentPickerImageBytes(selection.uri);
    }
    if (selection.uri.startsWith('file://')) {
      return ImageCropService.readAppCacheFileUriBytes(context, selection.uri);
    }
    throw new Error('当前图片来源不支持裁剪，请重新选择系统图片');
  }

  /**
   * 读取 picker media URI，并在媒体库查询受权限限制时回退到同一个授权 URI 的 fileIo 读取。
   * fallback 只接受系统 picker 返回的 file://media/，不会接收 rawfile、开发测试路径或用户手工拼接路径。
   */
  private static async readPickerUriBytesWithFallback(context: common.UIAbilityContext, uri: string): Promise<Uint8Array> {
    try {
      return await ImageCropService.readPickerUriBytes(context, uri);
    } catch (_) {
      return ImageCropService.readFileUriBytes(uri);
    }
  }

  /**
   * 读取应用缓存 file URI。
   * 普通 file:// 只允许读取本应用 cache 输出，避免后端 OCR fallback 借由任意本地路径绕过系统授权。
   */
  private static readAppCacheFileUriBytes(context: common.UIAbilityContext, uri: string): Uint8Array {
    const filePath = ImageCropService.toFilePath(uri);
    if (!ImageCropService.isUnderDirectory(filePath, context.cacheDir)) {
      throw new Error('当前图片来源不支持裁剪，请重新选择系统图片');
    }
    return ImageCropService.readFilePathBytes(filePath);
  }

  /**
   * 通过 PhotoAccessHelper 读取系统 picker 授权的媒体字节。
   * 方法只按当前 URI 查询单个资产，不枚举图库，不请求 READ_IMAGEVIDEO 权限。
   */
  private static async readPickerUriBytes(context: common.UIAbilityContext, uri: string): Promise<Uint8Array> {
    const helper = photoAccessHelper.getPhotoAccessHelper(context);
    const predicates = new dataSharePredicates.DataSharePredicates();
    predicates.equalTo(photoAccessHelper.PhotoKeys.URI, uri);
    const fetchOptions: photoAccessHelper.FetchOptions = {
      fetchColumns: [photoAccessHelper.PhotoKeys.URI, photoAccessHelper.PhotoKeys.SIZE],
      predicates: predicates
    };
    const fetchResult = await helper.getAssets(fetchOptions);
    try {
      if (fetchResult.getCount() <= 0) {
        throw new Error('无法读取系统相册授权图片，请重新选择后再试');
      }
      const asset = await fetchResult.getFirstObject();
      return await ImageCropService.requestAssetBytes(context, asset);
    } finally {
      fetchResult.close();
    }
  }

  /**
   * 从单个授权 PhotoAsset 请求原始图像数据。
   * 回调只返回内存字节；错误消息保持脱敏，避免暴露媒体 URI 或设备路径。
   */
  private static async requestAssetBytes(
    context: common.UIAbilityContext,
    asset: photoAccessHelper.PhotoAsset
  ): Promise<Uint8Array> {
    return new Promise<Uint8Array>((resolve: (value: Uint8Array) => void, reject: (reason: Error) => void) => {
      const requestOptions: photoAccessHelper.RequestOptions = {
        deliveryMode: photoAccessHelper.DeliveryMode.HIGH_QUALITY_MODE
      };
      const dataHandler: photoAccessHelper.MediaAssetDataHandler<ArrayBuffer> = {
        onDataPrepared: (data: ArrayBuffer): void => {
          if (data.byteLength <= 0) {
            reject(new Error('图片内容为空，请重新选择后再试'));
            return;
          }
          resolve(new Uint8Array(data));
        }
      };
      photoAccessHelper.MediaAssetManager.requestImageData(context, asset, requestOptions, dataHandler)
        .catch(() => {
          reject(new Error('无法读取系统相册授权图片，请重新选择后再试'));
        });
    });
  }

  /**
   * 读取应用可访问的 file URI。
   * 该路径只接收调用方已完成授权边界判断的路径，不输出真实路径。
   */
  private static readFileUriBytes(uri: string): Uint8Array {
    return ImageCropService.readFilePathBytes(ImageCropService.toFilePath(uri));
  }

  /**
   * 读取 Document picker 本轮授权返回的图片内容。
   * 该分支不接受普通本地路径来源标记，也不把 URI 或真实路径写入错误信息。
   */
  private static readDocumentPickerImageBytes(uri: string): Uint8Array {
    try {
      return ImageCropService.readDocumentPickerImageBytesByRandomAccessFile(uri);
    } catch (_) {
      return ImageCropService.readDocumentPickerImageBytesByOpenSync(uri);
    }
  }

  /**
   * 优先使用 RandomAccessFile 读取 DocumentViewPicker 图片 URI；失败时由外层尝试 fd 兜底。
   */
  private static readDocumentPickerImageBytesByRandomAccessFile(uri: string): Uint8Array {
    let file: fileIo.RandomAccessFile | undefined = undefined;
    try {
      file = fileIo.createRandomAccessFileSync(uri, fileIo.OpenMode.READ_ONLY);
      const stat = fileIo.statSync(file.fd);
      if (stat.size <= 0) {
        throw new Error('图片内容为空，请重新选择后再试');
      }
      const buffer = new ArrayBuffer(stat.size);
      const readLength = file.readSync(buffer, { offset: 0, length: stat.size });
      if (readLength <= 0) {
        throw new Error('无法读取图片内容，请重新选择后再试');
      }
      return new Uint8Array(buffer, 0, readLength);
    } catch (_) {
      throw new Error('无法读取系统文件选择的图片，请重新选择后再试');
    } finally {
      if (file !== undefined) {
        file.close();
      }
    }
  }

  /**
   * 使用 openSync + fd 兜底读取 DocumentViewPicker 图片 URI。
   * 部分系统文件服务允许 Image 组件预览 URI，但不支持 createRandomAccessFileSync 直接读取。
   */
  private static readDocumentPickerImageBytesByOpenSync(uri: string): Uint8Array {
    let file: fileIo.File | undefined = undefined;
    try {
      file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
      const stat = fileIo.statSync(file.fd);
      if (stat.size <= 0) {
        throw new Error('图片内容为空，请重新选择后再试');
      }
      const buffer = new ArrayBuffer(stat.size);
      const readLength = fileIo.readSync(file.fd, buffer, { offset: 0, length: stat.size });
      if (readLength <= 0) {
        throw new Error('无法读取图片内容，请重新选择后再试');
      }
      return new Uint8Array(buffer, 0, readLength);
    } catch (_) {
      throw new Error('无法读取系统文件选择的图片，请重新选择后再试');
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
   * 将 file URI 转为本地路径。
   * 调用前必须已经完成来源校验，避免任意本地路径绕过 picker 授权边界。
   */
  private static toFilePath(uri: string): string {
    return uri.startsWith('file://') ? uri.substring(7) : uri;
  }

  /**
   * 判断待读取路径是否仍位于允许目录内。
   * 仅做前端本地防护；授权 media URI 仍必须走系统 picker 授权分支。
   */
  private static isUnderDirectory(filePath: string, directory: string): boolean {
    const normalizedDirectory = directory.endsWith('/') ? directory : `${directory}/`;
    return filePath === directory || filePath.startsWith(normalizedDirectory);
  }

  /**
   * 读取已校验路径的文件字节。
   * 安全边界：调用方必须先确认路径位于允许目录内；本方法不输出真实路径或图片内容。
   */
  private static readFilePathBytes(filePath: string): Uint8Array {
    let file: fileIo.RandomAccessFile | undefined = undefined;
    try {
      file = fileIo.createRandomAccessFileSync(filePath, fileIo.OpenMode.READ_ONLY);
      const stat = fileIo.statSync(file.fd);
      if (stat.size <= 0) {
        throw new Error('图片内容为空，请重新选择后再试');
      }
      const buffer = new ArrayBuffer(stat.size);
      const readLength = file.readSync(buffer, { offset: 0, length: stat.size });
      if (readLength <= 0) {
        throw new Error('无法读取图片内容，请重新选择后再试');
      }
      return new Uint8Array(buffer, 0, readLength);
    } finally {
      if (file !== undefined) {
        file.close();
      }
    }
  }
}
