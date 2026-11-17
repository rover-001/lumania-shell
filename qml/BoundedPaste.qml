import QtQuick
import Quickshell.Io

// Read clipboard text outside Qt's synchronous Wayland clipboard path and cap
// the amount delivered to a TextInput.
Item {
  id: root

  property var targetInput

  function paste() {
    if (!targetInput || clipboardReader.running) return
    clipboardReader.running = true
  }

  Process {
    id: clipboardReader
    command: ["sh", "-c", "wl-paste --no-newline --type text/plain 2>/dev/null | head -c 4097"]

    stdout: StdioCollector {
      onStreamFinished: {
        if (!root.targetInput || !root.targetInput.activeFocus || text.length === 0 || text.length > 4096) return

        var start = root.targetInput.selectionStart
        var end = root.targetInput.selectionEnd
        var insertion = text.replace(/[\r\n\0]/g, "")
        var available = root.targetInput.maximumLength - (root.targetInput.text.length - (end - start))
        insertion = insertion.slice(0, Math.max(0, available))
        if (insertion.length === 0) return
        root.targetInput.remove(start, end)
        root.targetInput.insert(start, insertion)
        root.targetInput.cursorPosition = start + insertion.length
      }
    }
  }
}
