# GitGatto imagegen 图标资产计划

当前代码共盘点 **117** 个界面图标语义。清单由 `scripts/inventory-icons.py` 从实际 SwiftUI 调用生成。

## 统一风格

- 256 × 256 透明 PNG 主文件；主体占画布约 78%，四周保留一致安全区。
- 单色轮廓，粗细统一，圆角端点和圆角连接；在 24 px 下仍能识别。
- 友好几何结构，允许轻微不对称，避免 SF Symbols 的构图比例与 Apple 原生视觉。
- 不使用底板、渐变、投影、3D、文字、字母、水印、毛边、细碎纹理或模糊。
- 生成结果作为 template image，由应用主题与状态色统一着色。

## imagegen 调用

全套资产已使用 Codex 内置 imagegen 逐项生成，并以首个文件夹图标作为统一风格参考。

## 分组提示词

### actions-and-tools（28）

图标语义：`character.book.closed`, `command`, `dot.radiowaves.left.and.right`, `eye`, `eye.slash`, `gearshape`, `hammer`, `hand.raised`, `magnifyingglass`, `minus`, `minus.circle`, `minus.circle.fill`, `paintpalette`, `paperplane.fill`, `pencil`, `play.circle`, `play.circle.fill`, `plus`, `plus.circle`, `slider.horizontal.3`, `sparkles`, `square`, `square.grid.2x2`, `square.stack.3d.up`, `text.badge.plus`, `text.cursor`, `trash`, `wrench.and.screwdriver`

```text
为 GitGatto macOS Git 客户端生成一组自定义界面图标。每个图标是独立的 256×256 透明 PNG，不包含文字或底板。使用统一的单色粗轮廓、圆角端点、圆角连接和友好几何结构；保持轻微不对称与品牌辨识度，不采用 SF Symbols 或 Apple 原生图标的比例和路径。主体占画布约 78%，在 24 px 下轮廓清楚。不要渐变、投影、3D、字母、水印、毛边、细碎纹理或模糊。严格按清单一项一图，不合并语义。
```

### files（20）

图标语义：`archivebox`, `archivebox.fill`, `doc`, `doc.badge.ellipsis`, `doc.badge.gearshape`, `doc.badge.minus`, `doc.on.doc`, `doc.richtext`, `doc.text`, `doc.text.magnifyingglass`, `externaldrive.fill`, `folder`, `folder.badge.minus`, `folder.badge.plus`, `folder.fill`, `internaldrive`, `photo`, `shippingbox`, `shippingbox.fill`, `tray.and.arrow.down`

```text
为 GitGatto macOS Git 客户端生成一组自定义界面图标。每个图标是独立的 256×256 透明 PNG，不包含文字或底板。使用统一的单色粗轮廓、圆角端点、圆角连接和友好几何结构；保持轻微不对称与品牌辨识度，不采用 SF Symbols 或 Apple 原生图标的比例和路径。主体占画布约 78%，在 24 px 下轮廓清楚。不要渐变、投影、3D、字母、水印、毛边、细碎纹理或模糊。严格按清单一项一图，不合并语义。
```

### git-and-code（6）

图标语义：`clock.arrow.circlepath`, `clock.badge.checkmark`, `curlybraces.square`, `rectangle.split.2x1`, `stethoscope`, `terminal`

```text
为 GitGatto macOS Git 客户端生成一组自定义界面图标。每个图标是独立的 256×256 透明 PNG，不包含文字或底板。使用统一的单色粗轮廓、圆角端点、圆角连接和友好几何结构；保持轻微不对称与品牌辨识度，不采用 SF Symbols 或 Apple 原生图标的比例和路径。主体占画布约 78%，在 24 px 下轮廓清楚。不要渐变、投影、3D、字母、水印、毛边、细碎纹理或模糊。严格按清单一项一图，不合并语义。
```

### navigation（31）

图标语义：`arrow.clockwise`, `arrow.down`, `arrow.down.app`, `arrow.down.circle`, `arrow.down.circle.fill`, `arrow.down.to.line`, `arrow.left.arrow.right`, `arrow.left.arrow.right.square`, `arrow.right`, `arrow.triangle.2.circlepath`, `arrow.triangle.branch`, `arrow.triangle.merge`, `arrow.triangle.pull`, `arrow.turn.up.left`, `arrow.turn.up.right`, `arrow.up`, `arrow.up.arrow.down`, `arrow.up.circle`, `arrow.up.forward.app`, `arrow.up.right`, `arrow.up.right.square`, `arrow.uturn.backward`, `chevron.compact.down`, `chevron.compact.up`, `chevron.down`, `chevron.left`, `chevron.left.forwardslash.chevron.right`, `chevron.right`, `point.3.connected.trianglepath.dotted`, `point.3.filled.connected.trianglepath.dotted`, `point.topleft.down.to.point.bottomright.curvepath`

```text
为 GitGatto macOS Git 客户端生成一组自定义界面图标。每个图标是独立的 256×256 透明 PNG，不包含文字或底板。使用统一的单色粗轮廓、圆角端点、圆角连接和友好几何结构；保持轻微不对称与品牌辨识度，不采用 SF Symbols 或 Apple 原生图标的比例和路径。主体占画布约 78%，在 24 px 下轮廓清楚。不要渐变、投影、3D、字母、水印、毛边、细碎纹理或模糊。严格按清单一项一图，不合并语义。
```

### people-and-web（13）

图标语义：`bubble.left`, `bubble.left.and.bubble.right`, `building.2`, `globe`, `house.fill`, `link`, `location`, `person.2`, `person.crop.circle`, `person.crop.circle.badge.questionmark`, `person.crop.circle.fill`, `star`, `text.bubble`

```text
为 GitGatto macOS Git 客户端生成一组自定义界面图标。每个图标是独立的 256×256 透明 PNG，不包含文字或底板。使用统一的单色粗轮廓、圆角端点、圆角连接和友好几何结构；保持轻微不对称与品牌辨识度，不采用 SF Symbols 或 Apple 原生图标的比例和路径。主体占画布约 78%，在 24 px 下轮廓清楚。不要渐变、投影、3D、字母、水印、毛边、细碎纹理或模糊。严格按清单一项一图，不合并语义。
```

### status（19）

图标语义：`checkmark`, `checkmark.circle`, `checkmark.circle.fill`, `checkmark.seal`, `checkmark.seal.fill`, `checkmark.shield`, `checkmark.square.fill`, `circle.dashed`, `circle.dotted`, `circle.fill`, `circle.lefthalf.filled`, `exclamationmark`, `exclamationmark.shield`, `exclamationmark.triangle.fill`, `info.circle`, `lock.fill`, `record.circle`, `xmark`, `xmark.circle.fill`

```text
为 GitGatto macOS Git 客户端生成一组自定义界面图标。每个图标是独立的 256×256 透明 PNG，不包含文字或底板。使用统一的单色粗轮廓、圆角端点、圆角连接和友好几何结构；保持轻微不对称与品牌辨识度，不采用 SF Symbols 或 Apple 原生图标的比例和路径。主体占画布约 78%，在 24 px 下轮廓清楚。不要渐变、投影、3D、字母、水印、毛边、细碎纹理或模糊。严格按清单一项一图，不合并语义。
```

## 落地路径

- 运行时资产：`Sources/GitGatto/Resources/UIIcons/gatto-*.png`
- 校验脚本：`scripts/validate-generated-icons.py`，检查 117 张图标是否齐全、尺寸正确并带透明通道。
- 完整语义、引用位置和目标文件见 `imagegen-icon-manifest.json`。
