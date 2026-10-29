#!/usr/bin/env python3
"""把应用图标嵌进安装器的 HTML：src="AppIcon.png" 换成 base64 的 data URI。

安装器怎么拷贝附带的图片是它自己决定的，嵌进页面里就不依赖这一点。
用法：embed-icon.py <页面.html> <图标.png>
"""
import base64
import sys

page, icon = sys.argv[1], sys.argv[2]
with open(icon, "rb") as handle:
    uri = "data:image/png;base64," + base64.b64encode(handle.read()).decode("ascii")
with open(page, encoding="utf-8") as handle:
    text = handle.read()
text = text.replace('src="AppIcon.png"', f'src="{uri}"')
with open(page, "w", encoding="utf-8") as handle:
    handle.write(text)
