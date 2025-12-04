import ApplicationServices

// Test if modifier flags are being combined correctly
let cmd: CGEventFlags = .maskCommand
let ctrl: CGEventFlags = .maskControl
let combined = cmd.union(ctrl)

print("Command flag: \(cmd.rawValue)")
print("Control flag: \(ctrl.rawValue)")
print("Combined flag: \(combined.rawValue)")
print("Combined contains command: \(combined.contains(.maskCommand))")
print("Combined contains control: \(combined.contains(.maskControl))")

// Create a test event
if let event = CGEvent(keyboardEventSource: nil, virtualKey: 18, keyDown: true) {
    event.flags = combined
    print("\nEvent flags: \(event.flags.rawValue)")
    print("Event contains command: \(event.flags.contains(.maskCommand))")
    print("Event contains control: \(event.flags.contains(.maskControl))")
}
