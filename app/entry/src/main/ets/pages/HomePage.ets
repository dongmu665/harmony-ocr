import { AppRoutes } from '../common/routes/AppRoutes';
import { AppNavigator } from '../common/routes/AppNavigator';
import { AppTheme } from '../common/theme/AppTheme';
import { AppMotion } from '../common/theme/AppMotion';
import { AppBottomNav } from '../components/AppBottomNav';
import {
  HtmlAppBar,
  HtmlListRow,
  HtmlSectionHead,
  HtmlStatusBar,
  HtmlToolChip
} from '../components/BrandComponents';
import { HomeDashboardItem } from '../features/home/HomeDashboardModels';
import { HomeDashboardService } from '../features/home/HomeDashboardService';
import { HistoryState } from '../features/history/HistoryState';
import { OcrSourceType } from '../features/ocr/OcrModels';

/**
 * HomePage 对齐 V2.0 HTML 原型首页，承载扫描入口、AI 快捷处理、待处理和最近记录。
 * 维护边界：列表数据来自当前用户后端摘要；页面不读取或展示 Token、媒体 URI、objectKey 或 OCR 全文。
 */
@Entry
@Component
struct HomePage {
  @State sessionText: string = '正在同步记录';
  @State pendingMeta: string = '正在同步记录';
  @State recentMeta: string = '正在同步记录';
  @State pendingItems: HomeDashboardItem[] = [];
  @State recentItems: HomeDashboardItem[] = [];
  @State pressedSource: string = '';
  @State scanEntered: boolean = false;
  @State aiEntered: boolean = false;
  @State pendingEntered: boolean = false;
  @State recentEntered: boolean = false;
  @State scanLineActive: boolean = false;

  aboutToAppear(): void {
    this.refreshDashboard();
    this.triggerCardReveal();
  }

  /**
   * 首页卡片按 HTML 原型的 40ms stagger 轻微淡入上移，只影响视觉展示。
   */
  private triggerCardReveal(): void {
    this.revealCard(() => this.scanEntered = true, 0);
    this.revealCard(() => this.aiEntered = true, 1);
    this.revealCard(() => this.pendingEntered = true, 2);
    this.revealCard(() => this.recentEntered = true, 3);
  }

  private revealCard(update: () => void, index: number): void {
    setTimeout(() => {
      this.getUIContext().animateTo({ duration: AppMotion.DURATION_NORMAL, curve: Curve.EaseOut }, update);
    }, index * AppMotion.STAGGER_CARD_MS);
  }

  /**
   * 刷新首页真实读模型。
   * 安全边界：聚合服务只返回脱敏摘要；失败时显示明确空态，不回退到演示文件名。
   */
  private async refreshDashboard(): Promise<void> {
    const dashboard = await HomeDashboardService.load();
    this.pendingItems = dashboard.pendingItems;
    this.recentItems = dashboard.recentItems;
    this.pendingMeta = dashboard.pendingMeta;
    this.recentMeta = dashboard.recentMeta;
    this.sessionText = dashboard.statusText;
  }

  /**
   * 进入真实 OCR 主链路。
   * 参数 sourceType 只决定拍照或相册路由，图片选择、裁剪和识别仍由后续页面处理。
   */
  private enterOcrFlow(sourceType: OcrSourceType): void {
    AppNavigator.push(this.getUIContext(), sourceType === 'album' ? AppRoutes.ALBUM : AppRoutes.CAPTURE);
  }

  /**
   * 触发首页扫描主按钮的一次性扫描线动效。
   * 说明：动效只表达用户已启动扫描，不读取图片、媒体 URI、OCR 文本或账号数据。
   */
  private triggerScanMain(): void {
    this.scanLineActive = false;
    this.getUIContext().animateTo({ duration: AppMotion.DURATION_SWITCH, curve: Curve.EaseOut }, () => {
      this.scanLineActive = true;
    });
    setTimeout(() => {
      this.enterOcrFlow('album');
    }, AppMotion.DURATION_SWITCH);
  }

  private openDashboardItem(item: HomeDashboardItem): void {
    if (item.route === 'recordDetail' && item.recordId !== undefined) {
      HistoryState.selectRecord(item.recordId);
      AppNavigator.push(this.getUIContext(), AppRoutes.RECORD_DETAIL);
      return;
    }
    if (item.route === 'batch') {
      AppNavigator.push(this.getUIContext(), AppRoutes.BATCH_OCR);
      return;
    }
    if (item.route === 'export') {
      AppNavigator.push(this.getUIContext(), AppRoutes.EXPORT_CENTER);
      return;
    }
    if (item.route === 'ai') {
      AppNavigator.push(this.getUIContext(), AppRoutes.AI_WORKSPACE);
      return;
    }
    AppNavigator.push(this.getUIContext(), AppRoutes.HISTORY);
  }

  @Builder
  private emptyListState(title: string, detail: string) {
    Column({ space: 6 }) {
      Text(title)
        .fontSize(AppTheme.FONT_META)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.COLOR_TEXT)
        .width('100%')
      Text(detail)
        .fontSize(AppTheme.FONT_CAPTION)
        .fontColor(AppTheme.COLOR_TEXT_SUBTLE)
        .lineHeight(AppTheme.LINE_CAPTION)
        .width('100%')
    }
    .width('100%')
    .height(92)
    .justifyContent(FlexAlign.Center)
    .padding({ left: 4, right: 4 })
  }

  /**
   * 首页扫描入口使用四角取景框，替代字体方框字符，避免设备 glyph 差异并贴近 HTML 参考图标。
   */
  @Builder
  private scanFrameIcon() {
    Stack() {
      Row() {
        Column()
          .width(7)
          .height(2)
          .backgroundColor(AppTheme.COLOR_TEXT_INVERSE)
        Blank()
        Column()
          .width(7)
          .height(2)
          .backgroundColor(AppTheme.COLOR_TEXT_INVERSE)
      }
      .width(22)
      .height(2)
      .position({ x: 0, y: 0 })

      Row() {
        Column()
          .width(2)
          .height(7)
          .backgroundColor(AppTheme.COLOR_TEXT_INVERSE)
        Blank()
        Column()
          .width(2)
          .height(7)
          .backgroundColor(AppTheme.COLOR_TEXT_INVERSE)
      }
      .width(22)
      .height(7)
      .position({ x: 0, y: 0 })

      Row() {
        Column()
          .width(7)
          .height(2)
          .backgroundColor(AppTheme.COLOR_TEXT_INVERSE)
        Blank()
        Column()
          .width(7)
          .height(2)
          .backgroundColor(AppTheme.COLOR_TEXT_INVERSE)
      }
      .width(22)
      .height(2)
      .position({ x: 0, y: 20 })

      Row() {
        Column()
          .width(2)
          .height(7)
          .backgroundColor(AppTheme.COLOR_TEXT_INVERSE)
        Blank()
        Column()
          .width(2)
          .height(7)
          .backgroundColor(AppTheme.COLOR_TEXT_INVERSE)
      }
      .width(22)
      .height(7)
      .position({ x: 0, y: 15 })

      // 中文说明：补齐 HTML 扫描图标内部的两条文档线，避免只剩四角取景框导致首页主按钮显得过空。
      Column()
        .width(11)
        .height(2)
        .backgroundColor(AppTheme.COLOR_TEXT_INVERSE)
        .position({ x: 6, y: 11 })
      Column()
        .width(7)
        .height(2)
        .backgroundColor(AppTheme.COLOR_TEXT_INVERSE)
        .position({ x: 6, y: 15 })
    }
    .width(22)
    .height(22)
  }

  @Builder
  private scanMainAction() {
    Button() {
      Stack() {
        Column({ space: 0 }) {
          this.scanFrameIcon()
          Blank()
          Text('扫描文档')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.COLOR_TEXT_INVERSE)
            .width('100%')
          Text('自动裁切 · 透视校正')
            .fontSize(AppTheme.FONT_CAPTION)
            .fontColor(AppTheme.COLOR_SCAN_TEXT_MUTED)
            .width('100%')
        }
        .width('100%')
        .height('100%')
        .padding(15)
        .justifyContent(FlexAlign.SpaceBetween)
        .alignItems(HorizontalAlign.Start)

        Column()
          .width('72%')
          .height(2)
          .backgroundColor(AppTheme.COLOR_SCAN_LINE)
          .opacity(this.scanLineActive ? 0.92 : 0)
          .translate({ y: this.scanLineActive ? 22 : -36 })
          .animation({ duration: AppMotion.DURATION_SWITCH, curve: Curve.EaseOut })
      }
      .width('100%')
      .height('100%')
    }
    .layoutWeight(1.16)
    .height(118)
    .type(ButtonType.Normal)
    .backgroundColor(AppTheme.COLOR_DARK)
    .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_SCAN_BORDER })
    .borderRadius(18)
    .scale({ x: this.pressedSource === 'album' ? AppMotion.PRESS_SCALE : 1, y: this.pressedSource === 'album' ? AppMotion.PRESS_SCALE : 1 })
    .animation({ duration: AppMotion.DURATION_FAST, curve: Curve.EaseOut })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.pressedSource = 'album';
      }
      if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.pressedSource = '';
      }
    })
    .onClick(() => this.triggerScanMain())
  }

  @Builder
  private actionSmall(title: string, detail: string, sourceType: string) {
    Button() {
      Column({ space: 3 }) {
        Text(title)
          .fontSize(AppTheme.FONT_META)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.COLOR_TEXT)
          .maxLines(1)
          .width('100%')
        Text(detail)
          .fontSize(AppTheme.FONT_CAPTION)
          .fontColor(AppTheme.COLOR_TEXT_SUBTLE)
          .maxLines(1)
          .width('100%')
      }
      .width('100%')
      .padding({ left: 10, right: 8 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height(54)
    .type(ButtonType.Normal)
    .backgroundColor(AppTheme.COLOR_SURFACE_SOFT)
    .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
    .borderRadius(AppTheme.RADIUS_CONTROL)
    .onClick(() => {
      if (sourceType === 'batch') {
        AppNavigator.push(this.getUIContext(), AppRoutes.BATCH_OCR);
      } else {
        this.enterOcrFlow(sourceType === 'camera' ? 'camera' : 'album');
      }
    })
  }

  @Builder
  private scanPanel() {
    Column({ space: 13 }) {
      Column({ space: 7 }) {
        Text('处理新的文档')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.COLOR_TEXT)
          .lineHeight(27)
          .width('100%')
        Text('拍照扫描、导入文件或创建批量 OCR。识别后可编辑文本、调用 AI 整理并导出。')
          .fontSize(AppTheme.FONT_META)
          .fontColor(AppTheme.COLOR_TEXT_MUTED)
          .lineHeight(20)
          .width('100%')
      }
      .width('100%')

      Row({ space: 10 }) {
        this.scanMainAction()
        Column({ space: 10 }) {
          this.actionSmall('导入文件', 'PDF / JPG / PNG', 'album')
          this.actionSmall('批量 OCR', '多文件队列', 'batch')
        }
        // 中文说明：按 HTML action-grid 的 1.16/.84 比例继续收窄右侧操作栈，降低 ArkUI 实机截图中过宽过高的卡片感。
        .layoutWeight(0.84)
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
    .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
    .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
    .borderRadius(AppTheme.RADIUS_PANEL)
  }

  build() {
    Column({ space: 0 }) {
      HtmlStatusBar()
      Scroll() {
        Stack({ alignContent: Alignment.TopStart }) {
          Column({ space: 16 }) {
          HtmlAppBar({
            title: '首页',
            subtitle: this.sessionText,
            actionIcon: 'search',
            // 中文说明：首页搜索图标进入记录页搜索区，避免可点击控件仅刷新数据但没有可见搜索行为。
            onAction: () => AppNavigator.push(this.getUIContext(), AppRoutes.HISTORY)
          })
          Column() {
            this.scanPanel()
          }
          .width('100%')
          .opacity(this.scanEntered ? 1 : 0)
          .translate({ y: this.scanEntered ? 0 : AppMotion.ENTER_OFFSET_Y })

          HtmlSectionHead({ title: 'AI 快捷处理', meta: '基于当前文档' })
          Scroll() {
            Row({ space: 8 }) {
              HtmlToolChip({ label: '摘要', primary: true, onTap: () => AppNavigator.push(this.getUIContext(), AppRoutes.AI_WORKSPACE) })
              HtmlToolChip({ label: '纠错', onTap: () => AppNavigator.push(this.getUIContext(), AppRoutes.AI_WORKSPACE) })
              HtmlToolChip({ label: '字段提取', onTap: () => AppNavigator.push(this.getUIContext(), AppRoutes.AI_WORKSPACE) })
              HtmlToolChip({ label: '转 Markdown', onTap: () => AppNavigator.push(this.getUIContext(), AppRoutes.EXPORT_CENTER) })
            }
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .width('100%')
          .opacity(this.aiEntered ? 1 : 0)
          .translate({ y: this.aiEntered ? 0 : AppMotion.ENTER_OFFSET_Y })

          HtmlSectionHead({ title: '待处理', meta: this.pendingMeta })
          List({ space: 0 }) {
            if (this.pendingItems.length === 0) {
              ListItem() {
                this.emptyListState(this.pendingMeta, '识别任务创建后会显示在这里。')
              }
            } else {
              ForEach(this.pendingItems, (item: HomeDashboardItem, index?: number) => {
                ListItem() {
                  HtmlListRow({
                    index: index === undefined ? 0 : index,
                    mark: item.mark,
                    title: item.title,
                    meta: item.meta,
                    badge: item.badge,
                    tone: item.tone,
                    onTap: () => this.openDashboardItem(item)
                  })
                }
              }, (item: HomeDashboardItem) => item.id)
            }
          }
          .width('100%')
          .height(144)
          .scrollBar(BarState.Off)
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
          .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
          .borderRadius(AppTheme.RADIUS_PANEL)
          .opacity(this.pendingEntered ? 1 : 0)
          .translate({ y: this.pendingEntered ? 0 : AppMotion.ENTER_OFFSET_Y })

          HtmlSectionHead({ title: '最近记录', meta: this.recentMeta, actionLabel: '全部', onAction: () => AppNavigator.push(this.getUIContext(), AppRoutes.HISTORY) })
          List({ space: 0 }) {
            if (this.recentItems.length === 0) {
              ListItem() {
                this.emptyListState('暂无记录', '完成一次 OCR 并保存历史后会显示在这里，导出文件请到导出中心查看。')
              }
            } else {
              ForEach(this.recentItems, (item: HomeDashboardItem, index?: number) => {
                ListItem() {
                  HtmlListRow({
                    index: index === undefined ? 0 : index,
                    mark: item.mark,
                    title: item.title,
                    meta: item.meta,
                    badge: item.badge,
                    tone: item.tone,
                    onTap: () => this.openDashboardItem(item)
                  })
                }
              }, (item: HomeDashboardItem) => item.id)
            }
          }
          .width('100%')
          .height(210)
          .scrollBar(BarState.Off)
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
          .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
          .borderRadius(AppTheme.RADIUS_PANEL)
          .opacity(this.recentEntered ? 1 : 0)
          .translate({ y: this.recentEntered ? 0 : AppMotion.ENTER_OFFSET_Y })

          Column()
            .height(4)
        }
        .width('100%')
        .padding({ left: AppTheme.PAGE_PADDING, right: AppTheme.PAGE_PADDING, top: 4, bottom: AppTheme.PAGE_PADDING })
        }
        .width('100%')
        .constraintSize({ minHeight: '100%' })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .backgroundColor(AppTheme.COLOR_PAGE)

      AppBottomNav({ activeTab: 'home' })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.COLOR_PAGE)
  }
}
