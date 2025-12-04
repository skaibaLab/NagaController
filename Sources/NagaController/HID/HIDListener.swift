import Foundation
import IOKit.hid

final class HIDListener {
    static let shared = HIDListener()

    private var manager: IOHIDManager
    private let queue = DispatchQueue(label: "HIDListener.queue")

    // Recent button presses from the Naga device (by logical button index 1..12)
    // Value is timestamp (seconds since reference)
    private var recentPressTimestamps: [Int: TimeInterval] = [:]
    // Consider a HID press "recent" within this time window (seconds)
    // Increased to account for scheduling/processing latency between HID and event tap
    private let recentWindow: TimeInterval = 1.00
    private let dpiUpCookie: IOHIDElementCookie = IOHIDElementCookie(0x26b)
    private let dpiDownCookie: IOHIDElementCookie = IOHIDElementCookie(0x26d)
    private let scrollTiltCookie: IOHIDElementCookie = IOHIDElementCookie(0x66)  // Horizontal scroll tilt (usagePage=0xc, usage=0x238)
    private var syntheticStates: [Int: Bool] = [:]
    private var lastScrollTiltValue: Int = 0  // Track last tilt value to prevent duplicate processing
    private var tiltActionFired: Bool = false  // Track if we've already fired an action for current tilt gestureaaaaa
    private var lastTiltGestureTime: TimeInterval = 0  // Track when last tilt gesture completed
    private let tiltGestureCooldown: TimeInterval = 0.25  // Minimum time between tilt gestures (250ms)

    private init() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

        // Restrict: match only known vendors; still filter by product name fallback in callback
        let matches: [[String: Any]] = [
            [kIOHIDVendorIDKey as String: 0x068e], // Observed vendor for Naga V2 HS
            [kIOHIDVendorIDKey as String: 0x1532]  // Razer Inc.
        ]
        IOHIDManagerSetDeviceMatchingMultiple(manager, matches as CFArray)

        IOHIDManagerRegisterInputValueCallback(manager, { context, result, sender, value in
            guard let context = context else { return }
            let this = Unmanaged<HIDListener>.fromOpaque(context).takeUnretainedValue()
            this.handle(value: value)
        }, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()))

        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.commonModes.rawValue)
        let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if openResult != kIOReturnSuccess {
            NSLog("[HID] IOHIDManagerOpen failed: \(openResult)")
        } else {
            NSLog("[HID] Listener started (vendors: 0x68e, 0x1532; plus product contains 'naga')")
            // Enumerate currently matched devices for diagnostics
            if let set = IOHIDManagerCopyDevices(manager) {
                let devices = (set as NSSet) as! Set<IOHIDDevice>
                for dev in devices {
                    let vendor = HIDListener.vendorID(device: dev) ?? -1
                    let product = (IOHIDDeviceGetProperty(dev, kIOHIDProductKey as CFString) as? String) ?? "<unknown>"
                    NSLog("[HID] Device matched: vendor=0x\(String(vendor, radix: 16)), product=\(product)")
                }
            }
        }
    }

    private func record(buttonIndex: Int) {
        let now = CFAbsoluteTimeGetCurrent()
        queue.sync {
            recentPressTimestamps[buttonIndex] = now
        }
    }

    private func handle(value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let usagePage = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        let pressedValue = IOHIDValueGetIntegerValue(value)
        let pressed = pressedValue != 0

        let device = IOHIDElementGetDevice(element)

        // Handle non-keyboard usages (e.g. DPI buttons)
        if usagePage != 0x07 {
            guard HIDListener.isNagaDevice(device: device) else { return }
            let cookie = IOHIDElementGetCookie(element)
            if cookie == dpiUpCookie {
                handleSynthetic(buttonIndex: 13, pressed: (pressedValue & 0x80) != 0, rawValue: pressedValue)
            } else if cookie == dpiDownCookie {
                handleSynthetic(buttonIndex: 14, pressed: (pressedValue & 0x40) != 0, rawValue: pressedValue)
            } else if cookie == scrollTiltCookie {
                // Scroll tilt uses same cookie but different values: -1 = left, 1 = right
                // Mouse sends alternating values (e.g., -1, 0, -1, 0...) so we need to only
                // trigger on the FIRST non-zero value, then wait for stable return to 0
                let intValue = Int(pressedValue)
                NSLog("[HID] Scroll tilt cookie MATCHED: cookie=0x\(String(UInt32(cookie), radix: 16)), value=\(intValue), lastValue=\(lastScrollTiltValue), actionFired=\(tiltActionFired)")

                // Check state and determine action (thread-safe)
                let (shouldFireLeft, shouldFireRight, shouldRelease) = queue.sync { () -> (Bool, Bool, Bool) in
                    let now = CFAbsoluteTimeGetCurrent()
                    let timeSinceLastGesture = now - lastTiltGestureTime

                    let isNewTilt = (lastScrollTiltValue == 0 && intValue != 0)
                    let isRelease = (lastScrollTiltValue != 0 && intValue == 0)

                    lastScrollTiltValue = intValue

                    // Only fire if enough time has passed since last gesture completed
                    if isNewTilt && !tiltActionFired && timeSinceLastGesture >= tiltGestureCooldown {
                        // First non-zero value in this gesture - fire the action
                        tiltActionFired = true
                        lastTiltGestureTime = now
                        return (intValue == -1, intValue == 1, false)
                    } else if isRelease && tiltActionFired {
                        // Returned to neutral - reset for next gesture
                        tiltActionFired = false
                        return (false, false, true)
                    } else if intValue == 0 && !tiltActionFired {
                        // Stable at 0, ensure we're ready for next gesture
                        tiltActionFired = false
                    }
                    // All other events (duplicate -1s, 1s, or 0s mid-gesture) are ignored
                    return (false, false, false)
                }

                // Execute actions outside the sync block to avoid deadlock
                if shouldFireLeft {
                    handleSynthetic(buttonIndex: 16, pressed: false, rawValue: 0) // Ensure right is released
                    handleSynthetic(buttonIndex: 15, pressed: true, rawValue: pressedValue)
                    NSLog("[HID] Scroll tilt LEFT - action fired")
                } else if shouldFireRight {
                    handleSynthetic(buttonIndex: 15, pressed: false, rawValue: 0) // Ensure left is released
                    handleSynthetic(buttonIndex: 16, pressed: true, rawValue: pressedValue)
                    NSLog("[HID] Scroll tilt RIGHT - action fired")
                } else if shouldRelease {
                    handleSynthetic(buttonIndex: 15, pressed: false, rawValue: pressedValue)
                    handleSynthetic(buttonIndex: 16, pressed: false, rawValue: pressedValue)
                    NSLog("[HID] Scroll tilt RELEASED - ready for next gesture")
                }
            } else {
                let vendor = HIDListener.vendorID(device: device)
                let product = (IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String) ?? "<unknown>"
                let vendorHex = vendor.map { String($0, radix: 16) } ?? "-1"
                let usagePageHex = String(usagePage, radix: 16)
                let usageHex = String(usage, radix: 16)
                let cookieHex = String(UInt32(cookie), radix: 16)
                NSLog("[HID] Non-keyboard usage detected: vendor=0x\(vendorHex), product=\(product), usagePage=0x\(usagePageHex), usage=0x\(usageHex), cookie=0x\(cookieHex), value=\(pressedValue)")
            }
            return
        }

        guard pressed else { return }

        // Only accept events from Naga devices to avoid remapping real keyboards
        guard HIDListener.isNagaDevice(device: device) else {
            if let product = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String,
               let vendor = HIDListener.vendorID(device: device) {
                NSLog("[HID] Ignored keyboard usage from device: vendor=0x\(String(vendor, radix: 16)), product=\(product), usage=0x\(String(usage, radix: 16))")
            }
            return
        }

        // Convert HID usage to our logical button index (1..12)
        guard let buttonIndex = HIDListener.buttonIndex(forUsage: usage) else {
            NSLog("[HID] Keyboard usage with no mapping: usage=0x%{public}X (page 0x07)", usage)
            return
        }

        // Record timestamp
        record(buttonIndex: buttonIndex)
        // Debug
        if let productCF = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString),
           let product = productCF as? String,
           let vendor = HIDListener.vendorID(device: device) {
            NSLog("[HID] Press recorded: vendor=0x\(String(vendor, radix: 16)), product=\(product), usage=0x\(String(usage, radix: 16)), buttonIndex=\(buttonIndex)")
        } else {
            NSLog("[HID] Press recorded: usage=0x\(String(usage, radix: 16)), buttonIndex=\(buttonIndex)")
        }
    }

    private func handleSynthetic(buttonIndex: Int, pressed: Bool, rawValue: Int) {
        let previous = queue.sync { syntheticStates[buttonIndex] ?? false }
        if previous == pressed { return }

        if pressed {
            record(buttonIndex: buttonIndex)
        }

        queue.sync { syntheticStates[buttonIndex] = pressed }

        if pressed {
            NSLog("[HID] Synthetic press captured for button \(buttonIndex) (raw=0x\(String(rawValue, radix: 16)))")
            if ConfigManager.shared.getRemappingEnabled() {
                ButtonMapper.shared.handlePress(buttonIndex: buttonIndex)
            }
        } else {
            NSLog("[HID] Synthetic release captured for button \(buttonIndex)")
            if ConfigManager.shared.getRemappingEnabled() {
                ButtonMapper.shared.handleRelease(buttonIndex: buttonIndex)
            }
        }
    }

    func wasRecentPress(buttonIndex: Int) -> Bool {
        let now = CFAbsoluteTimeGetCurrent()
        return queue.sync {
            if let t = recentPressTimestamps[buttonIndex] {
                return (now - t) <= recentWindow
            }
            return false
        }
    }

    private static func isNagaDevice(device: IOHIDDevice) -> Bool {
        let vendor = vendorID(device: device)
        let product = (IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String)?.lowercased()
        if let v = vendor, v == 0x1532 || v == 0x068e { return true } // Razer and observed Naga V2 HS vendor
        if let p = product, p.contains("naga") { return true }
        return false
    }

    private static func vendorID(device: IOHIDDevice) -> Int? {
        if let v = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int {
            return v
        }
        if let num = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? NSNumber {
            return num.intValue
        }
        return nil
    }

    private static func buttonIndex(forUsage usage: UInt32) -> Int? {
        // HID Usage for top row numbers on Keyboard page:
        // 0x1E..0x27 => 1..0, 0x2D => '-', 0x2E => '='
        switch usage {
        case 0x1E: return 1
        case 0x1F: return 2
        case 0x20: return 3
        case 0x21: return 4
        case 0x22: return 5
        case 0x23: return 6
        case 0x24: return 7
        case 0x25: return 8
        case 0x26: return 9
        case 0x27: return 10
        case 0x2D: return 11
        case 0x2E: return 12
        default: return nil
        }
    }
}
