# Lunar design system: extracted tokens

This is what the Lunar 6.11.0 source actually defines. Every value is traced to a file. The hex values were computed from the source's HSB and RGB literals. Where the three colour sources disagree, all versions are listed. The critique and recommendations are in [PLAN.md §3](PLAN.md#3-design-system-extraction).

Colour sources:

- **A** = asset catalog, `Lunar/Assets.xcassets/*.colorset`. Light and dark pairs, all sRGB.
- **T** = `Lunar/Data/Theme.swift`, AppKit `NSColor` literals.
- **S** = `Lunar/Views/Colors.swift`, SwiftUI `Color(hue:saturation:brightness:)`.

---

## 1. Colour

### 1.1 Brand and accent

| Token | Light | Dark | Source | Used for |
|---|---|---|---|---|
| `lunarYellow` | `#FFD586` | `#FFC895` (becomes peach) | A `Lunar Yellow`, T `lunarYellow` | Primary accent, logo, settings page background (light), slider fill, big numeric text fields |
| `accent` | `#FFD586` | `#FFFFFF` | A `AccentColor` | System accent, used for controls AppKit tints automatically |
| `slider` | `#FFD586` | `#FFBD8F` | A `Slider` | AppKit slider track fill |
| `lunarYellowTransparent` | `#FFD586` @ 50% | `#FFF3E9` @ 20.5% | A | Selection and hover washes |
| `peach` | `#FFC895` (T) / `#FFC794` (S) | — | T, S | Dark-mode accent, BigSurSlider default fill and knob, settings background (dark), dropdown hover |
| `sunYellow` | **`#FDB53A` (T) ≠ `#FFC56E` (S)** | — | T, S | Options menu background (light, S); numeric text on black (T) |
| `orange` | `#FFA76A` | — | T | Dropdown arrows (light), hover on numeric fields (dark), Clock-mode colour |
| `saffron` | `#FFB82E` | — | S | Warnings |
| `golden` | `#A36A00` | — | S | Dark yellow text on light backgrounds |
| `lightGold` | `#F0D1AD` | — | S | Subtle warm fills |
| `dropdownArrow` | `#FF946F` | `#FFFFFF` | A | Pop-up button chevrons |

### 1.2 Ink and neutrals (the "mauve" family)

| Token | Value | Source | Used for |
|---|---|---|---|
| `caption` | `#100333` light / `#FFFFFF` dark | A `Caption` | Primary text (asset-catalog views) |
| `captionSecondary` | `#100333` @ 70% / `#FFFFFF` | A | Secondary text |
| `captionTertiary` | `#100333` @ 50% / `#FFFFFF` @ 80% | A | Tertiary text and hints |
| `captionInverted` | `#FFFFFF` / `#100333` | A | Text on accent fills |
| `mauve` | **`#3D304C` (T) ≠ `#2D2A3B` (S)** | T, S | Primary ink in AppKit pages, slider borders (light), button labels |
| `darkMauve` | `#2A252A` | T | Hotkeys page background (light), explanation text |
| `blackMauve` | **`#171518` (T) ≠ `#1D1C1F` (S)** | T, S | Darkest ink; popover background (dark) @ 80%; the standard shadow colour |
| `grayMauve` | `#544E6E` | S | Muted ink |
| `violet` | `#4A4A57` | T | Disabled "enable" button background |
| `mauveGray` | `#7E777E` / `#B3B1B6` | A `MauveGray` | Muted labels |
| `lightMauve` | `#ED91AC` | S | Pink highlight (dark mode `mauvish`) |
| `pinkMauve` | `#6B1A32` | S | Pink highlight (light mode `mauvish`) |
| `gray` | `#ECEDF1` | T | Off-state button background |
| `darkGray` / `lightGray` | `#525151` / `#EBEBEB` | S | `FG.gray` / `BG.gray` pair |
| `blackGray`, `blackish` | `#2E2928`, `#1F1D1C` | S | Near-black warm fills |
| `warmWhite` / `warmBlack` | `#F2E1E1` / `#2E2727` | S | `FG.warm` / `BG.warm`, the default "translucid" tint. **Bug: `hue: 20` where 0–1 is expected; intended `20/360` → ≈ `#F2E5E1` / `#2E2927`** |
| `white` | `#FFFFFF` | T | Page background |

### 1.3 Semantic and state

| Token | Value | Source | Used for |
|---|---|---|---|
| `red` / `power` | `#F23343` | T, A `Power` (light) | Destructive actions, lock "on", power button |
| `errorRed` | `#F70004` | T | Errors |
| `dullRed` | `#D55D5C` | T | Enable button "on" (light) |
| `rouge` | `#965B65` | T | Muted red |
| `hotRed` / `scarlet` | `#FF2E47` | S | `dynamicRed` (light) |
| `pinkishRed` | `#FA2357` | S | `dynamicRed` (dark) |
| `green` | `#54D381` | T | Sync mode, "brightness range" hover |
| `calmGreen` / `lightGreen` | `#28C741` / `#6AD48F` | S | Success |
| `blue` | `#167BFF` | T | Sensor mode, help hover |
| `calmBlue` | `#4081D6` | S | Info |
| `xdr` | `#93A5C7` | T, S | XDR brightness feature colour |
| `subzero` | `#FF7081` (darker `#800613`) | T, S | Sub-zero dimming feature colour |

**Mode colour map** (`Components.swift` `SettingsToggle.modeColor`): sync = green, sensor = blue, location = lunarYellow, clock = orange, manual = red, auto = blackMauve. Green, blue, orange and red here are SwiftUI's *system* colours, not the `Theme.swift` ones, which is one more source of drift.

### 1.4 Surfaces and fills

| Token | Light | Dark | Source |
|---|---|---|---|
| `buttonBG` | `#100333` @ 10% | `#FFFFFF` @ 15% | A `Button BG` |
| `fieldBG` | `#100333` @ 3.5% | `#FFFFFF` @ 5% | A `Field BG` |
| `fieldBGNeutral` | `#000000` @ 3.5% | `#FFFFFF` @ 5% | A `Field BG no color` |
| `inverted` | `#FFFFFF` | `#000000` | A |
| `invertedSemiOpaque` | `#FFFFFF` @ 82.5% | `#0A090A` @ 82% | A |
| `popoverBackground` | `#FFFFFF` @ 85% | blackMauve @ 80% | T |
| `menuPanel` | HUD blur + `#FFFFFF` @ 60% | HUD blur + blackMauve @ 40% | S `QuickActionsMenuView.bg` |
| `translucid` | warm fg @ 5% | — | S |
| `settingsDivider` | `#FFFFFF` @ 30% | — | T |
| `notch` / `notchless` | `#262227` @ 50% / `#E3DEDF` @ 37% | same | A |

---

## 2. Typography

**Families:**

- **SF Pro** (system) is the default.
- **SF Pro Rounded** (`design: .rounded`) is used for small labels and numeric values in SwiftUI.
- **SF Mono** (`design: .monospaced`, `NSFont.monospacedSystemFont`) is used for values and raw DDC numbers.
- **Menlo** (Regular and Bold, storyboard only) is used for big numeric fields and hotkey labels.
- **Hiragino Kaku Gothic ProN W3** appears once.

Frequency across the code:

| Size (pt) | Weights seen | Designs | Typical role |
|---|---|---|---|
| 60, 52, 48, 46, 44 | black, heavy, medium | default, rounded, mono | Page hero numbers (brightness %), OSD |
| 35, 25, 24, 22, 21, 20, 19 | heavy, black, bold, semibold | default, mono, Menlo Bold | Page titles, big scrollable value fields |
| 18, 16, 15, 14 | semibold, heavy, regular | default, rounded, mono, Menlo Bold | Section headers, display names |
| 13 | medium, light, regular | default, mono | Body (storyboard `systemMedium 13` × 23) |
| 12 | semibold, medium, regular | default, rounded, mono | Row labels, menu items |
| 11 | medium, semibold, bold | default, Menlo | Captions (storyboard `systemSemibold 11` × 32) |
| 10 | semibold (×14), medium, heavy, bold | default, **rounded (×17)**, mono | Most common SwiftUI label size: menu captions, slider values |
| 9, 8, 7 | semibold, medium, bold | rounded, mono | Knob values (8 mono), tags |

Storyboard metaFonts: `smallSystemBold` × 55, `systemSemibold 11` × 32, `system` × 28, `systemMedium 13` × 23, `systemHeavy 14` × 21, `systemHeavy 21/24` × 28.

**The hierarchy as practised** (inferred): hero value (44–60 heavy/black) › page title (21–24 heavy) › section (14–16 semibold/heavy) › body (12–13 medium) › caption (10–11 semibold, often rounded) › micro (8–9 mono/rounded). Weight carries most of the emphasis, and secondary levels use opacity (70/50%) instead of a smaller size.

---

## 3. Spacing

There's no declared scale. These are the observed values, by frequency, from `.padding` and `spacing:`:

`2` (×42) · `10` (×19) · `4` (×16) · `20` (×13) · `6` (×12) · `3` (×12) · `8` (×9) · `5` (×7) · `7` (×6) · `1` (×6) · `30` (×4) · `24` / `40` (×2) · `12`, `15`, `16` (×1)

Named layout constants (`Controllers/QuickActionsViewController.swift:96`):

| Constant | Value |
|---|---|
| `MENU_WIDTH` | 320 |
| `MENU_CLEAN_WIDTH` | 300 (no header/footer) |
| `FULL_OPTIONS_MENU_WIDTH` | 412 |
| `MENU_HORIZONTAL_PADDING` | 24 |
| `MENU_VERTICAL_PADDING` | 40 |

Button padding defaults: `FlatButton` is 2 × 8 vertical × horizontal; `RoundBG` is `radius/2` vertical and `vertical × 2.2` horizontal.

**The implied scale** if you normalise it: **2 · 4 · 6 · 8 · 10 · 20 · 24 · 40**.

---

## 4. Corner radii

| Radius | Where |
|---|---|
| 1 | Slider "mark" tick |
| 3–5 | Small tags, help badges |
| **6** (×9) | Inline controls |
| **8** (×16+) | Default: `FlatButton`, `PickerButton`, `RoundBG`, inner menu cards |
| 10 / 12 | Cards, text fields, popovers |
| **14** | Options menu panel |
| **18** (×8) | Menu bar panel (continuous) |
| 20 | BigSurSlider track (`.cornerRadius(20)` → a full pill at 22 pt height) |
| 24 | Large cards |
| `height/2` | `MacToggle`, knobs (full capsule) |

SwiftUI uses `style: .continuous` (the squircle) almost everywhere.

---

## 5. Shadows / elevation

| Level | Spec | Where |
|---|---|---|
| e1 | black @ 10%, r 3, y 2 | Quick action buttons |
| e2 | black @ 25% light / 75% dark, r = `shadowSize`, y = `shadowSize/2` | `RoundBG` |
| e3 | **blackMauve @ 20% light / 50% dark, r 8, y 6** | Menu panel, options panel (the house shadow) |
| e3-osd | blackMauve @ 20%, r 8, y 4 | OSD |
| tip | black @ 40%, r 5, y 3 | XDR tip |
| knob | black @ min(value, 0.3) × (pressed ? 1 : 0.3), r 4 → 6 pressed, x −1, y 0 → 2 pressed | BigSurSlider knob (the shadow grows with value and when pressed) |
| toggle | black @ 40%, offset (0, −2) | `MacToggle` knob (AppKit NSShadow) |
| glow | the OSD colour, r = value × glowRadius | OSD value glow |

---

## 6. Components

| Component | Framework | File | Notes |
|---|---|---|---|
| **Menu bar panel** | SwiftUI in a custom `NSWindow` | `SwiftUIViews/QuickActionsMenuView.swift`, `Controllers/StatusItemButtonController.swift` | Not an `NSPopover`. It's positioned under the status item, uses `.hudWindow` blur, 18 pt radius, and the e3 shadow. The header and footer auto-hide on hover |
| Display row | SwiftUI | `SwiftUIViews/DisplayRowView.swift` | Name, brightness/contrast/volume sliders, input/rotation, context menu |
| **BigSurSlider** | SwiftUI | `Views/OSDWindow.swift:245` | 200 × 22 default, pill track (bg black @ 10%), peach fill, 22 pt circular knob with the value in 8 pt mono inside, SF Symbol in the track, optional red "mark" tick (3 pt), `jumpySpring` on the mark, scroll-wheel support |
| AppKit Slider | AppKit | `Views/Slider.swift` | Custom `NSSliderCell` for the main window |
| **ScrollableTextField** | AppKit | `Views/ScrollableTextField.swift`, `ScrollableTextFieldCaption.swift` | Signature control: a big heavy numeral you change with the scroll wheel or arrow keys, hover colour change, caption beneath |
| SettingsToggle | SwiftUI | `Views/Components.swift:16` | `CheckboxToggleStyle(.circle)` + label + optional help "?" |
| CheckboxToggleStyle | SwiftUI | `Components.swift:344` | Circle or square checkbox |
| MacToggle | AppKit | `Views/MacToggle.swift` | iOS-style switch, default height 26 (44 in init), width = 1.6 × height, 0.3 s animation |
| ToggleButton / LockButton | AppKit | `Views/ToggleButton.swift`, `LockButton.swift` | State colours from the `Theme.swift` page × hover dictionaries |
| FlatButton | SwiftUI `ButtonStyle` | `Components.swift:197` | Radius 8, hover colour, press = blend 50% white, scale effect, disabled contrast 0.3 |
| OutlineButton | SwiftUI `ButtonStyle` | `Components.swift:135` | Stroke button, warm fg @ 80% |
| PickerButton | SwiftUI `ButtonStyle` | `Components.swift:287` | Segmented-style option chip: on = warm fg @ 90% (light) / 15% (dark), off = translucid |
| Dropdown | AppKit | `Views/PopUpButton.swift`, `AdaptiveModeButton.swift` | Custom `NSPopUpButton` with a coloured chevron. The mode picker is a dropdown with mode icons |
| RoundBG | SwiftUI modifier | `Components.swift:543` | Padded rounded background + e2 shadow |
| HelpTag / HelpButton | SwiftUI / AppKit | `Components.swift:567`, `Views/HelpButton.swift` | Popover with Markdown help (SwiftyMarkdown) |
| PaddedPopoverView | SwiftUI | `SwiftUIViews/PaddedPopoverView<Content>.swift` | Standard popover container |
| Curve chart | AppKit | `Views/BrightnessContrastChartView.swift` | Shows the adaptive curve and learned points |
| OSD | SwiftUI in an `NSWindow` | `Views/OSDWindow.swift` | Brightness/volume on-screen display |
| Main window | AppKit, WAYWindow | `Views/ModernWindow.swift`, `Base.lproj/Main.storyboard` (10.4k lines) | Paged: Display, Settings, Hotkeys, Configuration |
| Settings pages | Mixed | `Controllers/SettingsPageController.swift`, `SwiftUIViews/AdvancedSettingsView.swift`, `HDRSettingsView.swift` | AppKit pages hosting SwiftUI islands |
| Hotkey recorder | AppKit | `Views/HotKeyView.swift`, `HotkeyButton.swift` | Its own dark/light colour tables |

### SwiftUI vs AppKit split

- **SwiftUI:** the whole menu bar experience (QuickActions, display rows, presets, power-off, blackout popover), OSD, advanced/HDR settings, small popovers.
- **AppKit:** the main window and its pages (storyboard), every custom control used there (Slider, ScrollableTextField, MacToggle, ToggleButton, PopUpButton), the status item, window management.
- The **direction of travel** is AppKit → SwiftUI. Newer surfaces are SwiftUI, and older ones are storyboard.

---

## 7. Theming and light/dark

- **User override:** `AppDelegate.colorScheme` (`system | light | dark`). `darkMode` resolves `system` through `NightShift.currentAppearance.isDark` (`Theme.swift`).
- **Asset catalog:** each colorset has an `any` + `dark` appearance, so AppKit resolves them automatically.
- **SwiftUI:** `Color(light:dark:)` wraps `NSColor(name:dynamicProvider:)`, switching on `aqua/vibrantLight/highContrast…` vs `darkAqua/vibrantDark…` (`Colors.swift`). Views also branch on `@Environment(\.colorScheme)` for shadow opacity and fills.
- **AppKit `Theme.swift`:** computed `var`s re-evaluated on each access (`darkMode ? peach : lunarYellow`), plus per-page, per-hover-state dictionaries.
- **Dark mode shifts the accent from yellow `#FFD586` to peach `#FFC895`** so it reads less green on dark backgrounds. That's a nice detail.

---

## 8. Motion

| Token | Spec | Source | Used for |
|---|---|---|---|
| `fastSpring` | `interactiveSpring(dampingFraction: 0.7)` | `Components.swift:85` (×42) | Default for most state changes |
| `fastTransition` | same (macOS) / `easeOut(0.1)` (iOS) | `Components.swift:81` | Header/footer fade |
| `jumpySpring` | `spring(response: 0.4, dampingFraction: 0.45)` | `Components.swift:86` | Playful: slider mark, badges |
| `easeOutExpo` | cubic-bezier(0.19, 1, 0.22, 1) | `Utils/Extensions.swift:1466` | AppKit `CATransition`s, 0.5 / 0.8 / 1.0 s |
| `easeOutCubic` | cubic-bezier(0.215, 0.61, 0.355, 1) | same | 0.8 / 1.0 s transitions |
| `easeOutQuart` | cubic-bezier(0.165, 0.84, 0.44, 1) | same | Default for `NSView.transition` |
| `easeOutBack` | cubic-bezier(0.175, 0.885, 0.32, 1.275) | same | Move-in with overshoot |
| micro | `easeOut(0.1–0.2)`, `easeInOut(0.3)` | various | Hover |
| MacToggle | `NSAnimationContext` 0.3 s | `MacToggle.swift:136` | Switch thumb |
| Hover delay | 50 ms in / 500 ms out | `QuickActionsMenuView.handleHeaderTransition` | Header/footer reveal |
| Enter/exit | `.transition(.scale.animation(.fastSpring))` | several | Value labels appearing in sliders |

---

## 9. Machine-readable tokens (rebuild source)

This is a cleaned, *deduplicated* version: one value per token, with the drift resolved in favour of the asset catalog, since that's what light/dark actually render. Generate `Tokens.swift` from it.

```json
{
  "color": {
    "accent":            { "light": "#FFD586", "dark": "#FFC895" },
    "accent.strong":     { "light": "#FDB53A", "dark": "#FFBD8F" },
    "accent.wash":       { "light": "#FFD58680", "dark": "#FFF3E934" },
    "accent.orange":     { "light": "#FFA76A", "dark": "#FFA76A" },
    "ink":               { "light": "#100333", "dark": "#FFFFFF" },
    "ink.secondary":     { "light": "#100333B3", "dark": "#FFFFFFCC" },
    "ink.tertiary":      { "light": "#10033380", "dark": "#FFFFFF99" },
    "ink.onAccent":      { "light": "#1D1C1F", "dark": "#1D1C1F" },
    "mauve":             { "light": "#3D304C", "dark": "#B3B1B6" },
    "mauve.deep":        { "light": "#2A252A", "dark": "#171518" },
    "surface.panel":     { "light": "#FFFFFF99", "dark": "#1D1C1F66", "material": "hudWindow" },
    "surface.field":     { "light": "#10033309", "dark": "#FFFFFF0D" },
    "surface.button":    { "light": "#1003331A", "dark": "#FFFFFF26" },
    "danger":            { "light": "#F23343", "dark": "#FA2357" },
    "success":           { "light": "#28C741", "dark": "#6AD48F" },
    "info":              { "light": "#167BFF", "dark": "#4081D6" },
    "shadow":            { "light": "#1D1C1F33", "dark": "#1D1C1F80" }
  },
  "font": {
    "family":  { "ui": "SF Pro", "numeric": "SF Pro Rounded", "code": "SF Mono" },
    "hero":    { "size": 48, "weight": "heavy",    "family": "numeric" },
    "title":   { "size": 22, "weight": "heavy" },
    "section": { "size": 15, "weight": "semibold" },
    "body":    { "size": 13, "weight": "medium" },
    "label":   { "size": 12, "weight": "semibold" },
    "caption": { "size": 10, "weight": "semibold", "family": "numeric" },
    "micro":   { "size": 8,  "weight": "medium",   "family": "code" }
  },
  "space":  { "xxs": 2, "xs": 4, "sm": 6, "md": 8, "lg": 10, "xl": 20, "xxl": 24, "xxxl": 40 },
  "radius": { "xs": 3, "sm": 6, "md": 8, "lg": 12, "xl": 14, "panel": 18, "pill": 999 },
  "shadow": {
    "e1":    { "color": "#00000019", "radius": 3, "x": 0, "y": 2 },
    "panel": { "color": "shadow",    "radius": 8, "x": 0, "y": 6 }
  },
  "size": {
    "menu.width": 320, "menu.padding.h": 24,
    "slider.height": 22, "slider.width": 200, "slider.knob": 22,
    "toggle.height": 26, "toggle.widthRatio": 1.6
  },
  "motion": {
    "spring.fast":   { "type": "interactiveSpring", "damping": 0.7 },
    "spring.jumpy":  { "type": "spring", "response": 0.4, "damping": 0.45 },
    "ease.outExpo":  [0.19, 1, 0.22, 1],
    "ease.outQuart": [0.165, 0.84, 0.44, 1],
    "duration.micro": 0.15, "duration.page": 0.5,
    "hover.inDelay": 0.05, "hover.outDelay": 0.5
  }
}
```

Suggested additions for *your* app (not in Lunar):

- `color.whitepoint.live`: computed at runtime from the current Kelvin and used as the menu bar icon tint.
- `color.critical`: pure neutral `#8E8E93`, shown only in colour-critical mode. Using a neutral colour for the mode where colour matters most is the signal.
