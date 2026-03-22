# Dark Mode / Light Mode Support

## Overview

Add dark mode support to PasteFlow's floating panel UI, with a user-selectable appearance preference (System / Light / Dark). The Settings window continues using system colors and gets dark mode automatically.

## Decisions

- **Mode selection**: Dropdown in Settings with three options — System (default), Light, Dark
- **Color organization**: Asset Catalog named color sets with "Any Appearance" and "Dark" variants
- **Dark palette**: Neutral Dark (charcoal grays, matching macOS system dark mode aesthetic)
- **Settings view**: No changes — uses system colors which adapt automatically
- **FloatingPanel**: Remove forced `.aqua` appearance; apply user-chosen appearance

## Color Palette

### Semantic Color Names and Values

| Semantic Name        | Light Value | Dark Value  | Usage                              |
|---------------------|-------------|-------------|------------------------------------|
| `backgroundPrimary` | `#FFFFFF`   | `#1E1E1E`   | Main panel background              |
| `backgroundPreview` | `#F5F5F3`   | `#2A2A2A`   | Preview panel, code blocks         |
| `backgroundSelected`| `#E6F1FB`   | `#1E3A5C`   | Selected row highlight             |
| `backgroundPill`    | `#EEEDFE`   | `#2A2745`   | Filter pill, button backgrounds    |
| `textPrimary`       | `#1A1A1A`   | `#E8E8E8`   | Main text, row titles              |
| `textSecondary`     | `#999999`   | `#888888`   | Timestamps, metadata, placeholders |
| `textTertiary`      | `#666666`   | `#AAAAAA`   | Section headers ("PREVIEW")        |
| `accentBlue`        | `#185FA5`   | `#4A9EE5`   | Selected item icons, active states |
| `accentPurple`      | `#3C3489`   | `#7B73D1`   | Button text, pill active text      |
| `borderDivider`     | `#E5E5E5`   | `#3A3A3A`   | All divider lines and borders      |
| `borderPill`        | `#CECBF6`   | `#3D3966`   | Filter pill border                 |

### Notes

- Accent colors are lightened in dark mode for sufficient contrast against dark backgrounds
- Text colors are inverted — light text on dark backgrounds
- Selected row and pill backgrounds use deeper, muted tones of their light counterparts

## Architecture

### Asset Catalog Color Sets

Each semantic color gets a color set in `Assets.xcassets/Colors/`:

```
Assets.xcassets/
  Colors/
    backgroundPrimary.colorset/Contents.json
    backgroundPreview.colorset/Contents.json
    backgroundSelected.colorset/Contents.json
    backgroundPill.colorset/Contents.json
    textPrimary.colorset/Contents.json
    textSecondary.colorset/Contents.json
    textTertiary.colorset/Contents.json
    accentBlue.colorset/Contents.json
    accentPurple.colorset/Contents.json
    borderDivider.colorset/Contents.json
    borderPill.colorset/Contents.json
```

Each `Contents.json` defines two appearances:

```json
{
  "colors": [
    {
      "color": { "color-space": "srgb", "components": { "red": "1.000", "green": "1.000", "blue": "1.000", "alpha": "1.000" } },
      "idiom": "universal"
    },
    {
      "appearances": [{ "appearance": "luminosity", "value": "dark" }],
      "color": { "color-space": "srgb", "components": { "red": "0.118", "green": "0.118", "blue": "0.118", "alpha": "1.000" } },
      "idiom": "universal"
    }
  ],
  "info": { "author": "xcode", "version": 1 }
}
```

### Appearance Preference

- Store preference in `UserDefaults` with key `"appearanceMode"` (values: `"system"`, `"light"`, `"dark"`)
- Default: `"system"`
- Add `appearanceMode` property to `AppState`
- When preference changes, update `FloatingPanel`'s `appearance` property:
  - `"system"` → set `appearance = nil` (follows system)
  - `"light"` → set `appearance = NSAppearance(named: .aqua)`
  - `"dark"` → set `appearance = NSAppearance(named: .darkAqua)`

### FloatingPanel Changes

- Remove hardcoded `self.appearance = NSAppearance(named: .aqua)` from `init`
- Add a method to update appearance based on `AppState.appearanceMode`
- Call this method on init and whenever the preference changes

### SettingsView Changes

- Add "Appearance" dropdown (Picker) with options: System, Light, Dark
- Place it near the top of settings since it's a primary preference
- No other SettingsView changes needed — it already uses system colors

### View Changes

Replace all `Color(hex: 0x...)` calls with `Color("semanticName")`:

| File | Changes |
|------|---------|
| `PopoverView.swift` | `backgroundPrimary`, `borderDivider` |
| `SearchBarView.swift` | `backgroundPrimary`, `textSecondary`, `borderDivider` |
| `FilterRowView.swift` | `backgroundPrimary`, `accentPurple`, `backgroundPill`, `borderPill`, `textSecondary` |
| `ClipListView.swift` | `backgroundPrimary` |
| `ClipRowView.swift` | `backgroundSelected`, `backgroundPrimary`, `accentBlue`, `textSecondary`, `textPrimary`, `borderDivider` |
| `DetailPanelView.swift` | `textTertiary`, `textSecondary`, `backgroundPreview`, `accentPurple`, `backgroundPill`, `borderDivider` |
| `FooterView.swift` | `backgroundPrimary`, `textSecondary`, `borderDivider` |

### What Stays the Same

- `Color(hex:)` extension in `Extensions.swift` — kept for potential future use
- `SettingsView` system color usage — unchanged
- Image/icon assets — SF Symbols adapt to appearance automatically
- Error colors (`.red.opacity(0.7)`) — system colors, adapt automatically

## Testing

- Verify all 11 color sets render correctly in both appearances
- Toggle between System/Light/Dark in Settings and confirm panel updates immediately
- Confirm Settings window follows system appearance regardless of panel setting
- Verify text contrast meets WCAG AA (4.5:1) in both modes
- Test that SF Symbol icons adapt correctly
- Test persistence — quit and relaunch, appearance preference should be retained
