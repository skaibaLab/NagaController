import ApplicationServices

// Test that system flags are preserved
if let event = CGEvent(keyboardEventSource: nil, virtualKey: 18, keyDown: true) {
    print("Initial flags: \(event.flags.rawValue) (binary: \(String(event.flags.rawValue, radix: 2)))")
    
    let modifiers: CGEventFlags = [.maskCommand, .maskControl]
    event.flags.formUnion(modifiers)
    
    print("After formUnion: \(event.flags.rawValue) (binary: \(String(event.flags.rawValue, radix: 2)))")
    print("Contains command: \(event.flags.contains(.maskCommand))")
    print("Contains control: \(event.flags.contains(.maskControl))")
    print("\nCommand bit: \(String(CGEventFlags.maskCommand.rawValue, radix: 2))")
    print("Control bit: \(String(CGEventFlags.maskControl.rawValue, radix: 2))")
}
