# Terminal emulator research — 2026-09-19

The UI needs a Flutter renderer and VT/xterm parser; SSH remains in `dartssh2`. Package metadata and licenses were checked against the publishers' pub.dev pages and KAMMEL's GitHub pubspec. This is a package selection, not an iOS device validation.

| Option | Version/license | Assessment |
|---|---|---|
| `xterm` | 4.0.0, MIT | Original package, iOS listed; VT/ANSI core, Unicode/wide characters, Flutter terminal view, IME, special-key handler, auto-resize, selection and bounded scrollback. Last release about two years old. Selected for a small stable M2 surface with known API and no fork. |
| `xterm2` | 5.2.0, MIT | Maintained fork of original; newer renderer/reflow/input work, iOS listed. Smaller adoption and a separate publisher. Reconsider after device testing or if original shows a concrete limitation. |
| `xterm3` | 6.3.0, AGPL-3.0-or-later | Maintained successor with modern VT/input/rendering; license imposes app distribution obligations. Not selected without a product licensing decision. |
| `terminal_view` | 0.2.0, MIT | Recent mobile-focused fork of xterm 4, iOS listed, claims coalesced rendering and better touch selection. Early 0.x maturity; not required by the bounded M2 lab. |

KAMMEL pins `xterm ^4.0.0` but overrides it with a vendored copy. Its public pubspec attributes two changes: a normal keyboard allowing suggestions/autocorrect/voice dictation instead of upstream's incognito keyboard, and inline image paste through soft keyboard insertion. AgentDeck M2 requires neither feature. Upstream `xterm` 4 exposes `TerminalView`, `Terminal.onOutput`, `onResize`, `TerminalController.selection`, `buffer.getText`, `paste` and `keyInput`. We use those without copying KAMMEL code or an override. Whether iOS virtual keyboard behavior warrants a later change remains a device question.

The xterm core interprets ANSI/VT (colors, cursor movement, carriage return, clearing and wrapping); AgentDeck does not parse terminal control sequences. `maxLines: 2000` bounds scrollback because terminal output can be large and device memory is finite. Terminal output is streamed to xterm by decoded chunks without an application copy of the full buffer. Touch selection/copy uses xterm's selection range, and Paste is an explicit button that invokes bracketed paste when the remote application requests it. Keyboard toolbar adds Esc, Tab, Ctrl and arrows; xterm handles physical keyboard keys. A one-shot Ctrl modifier forwards control characters for C/D/L. These behaviors need iOS device validation, especially soft keyboard, hardware keyboard, selection, clipboard, safe area, rotation, resize, background/resume and network loss.

Known limits: original xterm 4 is no longer actively maintained; app-specific performance beyond 2000 lab lines is unmeasured; terminal text reflow may differ on resize; iOS touch and IME behavior unverified. Reevaluate a maintained MIT fork after device evidence. The package lists iOS support but that alone does not prove AgentDeck's iPhone behavior.

Primary sources: https://pub.dev/packages/xterm ; https://pub.dev/packages/xterm/versions ; https://pub.dev/packages/xterm/license ; https://pub.dev/packages/xterm2 ; https://pub.dev/packages/xterm3 ; https://pub.dev/packages/terminal_view ; https://github.com/Jhongdlp/Kammel_ssh/blob/main/pubspec.yaml .
