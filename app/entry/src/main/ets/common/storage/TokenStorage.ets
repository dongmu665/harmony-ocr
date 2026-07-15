import { common } from '@kit.AbilityKit';
import { asset } from '@kit.AssetStoreKit';
import { util } from '@kit.ArkTS';

/**
 * TokenPair 表示认证接口返回的一组会话凭证。
 * 安全边界：字段只允许传入 TokenStorage，不得用于 UI 展示、日志输出或普通持久化。
 */
export interface TokenPair {
  accessToken: string;
  refreshToken: string;
}

/**
 * TokenStorage 负责客户端会话 Token 的统一读写，属于 common/storage 模块。
 * 维护说明：V1.0 使用 HarmonyOS AssetStoreKit 保存 accessToken/refreshToken，不再把 Token 写入普通键值存储；任何失败都降级为未登录状态。
 */
export class TokenStorage {
  private static readonly ACCESS_TOKEN_ALIAS: string = 'harmony_ocr_access_token';
  private static readonly REFRESH_TOKEN_ALIAS: string = 'harmony_ocr_refresh_token';

  private static accessToken: string = '';
  private static refreshToken: string = '';
  private static initialization: Promise<void> | undefined = undefined;
  private static lastPersistenceFailure: boolean = false;

  /**
   * 初始化设备安全资产中的 Token 缓存。
   * 参数 context 保持 EntryAbility 调用契约；AssetStoreKit 不需要直接使用 context，读取失败会清空内存并进入未登录状态。
   */
  static async initialize(context: common.UIAbilityContext): Promise<void> {
    context;
    TokenStorage.initialization = TokenStorage.loadFromAssetStore();
    await TokenStorage.initialization;
  }

  /**
   * 保存登录或刷新后获得的 Access Token 和 Refresh Token。
   * 参数会先写入 AssetStoreKit，写入成功后才更新内存缓存；方法不会记录、展示或上传 Token 内容。
   */
  static async saveTokens(accessToken: string, refreshToken: string): Promise<void> {
    await TokenStorage.ensureInitialized();
    try {
      await TokenStorage.putAsset(TokenStorage.ACCESS_TOKEN_ALIAS, accessToken);
      try {
        await TokenStorage.putAsset(TokenStorage.REFRESH_TOKEN_ALIAS, refreshToken);
      } catch (_) {
        await TokenStorage.removeAssetQuietly(TokenStorage.ACCESS_TOKEN_ALIAS);
        await TokenStorage.removeAssetQuietly(TokenStorage.REFRESH_TOKEN_ALIAS);
        throw new Error('本地安全 Token 存储失败，请重新登录');
      }
      TokenStorage.accessToken = accessToken;
      TokenStorage.refreshToken = refreshToken;
      TokenStorage.lastPersistenceFailure = false;
    } catch (_) {
      TokenStorage.accessToken = '';
      TokenStorage.refreshToken = '';
      TokenStorage.lastPersistenceFailure = true;
      throw new Error('本地安全 Token 存储失败，请重新登录');
    }
  }

  /**
   * 兼容旧调用方式保存 TokenPair。
   * 参数来自认证响应；内部仍统一写入 AssetStoreKit，不保留普通键值存储兜底。
   */
  static async saveTokenPair(tokens: TokenPair): Promise<void> {
    await TokenStorage.saveTokens(tokens.accessToken, tokens.refreshToken);
  }

  /**
   * V1.2 E2E-only 内存会话注入。脚本 finally 会恢复源码；不写 AssetStoreKit，不输出 Token。
   */
  static setE2eMemoryTokens(accessToken: string, refreshToken: string): void {
    TokenStorage.accessToken = accessToken;
    TokenStorage.refreshToken = refreshToken;
    TokenStorage.initialization = undefined;
    TokenStorage.lastPersistenceFailure = false;
  }

  /**
   * 读取当前 Access Token。
   * 返回值可能为空；调用方不得将返回值写入日志、UI 或异常消息。
   */
  static async getAccessToken(): Promise<string> {
    await TokenStorage.ensureInitialized();
    return TokenStorage.accessToken;
  }

  /**
   * 读取当前 Refresh Token。
   * 返回值仅用于刷新或退出登录请求，不得持久化到普通存储或输出到日志。
   */
  static async getRefreshToken(): Promise<string> {
    await TokenStorage.ensureInitialized();
    return TokenStorage.refreshToken;
  }

  /**
   * 清理本地会话 Token。
   * 用于退出登录、401 失效处理和账号注销；会同步清理内存缓存和 AssetStoreKit 中的安全资产。
   */
  static async clearTokens(): Promise<boolean> {
    await TokenStorage.ensureInitialized();
    let failed = false;
    try {
      await TokenStorage.removeAsset(TokenStorage.ACCESS_TOKEN_ALIAS);
    } catch (_) {
      failed = true;
    }
    try {
      await TokenStorage.removeAsset(TokenStorage.REFRESH_TOKEN_ALIAS);
    } catch (_) {
      failed = true;
    }
    // 401 清理可能和启动期 AssetStore 初始化并发；删除资产后再清内存，避免旧 Token 被初始化回写。
    TokenStorage.accessToken = '';
    TokenStorage.refreshToken = '';
    TokenStorage.lastPersistenceFailure = failed;
    return !failed;
  }

  /**
   * 兼容旧调用方的会话清理入口。
   * 返回值沿用 clearTokens 语义，表示 AssetStoreKit 与内存清理是否全部成功。
   */
  static async clear(): Promise<boolean> {
    return TokenStorage.clearTokens();
  }

  /**
   * 仅清理内存缓存。
   * 该方法只用于测试或短生命周期恢复场景，不删除 AssetStoreKit 中的安全资产。
   */
  static clearMemoryOnly(): void {
    TokenStorage.accessToken = '';
    TokenStorage.refreshToken = '';
  }

  /**
   * 判断当前内存中是否存在完整 Token 对。
   * 如果 AssetStoreKit 读取失败，初始化阶段会清空 Token，因此这里会返回 false。
   */
  static async hasToken(): Promise<boolean> {
    await TokenStorage.ensureInitialized();
    return TokenStorage.accessToken.length > 0 && TokenStorage.refreshToken.length > 0;
  }

  /**
   * 兼容旧页面命名的登录态判断。
   * 返回 true 仅表示本地存在完整 Token 对，接口权限仍以后端校验为准。
   */
  static async hasSession(): Promise<boolean> {
    return TokenStorage.hasToken();
  }

  /**
   * 返回最近一次本地持久化清理是否失败。
   * 该状态只用于非敏感提示，不包含 Token 值、异常详情或设备路径。
   */
  static hasLastPersistenceFailure(): boolean {
    return TokenStorage.lastPersistenceFailure;
  }

  private static async ensureInitialized(): Promise<void> {
    if (TokenStorage.initialization) {
      await TokenStorage.initialization;
    }
  }

  private static async loadFromAssetStore(): Promise<void> {
    try {
      TokenStorage.accessToken = await TokenStorage.queryAsset(TokenStorage.ACCESS_TOKEN_ALIAS);
      TokenStorage.refreshToken = await TokenStorage.queryAsset(TokenStorage.REFRESH_TOKEN_ALIAS);
      TokenStorage.lastPersistenceFailure = false;
    } catch (_) {
      TokenStorage.accessToken = '';
      TokenStorage.refreshToken = '';
      TokenStorage.lastPersistenceFailure = true;
    }
  }

  /**
   * 写入单个 Token 安全资产。
   * alias 只标识 Token 类型，不包含用户信息；Token 明文只交给 AssetStoreKit，不进入日志。
   */
  private static async putAsset(alias: string, token: string): Promise<void> {
    const attributes = TokenStorage.createBaseAssetMap(alias);
    attributes.set(asset.Tag.SECRET, TokenStorage.encode(token));
    attributes.set(asset.Tag.CONFLICT_RESOLUTION, asset.ConflictResolution.OVERWRITE);
    await asset.add(attributes);
  }

  /**
   * 查询单个 Token 安全资产。
   * 未找到或读取失败时返回空字符串，让调用方按未登录处理。
   */
  private static async queryAsset(alias: string): Promise<string> {
    const query = TokenStorage.createBaseAssetMap(alias);
    query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
    const results = await asset.query(query);
    if (results.length === 0) {
      return '';
    }
    const secret = results[0].get(asset.Tag.SECRET);
    if (secret instanceof Uint8Array) {
      return TokenStorage.decode(secret);
    }
    return '';
  }

  private static async removeAsset(alias: string): Promise<void> {
    const query = TokenStorage.createBaseAssetMap(alias);
    query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ATTRIBUTES);
    const existing = await asset.query(query);
    if (existing.length === 0) {
      return;
    }
    query.delete(asset.Tag.RETURN_TYPE);
    await asset.remove(query);
  }

  /**
   * 安静删除单个 Token 安全资产。
   * 该方法只用于保存失败后的回滚清理，不向上抛出底层删除异常，避免把半写入状态留在设备上。
   */
  private static async removeAssetQuietly(alias: string): Promise<void> {
    try {
      await TokenStorage.removeAsset(alias);
    } catch (_) {
    }
  }

  private static createBaseAssetMap(alias: string): asset.AssetMap {
    const map: asset.AssetMap = new Map<asset.Tag, asset.Value>();
    map.set(asset.Tag.ALIAS, TokenStorage.encode(alias));
    map.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED);
    map.set(asset.Tag.AUTH_TYPE, asset.AuthType.NONE);
    map.set(asset.Tag.SYNC_TYPE, asset.SyncType.NEVER);
    return map;
  }

  private static encode(value: string): Uint8Array {
    const encoder = util.TextEncoder.create('utf-8');
    return encoder.encodeInto(value);
  }

  private static decode(value: Uint8Array): string {
    const decoder = util.TextDecoder.create('utf-8');
    return decoder.decodeToString(value);
  }
}
