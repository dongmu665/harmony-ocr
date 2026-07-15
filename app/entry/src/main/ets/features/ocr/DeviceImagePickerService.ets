import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { DeviceImagePickerMode, DeviceImageSelection } from './DeviceOcrModels';
import { OcrSourceType } from './OcrModels';

/**
 * DeviceImagePickerService 封装 HarmonyOS 系统图片选择器，属于 features/ocr 设备输入层。
 * 维护说明：本服务只在用户主动操作后获取临时授权 URI，不读取非用户选择图片，不上传文件，也不记录本地 URI。
 */
export class DeviceImagePickerService {
  private static readonly MAX_IMAGE_SELECT_NUMBER: number = 20;

  /**
   * 打开系统图片选择器。
   * 参数 mode 为 camera 时允许用户在系统选择器内拍照；为 album 时仅选择已有图片。返回值只包含短期 URI 和非敏感上传文件名。
   */
  static async selectImage(mode: DeviceImagePickerMode): Promise<DeviceImageSelection | undefined> {
    const selections = await DeviceImagePickerService.selectImages(mode, 1);
    return selections.length === 0 ? undefined : selections[0];
  }

  /**
   * 打开系统图片选择器并允许一次选择多张图片。
   * 安全边界：返回值只保留临时授权 URI 与安全文件名；调用方不得把 URI 写入 @State、日志或持久化存储。
   */
  static async selectImages(mode: DeviceImagePickerMode, maxSelectNumber: number = DeviceImagePickerService.MAX_IMAGE_SELECT_NUMBER): Promise<DeviceImageSelection[]> {
    const options = new photoAccessHelper.PhotoSelectOptions();
    options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
    options.maxSelectNumber = DeviceImagePickerService.normalizeMaxSelectNumber(mode, maxSelectNumber);
    options.isPhotoTakingSupported = mode === 'camera';

    const picker = new photoAccessHelper.PhotoViewPicker();
    const result = await picker.select(options);
    if (result.photoUris.length === 0) {
      return [];
    }

    const sourceType: OcrSourceType = mode === 'album' ? 'album' : 'camera';
    const selectedAt = Date.now();
    const selections: DeviceImageSelection[] = [];
    result.photoUris.forEach((uri: string, index: number) => {
      selections.push({
        sourceType: sourceType,
        uri: uri,
        fileName: DeviceImagePickerService.createSafeFileName(sourceType, selectedAt, index),
        mimeType: 'image/*',
        uploadSource: 'system_picker'
      });
    });
    return selections;
  }

  /**
   * 统一限制系统选择器多选数量，避免超出当前批量 OCR 页面可展示和后端常见套餐提示范围。
   * 说明：这不是业务额度判断，最终仍以后端校验为准；camera 模式保持单选以兼容系统拍照入口。
   */
  private static normalizeMaxSelectNumber(mode: DeviceImagePickerMode, maxSelectNumber: number): number {
    if (mode === 'camera') {
      return 1;
    }
    if (maxSelectNumber <= 1) {
      return 1;
    }
    return Math.min(maxSelectNumber, DeviceImagePickerService.MAX_IMAGE_SELECT_NUMBER);
  }

  /**
   * 生成上传用安全文件名。
   * 返回值不包含用户原始文件名、本地路径、账号信息或对象存储 key，避免泄露隐私上下文。
   */
  private static createSafeFileName(sourceType: OcrSourceType, selectedAt: number, index: number): string {
    const prefix = sourceType === 'album' ? 'album' : 'camera';
    return `ocr-${prefix}-${selectedAt}-${index + 1}`;
  }
}
