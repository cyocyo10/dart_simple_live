# Local canvas_danmaku patch

Base: pub.dev canvas_danmaku 0.3.1 (upstream license retained).

The upstream initial glyph rendering accepts fontFamily, but cache rebuilds in
scroll/static/special painters omit it. Thread fontFamily through all repaint
paths, including DPI cache rebuilds, and recalculate tracks on font changes.
Also use the new outline width when updating the self-send border paint.

Regression: simple_live_app/test/widget_test.dart.
Remove the path override only after an upstream release passes this regression.
