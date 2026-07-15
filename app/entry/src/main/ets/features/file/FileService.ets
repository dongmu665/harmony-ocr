import { common } from '@kit.AbilityKit';
import { request } from '@kit.BasicServicesKit';
import { fileIo } from '@kit.CoreFileKit';
import { dataSharePredicates } from '@kit.ArkData';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { util } from '@kit.ArkTS';
import { http } from '@kit.NetworkKit';
import { ApiConfig } from '../../common/config/ApiConfig';
import { HttpClient } from '../../common/network/HttpClient';
import { ApiError, ApiResponse } from '../../common/network/ApiTypes';
import { TokenStorage } from '../../common/storage/TokenStorage';
import { DeviceImageSelection } from '../ocr/DeviceOcrModels';
import { ImageUploadNormalizeService } from '../ocr/ImageUploadNormalizeService';
import { FileObject, FileUploadRequest } from './FileModels';

/**
 * UploadHeaders 限定系统 uploadFile 能接收的上传请求头。
 * 安全边界：Authorization 只传给系统上传任务，不进入错误消息、页面状态或调试输出。
 */
class UploadHeaders {
  Authorization?: string;
}

/**
 * FileService 负责 files 模块 API 调用。
 * 维护说明：uploadFile 已接入 OCR 结果页的用户确认保存路径；调用方必须先获得用户主动选择的短期 URI。
 * 安全约束：multipart 上传绕过 HttpClient，因此本类必须自行处理 401 本地会话清理，且不得输出本地路径或 Authorization。
 */
export class FileService {
  private static readonly CROP_OUTPUT_PREFIX: string = 'ocr-crop-output-';
  private static allowDevRawFileUpload: boolean = false;

  /**
   * 仅供 debug/test E2E 临时开启开发测试 rawfile 上传。
   * 安全边界：默认关闭，release 与常规用户流程不得依赖该开关。
   */
  static setDevRawFileUploadEnabled(enabled: boolean): void {
    FileService.allowDevRawFileUpload = enabled;
  }

  /**
   * 执行真实文件 multipart 上传。
   * 参数 context 由结果页显式传入；file.uri 只交给系统上传任务，不写入日志或错误消息。
   * 返回值为后端统一 Result.data；调用方只能使用后端返回的 objectKey 关联 record。
   */
  static async uploadFile(context: common.UIAbilityContext, file: FileUploadRequest): Promise<FileObject> {
    const accessToken = await TokenStorage.getAccessToken();
    if (accessToken.length === 0) {
      throw new ApiError('UNAUTHORIZED', '请先登录后再上传文件', 401);
    }
    if (file.rawFileName !== undefined && file.rawFileName.length > 0) {
      return FileService.uploadDevRawFile(context, file, accessToken);
    }
    if (FileService.shouldNormalizeImageUpload(file)) {
      return FileService.uploadNormalizedImageFile(context, file, accessToken);
    }

    const headers: UploadHeaders = new UploadHeaders();
    headers.Authorization = `Bearer ${accessToken}`;
    try {
      const uploadTask = await request.uploadFile(context, {
        url: `${ApiConfig.BASE_URL}${ApiConfig.API_PREFIX}/files/upload`,
        header: headers,
        method: 'POST',
        files: [{
          name: 'file',
          filename: file.fileName,
          uri: file.uri,
          type: file.mimeType
        }],
        data: []
      });
      return await FileService.waitForUploadResult(uploadTask);
    } catch (error) {
      if (FileService.canRetryAsPickerUriMultipart(file, error)) {
        return FileService.uploadPickerUriAsMultipart(context, file, accessToken);
      }
      if (FileService.canRetryAsDocumentPickerImageMultipart(file, error)) {
        return FileService.uploadDocumentPickerImageAsMultipart(file, accessToken);
      }
      if (FileService.canRetryAsGeneratedCropMultipart(context, file, error)) {
        return FileService.uploadGeneratedCropCacheAsMultipart(context, file, accessToken);
      }
      throw error as Error;
    }
  }

  /**
   * 查询当前用户有权访问的文件元数据。
   * 参数 id 来自后端文件对象 ID；返回值不得被用来绕过 records ownership 校验。
   */
  static async getFile(id: string): Promise<FileObject> {
    return HttpClient.get<FileObject>(`/files/${encodeURIComponent(id)}`, { authorized: true });
  }

  /**
   * 删除当前用户有权访问的文件对象。
   * 安全边界：前端只提交文件 ID，真实对象存储删除和 ownership 校验由后端执行。
   */
  static async deleteFile(id: string): Promise<void> {
    return HttpClient.delete<void>(`/files/${encodeURIComponent(id)}`, { authorized: true });
  }

  /**
   * 解析系统上传任务完成事件。
   * 返回值只取后端统一 Result.data；错误消息不包含本地文件路径、Token 或 Authorization。
   */
  private static async waitForUploadResult(uploadTask: request.UploadTask): Promise<FileObject> {
    return new Promise<FileObject>((resolve: (value: FileObject) => void, reject: (reason: ApiError) => void) => {
      const onComplete = (states: Array<request.TaskState>): void => {
        try {
          uploadTask.off('complete', onComplete);
          uploadTask.off('fail', onFail);
          const state = states.length > 0 ? states[0] : undefined;
          if (!state || state.message.length === 0) {
            reject(new ApiError('INVALID_RESPONSE', '文件上传响应为空', 0));
            return;
          }
          const apiResponse = JSON.parse(state.message) as ApiResponse<FileObject>;
          if (!apiResponse.success) {
            if (FileService.isUnauthorizedResponse(apiResponse.code)) {
              TokenStorage.clearTokens().catch(() => {});
            }
            reject(new ApiError(apiResponse.code, apiResponse.message, 0));
            return;
          }
          if (apiResponse.data === undefined) {
            reject(new ApiError('INVALID_RESPONSE', '文件上传响应缺少文件数据', 0));
            return;
          }
          if (apiResponse.data.objectKey.length === 0) {
            reject(new ApiError('INVALID_RESPONSE', '文件上传响应缺少对象 key', 0));
            return;
          }
          resolve(apiResponse.data);
        } catch (_) {
          reject(new ApiError('INVALID_RESPONSE', '文件上传响应格式错误', 0));
        }
      };
      const onFail = (_states: Array<request.TaskState>): void => {
        uploadTask.off('complete', onComplete);
        uploadTask.off('fail', onFail);
        reject(new ApiError('UPLOAD_FAILED', '文件上传失败，请稍后重试', 0));
      };
      uploadTask.on('complete', onComplete);
      uploadTask.on('fail', onFail);
    });
  }

  /**
   * 判断上传统一响应是否表示认证失效。
   * 参数 code 来自后端 Result.code；返回 true 时调用方应清理本地 Token，但不得记录 Authorization 或 Token 值。
   */
  private static isUnauthorizedResponse(code: string): boolean {
    return code === 'UNAUTHORIZED' || code === 'AUTH_TOKEN_EXPIRED';
  }

  /**
   * 判断当前文件是否属于 OCR 图片链路，必须先按真实 bytes 规范化后再上传。
   */
  private static shouldNormalizeImageUpload(file: FileUploadRequest): boolean {
    return file.rawFileName === undefined &&
      (file.uploadSource === 'system_picker' ||
        file.uploadSource === 'document_picker_image' ||
        file.uploadSource === 'generated_crop_cache');
  }

  /**
   * 读取本轮授权图片内容并按魔数/ImageKit 结果构造 multipart，避免沿用前端占位 MIME。
   */
  private static async uploadNormalizedImageFile(
    context: common.UIAbilityContext,
    file: FileUploadRequest,
    accessToken: string
  ): Promise<FileObject> {
    const content = await FileService.readImageUploadContent(context, file);
    return FileService.uploadBytesAsMultipart(file, accessToken, content, 'ImageNormalized');
  }

  /**
   * 根据可信 uploadSource 读取图片 bytes；错误信息保持脱敏，不包含 URI 或本地路径。
   */
  private static async readImageUploadContent(
    context: common.UIAbilityContext,
    file: FileUploadRequest
  ): Promise<Uint8Array> {
    if (file.uploadSource === 'system_picker') {
      return FileService.readPickerUriContent(context, file.uri);
    }
    if (file.uploadSource === 'document_picker_image') {
      return FileService.readDocumentPickerImageContent(file.uri);
    }
    if (file.uploadSource === 'generated_crop_cache') {
      return FileService.readGeneratedCropCacheContent(context, file);
    }
    throw new ApiError('INVALID_FILE', '当前图片来源不可上传，请重新选择图片后再试', 0);
  }

  /**
   * 判断是否允许把真实 picker URI 作为手工 multipart 重试。
   * 该兜底只处理用户通过系统 PhotoViewPicker 授权返回的媒体 URI；不会把 rawfile、沙箱路径或开发测试入口包装成真实相册能力。
   */
  private static canRetryAsPickerUriMultipart(file: FileUploadRequest, error: Error): boolean {
    const apiError = error as ApiError;
    if (apiError.statusCode === 401 || apiError.code === 'UNAUTHORIZED' || apiError.code === 'AUTH_TOKEN_EXPIRED') {
      return false;
    }
    return file.rawFileName === undefined && file.uploadSource === 'system_picker' && file.uri.startsWith('file://media/');
  }

  /**
   * 判断是否允许把 Document picker 返回的图片 URI 作为手工 multipart 重试。
   * 只接受本轮用户主动选择的图片来源标记，不接受 rawfile、任意 app cache 或未标注本地路径。
   */
  private static canRetryAsDocumentPickerImageMultipart(file: FileUploadRequest, error: Error): boolean {
    const apiError = error as ApiError;
    if (apiError.statusCode === 401 || apiError.code === 'UNAUTHORIZED' || apiError.code === 'AUTH_TOKEN_EXPIRED') {
      return false;
    }
    return file.rawFileName === undefined &&
      file.uploadSource === 'document_picker_image' &&
      file.mimeType.startsWith('image/') &&
      file.uri.length > 0;
  }

  /**
   * 判断是否允许把应用生成的裁剪缓存文件作为手工 multipart 重试。
   * 该兜底只接受本应用本轮生成的裁剪 JPEG，必须位于 context.cacheDir 且文件名带固定前缀；不接受任意 file URI、本地路径或 rawfile。
   */
  private static canRetryAsGeneratedCropMultipart(
    context: common.UIAbilityContext,
    file: FileUploadRequest,
    error: Error
  ): boolean {
    const apiError = error as ApiError;
    if (apiError.statusCode === 401 || apiError.code === 'UNAUTHORIZED' || apiError.code === 'AUTH_TOKEN_EXPIRED') {
      return false;
    }
    return file.rawFileName === undefined &&
      file.uploadSource === 'generated_crop_cache' &&
      file.mimeType === 'image/jpeg' &&
      file.fileName.startsWith(FileService.CROP_OUTPUT_PREFIX) &&
      file.uri.startsWith(`file://${context.cacheDir}/`);
  }

  /**
   * 使用 picker 授权的媒体 URI 读取图片字节并执行 multipart 上传。
   * 该方法只在系统 uploadFile 无法处理短期媒体 URI 时启用；URI 不写日志、不持久化，objectKey 仍只能来自后端响应。
   */
  private static async uploadPickerUriAsMultipart(
    context: common.UIAbilityContext,
    file: FileUploadRequest,
    accessToken: string
  ): Promise<FileObject> {
    const content = await FileService.readPickerUriContent(context, file.uri);
    return FileService.uploadBytesAsMultipart(file, accessToken, content, 'PickerUri');
  }

  /**
   * 使用 Document picker 授权的图片 URI 执行 multipart 上传。
   * URI 仅在内存中用于读取字节，不写日志、不持久化，objectKey 仍只能来自后端响应。
   */
  private static uploadDocumentPickerImageAsMultipart(
    file: FileUploadRequest,
    accessToken: string
  ): Promise<FileObject> {
    const content = FileService.readDocumentPickerImageContent(file.uri);
    return FileService.uploadBytesAsMultipart(file, accessToken, content, 'DocumentPickerImage');
  }

  /**
   * 读取并上传应用生成的裁剪输出缓存。
   * 该方法只服务真实 picker 之后生成的受控裁剪结果；失败时返回脱敏错误，不暴露缓存路径、URI 或 objectKey。
   */
  private static async uploadGeneratedCropCacheAsMultipart(
    context: common.UIAbilityContext,
    file: FileUploadRequest,
    accessToken: string
  ): Promise<FileObject> {
    const content = FileService.readGeneratedCropCacheContent(context, file);
    return FileService.uploadBytesAsMultipart(file, accessToken, content, 'GeneratedCrop');
  }

  /**
   * 复用手工 multipart 上传实现。
   * 参数 content 来自系统 picker 授权字节、受控裁剪缓存或显式开发测试 rawfile；方法不记录 Authorization、URI、本地路径或 objectKey。
   */
  private static async uploadBytesAsMultipart(
    file: FileUploadRequest,
    accessToken: string,
    content: Uint8Array,
    boundaryTag: string
  ): Promise<FileObject> {
    const boundary = `----HarmonyOcr${boundaryTag}${Date.now()}`;
    const normalized = await ImageUploadNormalizeService.normalizeSelectionForUpload(
      FileService.toDeviceImageSelection(file),
      content
    );
    const body = FileService.buildMultipartBody(boundary, normalized.fileName, normalized.mimeType, normalized.content);
    const requestTask = http.createHttp();
    try {
      const response = await requestTask.request(`${ApiConfig.BASE_URL}${ApiConfig.API_PREFIX}/files/upload`, {
        method: http.RequestMethod.POST,
        header: {
          'Authorization': `Bearer ${accessToken}`,
          'Content-Type': `multipart/form-data; boundary=${boundary}`
        },
        connectTimeout: ApiConfig.REQUEST_TIMEOUT_MS,
        readTimeout: ApiConfig.REQUEST_TIMEOUT_MS,
        expectDataType: http.HttpDataType.STRING,
        extraData: body
      });
      return FileService.parseUploadResponse(String(response.result), response.responseCode);
    } finally {
      requestTask.destroy();
    }
  }

  /**
   * 将文件上传请求转换为图片规范化所需的最小选择对象；仅传递安全文件名和来源标签。
   */
  private static toDeviceImageSelection(file: FileUploadRequest): DeviceImageSelection {
    return {
      sourceType: 'album',
      uri: file.uri,
      fileName: file.fileName,
      mimeType: file.mimeType,
      rawFileName: file.rawFileName,
      uploadSource: file.uploadSource ?? (file.rawFileName !== undefined ? 'dev_rawfile' : 'system_picker')
    };
  }

  /**
   * 读取系统 picker 返回的短期媒体 URI 内容。
   * 方法只返回内存字节，不输出 URI 或本地路径；读取失败时给出脱敏错误，避免把用户媒体位置暴露到 UI 或日志。
   */
  private static async readPickerUriContent(context: common.UIAbilityContext, uri: string): Promise<Uint8Array> {
    try {
      return await FileService.readPickerUriContentByMediaAsset(context, uri);
    } catch (_) {
      return FileService.readPickerUriContentByFileIo(uri);
    }
  }

  /**
   * 通过 PhotoAccessHelper 按 picker URI 获取临时授权资产并读取原始图片数据。
   * 这是系统 picker 文档推荐的读取路径；只使用用户刚选择的 URI，不枚举图库，也不申请 READ_IMAGEVIDEO。
   */
  private static async readPickerUriContentByMediaAsset(
    context: common.UIAbilityContext,
    uri: string
  ): Promise<Uint8Array> {
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
        throw new ApiError('PICKER_URI_READ_FAILED', '无法读取系统相册授权图片，请重新选择后再试', 0);
      }
      const asset = await fetchResult.getFirstObject();
      return await FileService.requestAssetBytes(context, asset);
    } finally {
      fetchResult.close();
    }
  }

  /**
   * 请求单个授权 PhotoAsset 的图片字节。
   * 回调只在内存中返回 ArrayBuffer；失败信息保持脱敏，避免暴露完整 URI、本地路径或后端 objectKey。
   */
  private static async requestAssetBytes(
    context: common.UIAbilityContext,
    asset: photoAccessHelper.PhotoAsset
  ): Promise<Uint8Array> {
    return new Promise<Uint8Array>((resolve: (value: Uint8Array) => void, reject: (reason: ApiError) => void) => {
      const requestOptions: photoAccessHelper.RequestOptions = {
        deliveryMode: photoAccessHelper.DeliveryMode.HIGH_QUALITY_MODE
      };
      const dataHandler: photoAccessHelper.MediaAssetDataHandler<ArrayBuffer> = {
        onDataPrepared: (data: ArrayBuffer): void => {
          if (data.byteLength <= 0) {
            reject(new ApiError('INVALID_FILE', '用户选择的图片内容为空', 0));
            return;
          }
          resolve(new Uint8Array(data));
        }
      };
      photoAccessHelper.MediaAssetManager.requestImageData(context, asset, requestOptions, dataHandler)
        .catch(() => {
          reject(new ApiError('PICKER_URI_READ_FAILED', '无法读取系统相册授权图片，请重新选择后再试', 0));
        });
    });
  }

  /**
   * 在系统媒体资产读取不可用时，尝试用文件 API 读取 picker URI。
   * 该路径仍只接受用户选择的短期媒体 URI；若系统拒绝访问，向上抛出脱敏错误。
   */
  private static readPickerUriContentByFileIo(uri: string): Uint8Array {
    let file: fileIo.RandomAccessFile | undefined = undefined;
    try {
      file = fileIo.createRandomAccessFileSync(uri, fileIo.OpenMode.READ_ONLY);
      const stat = fileIo.statSync(file.fd);
      if (stat.size <= 0) {
        throw new ApiError('INVALID_FILE', '用户选择的图片内容为空', 0);
      }
      const buffer = new ArrayBuffer(stat.size);
      const readLength = file.readSync(buffer, { offset: 0, length: stat.size });
      if (readLength <= 0) {
        throw new ApiError('INVALID_FILE', '无法读取用户选择的图片', 0);
      }
      return new Uint8Array(buffer, 0, readLength);
    } catch (error) {
      if ((error as ApiError).code === 'INVALID_FILE') {
        throw error as Error;
      }
      throw new ApiError('PICKER_URI_READ_FAILED', '无法读取系统相册授权图片，请重新选择后再试', 0);
    } finally {
      if (file !== undefined) {
        file.close();
      }
    }
  }

  /**
   * 读取 Document picker 图片 URI 内容。
   * 错误向上保持脱敏，不包含 URI、路径、Token、Authorization 或 objectKey。
   */
  private static readDocumentPickerImageContent(uri: string): Uint8Array {
    let file: fileIo.RandomAccessFile | undefined = undefined;
    try {
      file = fileIo.createRandomAccessFileSync(uri, fileIo.OpenMode.READ_ONLY);
      const stat = fileIo.statSync(file.fd);
      if (stat.size <= 0) {
        throw new ApiError('INVALID_FILE', '用户选择的图片内容为空', 0);
      }
      const buffer = new ArrayBuffer(stat.size);
      const readLength = file.readSync(buffer, { offset: 0, length: stat.size });
      if (readLength <= 0) {
        throw new ApiError('INVALID_FILE', '无法读取用户选择的图片', 0);
      }
      return new Uint8Array(buffer, 0, readLength);
    } catch (error) {
      if ((error as ApiError).code === 'INVALID_FILE') {
        throw error as Error;
      }
      throw new ApiError('PICKER_URI_READ_FAILED', '无法读取系统文件选择的图片，请重新选择后再试', 0);
    } finally {
      if (file !== undefined) {
        file.close();
      }
    }
  }

  /**
   * 读取应用生成的受控裁剪缓存文件。
   * 安全边界：只接受 context.cacheDir 下、固定文件名前缀、JPEG MIME 的文件 URI；不把任意本地路径升级成可上传输入。
   */
  private static readGeneratedCropCacheContent(context: common.UIAbilityContext, file: FileUploadRequest): Uint8Array {
    if (!FileService.canUseGeneratedCropCacheFile(context, file)) {
      throw new ApiError('INVALID_FILE', '裁剪输出不可上传，请重新选择图片后再试', 0);
    }
    const filePath = file.uri.substring(7);
    let cacheFile: fileIo.RandomAccessFile | undefined = undefined;
    try {
      cacheFile = fileIo.createRandomAccessFileSync(filePath, fileIo.OpenMode.READ_ONLY);
      const stat = fileIo.statSync(cacheFile.fd);
      if (stat.size <= 0) {
        throw new ApiError('INVALID_FILE', '裁剪输出为空，请重新选择图片后再试', 0);
      }
      const buffer = new ArrayBuffer(stat.size);
      const readLength = cacheFile.readSync(buffer, { offset: 0, length: stat.size });
      if (readLength <= 0) {
        throw new ApiError('INVALID_FILE', '无法读取裁剪输出，请重新选择图片后再试', 0);
      }
      return new Uint8Array(buffer, 0, readLength);
    } catch (error) {
      if ((error as ApiError).code === 'INVALID_FILE') {
        throw error as Error;
      }
      throw new ApiError('INVALID_FILE', '无法读取裁剪输出，请重新选择图片后再试', 0);
    } finally {
      if (cacheFile !== undefined) {
        cacheFile.close();
      }
    }
  }

  /**
   * 校验裁剪缓存上传输入。
   * 只根据本应用生成时写入的来源标记、固定文件名前缀、MIME 和 cacheDir 边界放行，避免把任意 file URI 当成用户授权图片。
   */
  private static canUseGeneratedCropCacheFile(context: common.UIAbilityContext, file: FileUploadRequest): boolean {
    return file.rawFileName === undefined &&
      file.uploadSource === 'generated_crop_cache' &&
      file.mimeType === 'image/jpeg' &&
      file.fileName.startsWith(FileService.CROP_OUTPUT_PREFIX) &&
      file.uri.startsWith(`file://${context.cacheDir}/`);
  }

  /**
   * 上传明确标注的开发测试 rawfile。
   * 该路径只服务显式启用的开发测试图片入口；真实相册 URI 仍使用系统 uploadFile，避免把测试夹具伪装成真实相册能力。
   */
  private static async uploadDevRawFile(
    context: common.UIAbilityContext,
    file: FileUploadRequest,
    accessToken: string
  ): Promise<FileObject> {
    if (!FileService.allowDevRawFileUpload) {
      throw new ApiError('DEV_RAWFILE_DISABLED', '开发测试 rawfile 上传未启用', 0);
    }
    const rawFileName = file.rawFileName ?? '';
    const content: Uint8Array = await context.resourceManager.getRawFileContent(rawFileName);
    return FileService.uploadBytesAsMultipart(file, accessToken, content, 'DevelopmentRawFile');
  }

  /**
   * 构造 multipart/form-data 请求体。
   * 参数只包含开发测试图片的脱敏文件名和 rawfile 字节；不拼接本地路径、Token 或对象存储 key。
   */
  private static buildMultipartBody(
    boundary: string,
    fileName: string,
    mimeType: string,
    content: Uint8Array
  ): ArrayBuffer {
    const encoder = util.TextEncoder.create('utf-8');
    const safeName = fileName.replace(/["\r\n\\/]+/g, '_');
    const head = encoder.encodeInto(
      `--${boundary}\r\nContent-Disposition: form-data; name="file"; filename="${safeName}"\r\nContent-Type: ${mimeType}\r\n\r\n`
    );
    const tail = encoder.encodeInto(`\r\n--${boundary}--\r\n`);
    const body = new Uint8Array(head.length + content.length + tail.length);
    body.set(head, 0);
    body.set(content, head.length);
    body.set(tail, head.length + content.length);
    return body.buffer;
  }

  /**
   * 解析开发测试 multipart 上传响应。
   * 返回值只接受后端统一 Result.data；401 会清理本地 Token，错误消息不包含 Authorization 或本地文件路径。
   */
  private static async parseUploadResponse(rawBody: string, statusCode: number): Promise<FileObject> {
    let apiResponse: ApiResponse<FileObject>;
    try {
      apiResponse = JSON.parse(rawBody) as ApiResponse<FileObject>;
    } catch (_) {
      if (statusCode === 401) {
        await TokenStorage.clearTokens();
      }
      throw new ApiError('INVALID_RESPONSE', '文件上传响应格式错误', statusCode);
    }
    if (!apiResponse.success) {
      if (statusCode === 401 || FileService.isUnauthorizedResponse(apiResponse.code)) {
        await TokenStorage.clearTokens();
      }
      throw new ApiError(apiResponse.code, apiResponse.message, statusCode);
    }
    if (apiResponse.data === undefined || apiResponse.data.objectKey.length === 0) {
      throw new ApiError('INVALID_RESPONSE', '文件上传响应缺少对象 key', statusCode);
    }
    return apiResponse.data;
  }
}
