import QtQuick
import qs.Commons

// Shared chrome tokens for Spotlight's card-styled surfaces: the setup tour
// and the settings panel. Both paint on the same glass card rather than on the
// shell kit, so the derived alphas are worked out once here instead of being
// repeated by every surface that needs them.
QtObject {
  id: pal

  property color foreground: Color.foreground
  property color accent: Color.accent
  property string fontFamily: Style.font.family
  property int hairline: 1
  property int rowRadius: 8

  readonly property color dim: Util.alpha(pal.foreground, 0.6)
  readonly property color line: Util.alpha(pal.foreground, 0.1)
  readonly property color lineHot: Util.alpha(pal.foreground, 0.22)
  readonly property color lineFocus: Util.alpha(pal.accent, 0.7)
  readonly property color fill: Util.alpha(pal.foreground, 0.04)
  readonly property color fillHot: Util.alpha(pal.foreground, 0.08)
  readonly property color accentFill: Util.alpha(pal.accent, 0.14)
  readonly property color onAccent: Color.background
}
