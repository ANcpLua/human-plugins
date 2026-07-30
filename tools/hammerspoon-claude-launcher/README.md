# hammerspoon-claude-launcher

Ctrl-middle-click or `Ctrl+Alt+Shift+F12` opens a Ghostty window running Claude
Code, then tiles only windows created by this launcher.

The managed config is installed at `~/.hammerspoon/init.lua`. It defaults to:

```text
terminal: /Applications/Ghostty.app/Contents/MacOS/ghostty
command:  ~/.local/bin/claude --ide
```

Set `HUMAN_TERMINAL_EXECUTABLE`, `HUMAN_TERMINAL_BUNDLE`, or
`HUMAN_AGENT_COMMAND` in Hammerspoon's environment to override those values.
The launcher contains no pinned model, external prompt, or permission bypass.

Hammerspoon still needs Accessibility and Input Monitoring access from macOS
System Settings. Reload after installation with the Hammerspoon menu or
`hs -c 'hs.reload()'`.
