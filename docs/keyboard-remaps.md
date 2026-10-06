# Keyboard Remaps

Install **Keyboard Remaps** in Settings → Features. A new setup has no rules
and remapping is off. Add your own rules, review **Current setup preview**, then
enable remapping. Disable overlapping Karabiner or macOS modifier rules first.
Accessibility is required.

## General rules

**Key rules** map a physical key to another key, a shortcut, or an action.
Choose from Fn/Globe, Caps Lock, left/right modifiers, letters, numbers,
punctuation, navigation keys and F1–F20. Examples: Fn → Control, right Option →
right Command, Caps Lock → Escape, or Home → Command+Left. These are individual
user choices rather than app-wide defaults.

**Shortcut rules** match a chosen key and exact modifiers, then send a chosen
shortcut or run an action. Sources and outputs can be selected manually or
recorded, including bare keys and Shift combinations. Available actions are:

- Do nothing.
- Cycle enabled input languages.
- Toggle normal Caps Lock and its keyboard light.
- Open a chosen installed application, stored by bundle identifier.

Each rule can be edited, disabled or removed. **Clear all rules** starts again
without changing the feature's availability. No shell commands are executed.

Shortcut rules run after physical key remaps. For example, if Caps Lock is
mapped to Escape, configure any further shortcut using Escape as the source.
For action keys, rules use the original source: Caps Lock → next language can
be combined with Shift+Caps Lock → toggle Caps Lock. Key actions apply only
without modifiers; configure modifier combinations as separate shortcut rules.
If Caps Lock has only a modified action, its bare press retains normal Caps Lock.

Translated shortcuts retain matching down/up events even if modifiers are
released early, and action repeats are suppressed. Outputs bypass Vorssaint's
Quit Protection confirmation. A rule claiming Command+Q takes precedence over
Quit Protection regardless of event-tap installation order.

## One suggested setup

**Suggested setup: comfortable Mac** is optional. Its preview offers:

| Key | Result |
| --- | --- |
| Fn / Globe | Left Command |
| Caps Lock | Cycle input languages |
| Shift + Caps Lock | Toggle normal Caps Lock |
| Command + Q | Do nothing |
| Option + Q | Send Command + Q to quit |
| Option + T | Open Terminal |

Right Command → Right Option is a separate personal choice for layouts such as
Latvian that use Option for alternative characters. It is not in this suggestion.

**Add suggested rules** adds missing sources only. Existing custom rules and
explicitly disabled choices stay intact. Repeated use does not duplicate rules.
A different existing Caps Lock key mapping is preserved along with its meaning;
the suggestion does not add a conflicting Shift+Caps Lock rule.

Q/T in this suggestion follow the input layout's Command table, so Q retains
its shortcut meaning across supported layouts. Recording or selecting a new
source replaces that logical match with the chosen physical key code. Remaps
that use Option combinations replace the characters those combinations type.
Windows/Linux need separate configuration; Vorssaint changes macOS only.

A fresh install receives no suggested rules automatically.

## Compatibility and recovery

This uses macOS HID key mapping and an Accessibility event tap without a
virtual keyboard driver. Fn must be exposed to macOS; some keyboards handle it
in firmware. Verify a physical Fn press after disabling overlapping rules. A
confirmed mapping table alone cannot prove that the keyboard sends Fn events.
macOS Modifier Keys mappings run first; overlapping assignments pause this
feature. Restore the overlapping keys under System Settings → Keyboard →
Keyboard Shortcuts → Modifier Keys, then re-enable Keyboard Remaps.
A remapped Fn loses its usual Fn+function-key alternate behavior.

Super Key takes precedence and pauses Keyboard Remaps while enabled. Up to
seven physical action keys use F19, F20, F17, F16, F15, F14 and F13 as internal
triggers; only the triggers actually needed are reserved. Physical presses of
these keys share their assigned actions. Allocation avoids keys used by other
rules; configurations with no free trigger slots are refused. Ordinary shortcut-only actions do not use these slots,
except Caps Lock, which needs a releasable trigger for modifier combinations.

Duplicate active sources, invalid targets, self-maps, and overlapping external
mappings are refused before applying. External per-keyboard tables must agree
before any global write. Unrelated mappings are retained, and writes are read
back. Disable, session suspension and normal exit remove the exact owned
entries. A pipe helper handles process death and a machine-only marker supports
recovery on next launch. Wake and raw source events schedule mapping repair;
the first press before repair may retain the original behavior.

Rule choices participate in settings backup; mapping ownership does not.

## References

- [Apple's HID key mapping technical note](https://developer.apple.com/library/archive/technotes/tn2450/)
- [Apple's Mac shortcut reference](https://support.apple.com/en-us/102650)
- [Karabiner's examples and Fn limitations](https://karabiner-elements.pqrs.org/docs/getting-started/features/)
