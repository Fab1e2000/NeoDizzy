# DizzyLab 标签图标

参考 https://www.dizzylab.net/ 导航标志中的花瓣环线，由本项目重新绘制并经用户确认；不是官方原稿。

- 设计母版：本次确认的 `dizzylab-rounded-vector.svg`。
- 24×24 pt 画布，圆角底为 `(1.6, 1.6, 20.8, 20.8)`，圆角 5.6；七条环线宽 1.15，圆端点、圆连接。
- 使用 CoreGraphics 将环线描边转成轮廓，并依次从圆角底中减去，输出普通 SVG 路径。未使用位图、运行时遮罩或滤镜。
- `DizzyLabTabIcon` 使用模板渲染并保留矢量，颜色由界面提供。
