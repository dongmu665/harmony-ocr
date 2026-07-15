import { AppRoutes } from '../common/routes/AppRoutes';
import { AppNavigator } from '../common/routes/AppNavigator';
import { AppTheme } from '../common/theme/AppTheme';
import { AppMotion } from '../common/theme/AppMotion';

export type BottomNavTab = 'home' | 'history' | 'batch' | 'profile';

/**
 * BottomNavItem 描述底栏单个导航项。
 * 维护说明：只保存路由和展示文案，不承载页面业务数据或账号状态。
 */
interface BottomNavItem {
  key: BottomNavTab;
  label: string;
  route: string;
}

/**
 * BottomNavSvgIcon 使用 Canvas 按 HTML SVG 的 24 viewBox 坐标复刻底栏图标。
 * 维护边界：该组件只绘制静态导航符号，不读取业务数据、账号状态或敏感字段。
 */
@Component
struct BottomNavSvgIcon {
  tab: BottomNavTab = 'home';
  active: boolean = false;
  private iconContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));

  /**
   * 将 HTML SVG 坐标映射到 ArkUI 21px 画布，保证线宽和外接尺寸与原型一致。
   */
  private map(value: number): number {
    return value * 21 / 24;
  }

  /**
   * 绘制当前 tab 的线稿图标；只使用 path/line/circle 语义，避免字体图标或堆叠组件造成几何偏差。
   */
  private drawIcon(): void {
    const ctx = this.iconContext;
    const color = this.active ? AppTheme.COLOR_BRAND_DARK : AppTheme.COLOR_TEXT_SUBTLE;
    ctx.clearRect(0, 0, 21, 21);
    ctx.strokeStyle = color;
    ctx.lineWidth = 2;
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';
    ctx.fillStyle = AppTheme.COLOR_TRANSPARENT;

    if (this.tab === 'home') {
      ctx.beginPath();
      ctx.moveTo(this.map(4), this.map(10.5));
      ctx.lineTo(this.map(12), this.map(4));
      ctx.lineTo(this.map(20), this.map(10.5));
      ctx.lineTo(this.map(20), this.map(20));
      ctx.lineTo(this.map(14), this.map(20));
      ctx.lineTo(this.map(14), this.map(15));
      ctx.lineTo(this.map(10), this.map(15));
      ctx.lineTo(this.map(10), this.map(20));
      ctx.lineTo(this.map(5), this.map(20));
      ctx.lineTo(this.map(4), this.map(19));
      ctx.lineTo(this.map(4), this.map(10.5));
      ctx.stroke();
    } else if (this.tab === 'history') {
      ctx.beginPath();
      ctx.moveTo(this.map(7), this.map(3));
      ctx.lineTo(this.map(17), this.map(3));
      ctx.lineTo(this.map(18), this.map(4));
      ctx.lineTo(this.map(18), this.map(21));
      ctx.lineTo(this.map(15), this.map(19));
      ctx.lineTo(this.map(12), this.map(21));
      ctx.lineTo(this.map(9), this.map(19));
      ctx.lineTo(this.map(6), this.map(21));
      ctx.lineTo(this.map(6), this.map(4));
      ctx.lineTo(this.map(7), this.map(3));
      ctx.stroke();
      this.drawLine(9, 8, 15, 8);
      this.drawLine(9, 12, 15, 12);
      this.drawLine(9, 16, 13, 16);
    } else if (this.tab === 'batch') {
      this.drawLine(8, 6, 20, 6);
      this.drawLine(8, 12, 20, 12);
      this.drawLine(8, 18, 20, 18);
      this.drawDot(4, 6, color);
      this.drawDot(4, 12, color);
      this.drawDot(4, 18, color);
    } else {
      ctx.beginPath();
      ctx.arc(this.map(12), this.map(8), this.map(4), 0, Math.PI * 2);
      ctx.stroke();
      ctx.beginPath();
      ctx.arc(this.map(12), this.map(21), this.map(7), Math.PI, Math.PI * 2);
      ctx.stroke();
    }
  }

  private drawLine(x1: number, y1: number, x2: number, y2: number): void {
    const ctx = this.iconContext;
    ctx.beginPath();
    ctx.moveTo(this.map(x1), this.map(y1));
    ctx.lineTo(this.map(x2), this.map(y2));
    ctx.stroke();
  }

  private drawDot(x: number, y: number, color: string): void {
    const ctx = this.iconContext;
    ctx.beginPath();
    ctx.fillStyle = color;
    ctx.arc(this.map(x), this.map(y), 1.05, 0, Math.PI * 2);
    ctx.fill();
    ctx.fillStyle = AppTheme.COLOR_TRANSPARENT;
  }

  build() {
    Canvas(this.iconContext)
      .width(21)
      .height(21)
      .onReady(() => this.drawIcon())
      .onAreaChange(() => this.drawIcon())
  }
}

/**
 * AppBottomNav 提供首页、记录、批量、我的四个一级区域的固定底部导航。
 * 维护边界：组件只做应用内路由切换，不读取账号、Token、OCR 文本、图片 URI 或 records 数据；AI 能力只能从业务页面进入，不作为独立底栏 tab。
 */
@Component
export struct AppBottomNav {
  activeTab: BottomNavTab = 'home';
  @State private pressedTab: string = '';

  /**
   * 返回当前一级导航配置。
   * 说明：对齐 HTML 原型的四栏结构，AI 服务连接保留在首页、记录、结果页和我的页上下文中。
   */
  private tabs(): BottomNavItem[] {
    return [
      { key: 'home', label: '首页', route: AppRoutes.HOME },
      { key: 'history', label: '记录', route: AppRoutes.HISTORY },
      { key: 'batch', label: '批量', route: AppRoutes.BATCH_OCR },
      { key: 'profile', label: '我的', route: AppRoutes.PROFILE }
    ];
  }

  @Builder
  private navItem(item: BottomNavItem) {
    Button() {
      Column({ space: 2 }) {
        this.navIconView(item.key)
        Text(item.label)
          .fontSize(10.5)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.activeTab === item.key ? AppTheme.COLOR_BRAND_DARK : AppTheme.COLOR_TEXT_SUBTLE)
          .lineHeight(14.5)
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .scale({ x: this.pressedTab === item.key ? AppMotion.PRESS_SCALE : 1, y: this.pressedTab === item.key ? AppMotion.PRESS_SCALE : 1 })
      .animation({ duration: AppMotion.DURATION_FAST, curve: Curve.EaseOut })
    }
    .layoutWeight(1)
    .height(56)
    .type(ButtonType.Normal)
    .padding(0)
    .backgroundColor(this.activeTab === item.key ? AppTheme.COLOR_BRAND_SOFT : AppTheme.COLOR_TRANSPARENT)
    .border({ width: this.activeTab === item.key ? AppTheme.HAIRLINE : 0, color: this.activeTab === item.key ? AppTheme.COLOR_ACCENT_SOFT : AppTheme.COLOR_TRANSPARENT })
    .borderRadius(AppTheme.RADIUS_CONTROL)
    .animation({ duration: AppMotion.DURATION_NORMAL, curve: Curve.EaseOut })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.pressedTab = item.key;
      }
      if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.pressedTab = '';
      }
    })
    .onClick(() => {
      if (this.activeTab !== item.key) {
        AppNavigator.replaceRoot(this.getUIContext(), item.route);
      }
    })
    .enabled(this.activeTab !== item.key)
  }

  /**
   * 返回底栏图标颜色，供 Builder 内组件链式调用，避免在组件语法区声明局部变量。
   */
  private navIconColor(tab: BottomNavTab): string {
    return this.activeTab === tab ? AppTheme.COLOR_BRAND_DARK : AppTheme.COLOR_TEXT_SUBTLE;
  }

  /**
   * 绘制底栏原生线稿图标，避免字符字体在设备上产生与 HTML SVG 明显不同的字形偏差。
   * 说明：图标只表达导航语义，不读取或暴露任何业务状态。
   */
  @Builder
  private navIconView(tab: BottomNavTab) {
    BottomNavSvgIcon({ tab: tab, active: this.activeTab === tab })
  }

  build() {
    Row({ space: 0 }) {
      ForEach(this.tabs(), (item: BottomNavItem) => {
        this.navItem(item)
      }, (item: BottomNavItem) => item.key)
    }
    .width('100%')
    .height(74)
    .padding({ left: 8, right: 8, top: 7, bottom: 11 })
    .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
    .borderWidth({ top: AppTheme.HAIRLINE, right: 0, bottom: 0, left: 0 })
    .borderColor(AppTheme.COLOR_LINE_SOFT)
  }
}
