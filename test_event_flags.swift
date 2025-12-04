import ApplicationServices

// Test different ways of setting flags
if let event1 = CGEvent(keyboardEventSource: nil, virtualKey: 18, keyDown: true) {
    print("Default event flags: \(event1.flags.rawValue)")
    
    event1.flags = .maskCommand
    print("After setting .maskCommand: \(event1.flags.rawValue)")
    
    event1.flags.insert(.maskControl)
    print("After inserting .maskControl: \(event1.flags.rawValue)")
}

print("\nTest 2: Creating with combined flags")
if let event2 = CGEvent(keyboardEventSource: nil, virtualKey: 18, keyDown: true) {
    let combined: CGEventFlags = [.maskCommand, .maskControl]
    event2.flags = combined
    print("Event flags: \(event2.flags.rawValue)")
    print("Binary: \(String(event2.flags.rawValue, radix: 2))")
}

print("\nCommand flag value: \(CGEventFlags.maskCommand.rawValue)")
print("Control flag value: \(CGEventFlags.maskControl.rawValue)")
print("Combined: \((CGEventFlags.maskCommand.rawValue | CGEventFlags.maskControl.rawValue))")
