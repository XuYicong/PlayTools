//
//  MacPlugin.swift
//  AKInterface
//
//  Created by Isaac Marovitz on 13/09/2022.
//

import AppKit
import CoreGraphics
import Foundation

class AKPlugin: NSObject, Plugin {
    required override init() {
    }

    var screenCount: Int {
        NSScreen.screens.count
    }

    var mousePoint: CGPoint {
        NSApplication.shared.windows.first?.mouseLocationOutsideOfEventStream ?? CGPoint()
    }

    var windowFrame: CGRect {
        NSApplication.shared.windows.first?.frame ?? CGRect()
    }

    var isMainScreenEqualToFirst: Bool {
        return NSScreen.main == NSScreen.screens.first
    }

    var mainScreenFrame: CGRect {
        return NSScreen.main!.frame as CGRect
    }

    var isFullscreen: Bool {
        NSApplication.shared.windows.first!.styleMask.contains(.fullScreen)
    }

    var cmdPressed: Bool = false
    var cursorHideLevel = 0
    func hideCursor() {
        NSCursor.hide()
        cursorHideLevel += 1
        CGAssociateMouseAndMouseCursorPosition(0)
        warpCursor()
    }

    func warpCursor() {
        guard let firstScreen = NSScreen.screens.first else {return}
        let frame = windowFrame
        // Convert from NS coordinates to CG coordinates
        CGWarpMouseCursorPosition(CGPoint(x: frame.midX, y: firstScreen.frame.height - frame.midY))
    }

    func unhideCursor() {
        NSCursor.unhide()
        cursorHideLevel -= 1
        if cursorHideLevel <= 0 {
            CGAssociateMouseAndMouseCursorPosition(1)
        }
    }

    func terminateApplication() {
        NSApplication.shared.terminate(self)
    }

    private var modifierFlag: UInt = 0
    func setupKeyboard(keyboard: @escaping(UInt16, Bool, Bool) -> Bool,
                       swapMode: @escaping() -> Bool) {
        func checkCmd(modifier: NSEvent.ModifierFlags) -> Bool {
            if modifier.contains(.command) {
                self.cmdPressed = true
                return true
            } else if self.cmdPressed {
                self.cmdPressed = false
            }
            return false
        }
        NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { event in
            if checkCmd(modifier: event.modifierFlags) {
                return event
            }
            let consumed = keyboard(event.keyCode, true, event.isARepeat)
            if consumed {
                return nil
            }
            return event
        })
        NSEvent.addLocalMonitorForEvents(matching: .keyUp, handler: { event in
            if checkCmd(modifier: event.modifierFlags) {
                return event
            }
            let consumed = keyboard(event.keyCode, false, false)
            if consumed {
                return nil
            }
            return event
        })
        NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: { event in
            if checkCmd(modifier: event.modifierFlags) {
                return event
            }
            let pressed = self.modifierFlag < event.modifierFlags.rawValue
            let changed = self.modifierFlag ^ event.modifierFlags.rawValue
            self.modifierFlag = event.modifierFlags.rawValue
            if pressed && NSEvent.ModifierFlags(rawValue: changed).contains(.option) {
                if swapMode() {
                    return nil
                }
                return event
            }
            let consumed = keyboard(event.keyCode, pressed, false)
            if consumed {
                return nil
            }
            return event
        })
    }

    func setupMouseMoved(_ mouseMoved: @escaping(CGFloat, CGFloat) -> Bool) {
        let mask: NSEvent.EventTypeMask = [.leftMouseDragged, .otherMouseDragged, .rightMouseDragged]
        NSEvent.addLocalMonitorForEvents(matching: mask, handler: { event in
            let consumed = mouseMoved(event.deltaX, event.deltaY)
            if consumed {
                return nil
            }
            return event
        })
        // transpass mouse moved event when no button pressed, for traffic light button to light up
        NSEvent.addLocalMonitorForEvents(matching: .mouseMoved, handler: { event in
            _ = mouseMoved(event.deltaX, event.deltaY)
            return event
        })
    }

    func setupMouseButton(left: Bool, right: Bool, _ consumed: @escaping(Int, Bool) -> Bool) {
        let downType: NSEvent.EventTypeMask = left ? .leftMouseDown : right ? .rightMouseDown : .otherMouseDown
        let upType: NSEvent.EventTypeMask = left ? .leftMouseUp : right ? .rightMouseUp : .otherMouseUp
        NSEvent.addLocalMonitorForEvents(matching: downType, handler: { event in
            // For traffic light buttons when fullscreen
            if event.window != NSApplication.shared.windows.first! {
                return event
            }
            if consumed(event.buttonNumber, true) {
                return nil
            }
            return event
        })
        NSEvent.addLocalMonitorForEvents(matching: upType, handler: { event in
            if consumed(event.buttonNumber, false) {
                return nil
            }
            return event
        })
    }

    func setupScrollWheel(_ onMoved: @escaping(CGFloat, CGFloat) -> Bool) {
        NSEvent.addLocalMonitorForEvents(matching: NSEvent.EventTypeMask.scrollWheel, handler: { event in
            var deltaX = event.scrollingDeltaX, deltaY = event.scrollingDeltaY
            if !event.hasPreciseScrollingDeltas {
                deltaX *= 16
                deltaY *= 16
            }
            let consumed = onMoved(deltaX, deltaY)
            if consumed {
                guard let cgevt = MagnifyGesture.shared.getEvent(
                    magnification: Float32(deltaY),
                    proto: event.cgEvent) else { return nil }
                let nsEvent = NSEvent(cgEvent: cgevt)
                NSLog("Constructed: \(String(describing: nsEvent))")
//                guard let data = event.cgEvent?.data else { return nil }
//                let length = CFDataGetLength(data)
//                let bytes = CFDataGetBytePtr(data)
//                for idx in 0..<length {
//                    NSLog("\(bytes![idx])")
//                }
//                NSLog("这是滚轮")
                // 暂时从post来传递事件
                return nil
//                return nsEvent
            }
            return event
        })
        NSEvent.addLocalMonitorForEvents(matching: .magnify, handler: {event in
            NSLog("Monitored: \(event)")
            guard let cgevent = event.cgEvent else { return event }
//            for id in 0..<256 {
//                guard let field = CGEventField(rawValue: UInt32(id)) else { continue }
//                let value = cgevent.getIntegerValueField(field)
//                NSLog("field: \(id), value: \(value)")
//            }
            let newEvent = NSEvent(cgEvent: cgevent)
            NSLog("New: \(String(describing: newEvent))")
            // Test to see what the `post` thing has changed my fields
            if let originalEvent = MagnifyGesture.shared.lastEvent {
//                for id in 0..<256 {
//                    guard let field = CGEventField(rawValue: UInt32(id)) else { continue }
//                    let value = cgevent.getIntegerValueField(field)
//                    let valueFloat = cgevent.getDoubleValueField(field)
//                    let valueBefore = originalEvent.getIntegerValueField(field)
//                    let valueFloatBefore = originalEvent.getDoubleValueField(field)
//                    if value != valueBefore {
//                        NSLog("Diff: Field: \(id), before: \(valueBefore)(\(valueFloatBefore)), after: \(value)(\(valueFloat))")
//                    }
//                }
//                MagnifyGesture.shared.lastEvent = nil
                // The above are all the same and it not working!
                // I'm dumping the entire data to see difference!
//                guard let data = cgevent.data else { return newEvent }
//                guard let dataBefore = originalEvent.data else { return newEvent }
//                // If all data are the same then nothing can differ them right?
//                let length = CFDataGetLength(data)
//                let lengthBefore = CFDataGetLength(dataBefore)
//                let bytes = CFDataGetBytePtr(data)
//                let bytesBefore = CFDataGetBytePtr(dataBefore)
//                for idx in 0..<length {
//                    NSLog("\(bytes![idx])")
//                }
//                NSLog("继续打印！")
//                for idx in 0..<lengthBefore {
//                    NSLog("\(bytesBefore![idx])")
//                }
//                NSLog("看看区别！")
                // 44-52行 differ
            } else {
                guard let data = cgevent.data else { return newEvent }
//                let length = CFDataGetLength(data)
//                let bytes = CFDataGetBytePtr(data)
//                NSLog("原生的也看看！")
//                for idx in 0..<length {
//                    NSLog("\(bytes![idx])")
//                }
            }
            return newEvent
        })
    }

    func urlForApplicationWithBundleIdentifier(_ value: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: value)
    }

    func setMenuBarVisible(_ visible: Bool) {
        NSMenu.setMenuBarVisible(visible)
    }
}
