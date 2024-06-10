//
//  MagnifyGesture.swift
//  AKInterface
//
//  Created by 许沂聪 on 2024/6/9.
//

import Foundation

public class MagnifyGesture {
    static public var shared: MagnifyGesture = MagnifyGesture()
    public var magnification: Float32
    // get by comparing with the event after the post action
    private let fieldsToCopy: [UInt32] = [
        164, 106, 107,
//        101, 
        85, 57,
//        58, // timestamp
//        59, 
//        169, // timestamp
                                          53, 52, 51, // windowNumber
                                          39, // eventTargetProcessSerialNumber
                                          40
    ]
    // These fields should also be filled with magnification data
    private let dataFields: [UInt32] = [115, 117, 164]
    private var phase: Int
    public var lastEvent: CGEvent?
    private init() {
        magnification = 0.0
        phase = kIOHIDEventPhaseUndefined
    }
    public func getEvent(magnification: Float32, proto: CGEvent?) -> CGEvent? {
        self.magnification = magnification * 0.01
        switch phase {
        case kIOHIDEventPhaseBegan:
            phase = kIOHIDEventPhaseChanged
        case kIOHIDEventPhaseEnded:
            phase = kIOHIDEventPhaseBegan
//        case kIOHIDEventPhaseChanged:
//            phase = kIOHIDEventPhaseEnded
        default:
            phase = kIOHIDEventPhaseBegan
        }

        let gestureDict: [String: Any] = [
            kTLInfoKeyGestureSubtype as String: kTLInfoSubtypeMagnify,
            kTLInfoKeyGesturePhase as String: phase,
            kTLInfoKeyMagnification as String: self.magnification
        ]

        guard let cgEvent = tl_CGEventCreateFromGesture(gestureDict as CFDictionary, [] as CFArray)
        else { return nil }
        var copied = cgEvent.takeRetainedValue()
        // CGEvent.post() works, but require accessibility permission
        // Instead, we manually do the work of the post pipeline
        // field raw value was found out by experiment
        let untackedEvent = copied.copy()
        // TODO: experiment to see what fields has `post` changed
        if let refer = proto {
            for id in fieldsToCopy {
                guard let field = CGEventField(rawValue: id) else { return nil }
                let value = refer.getIntegerValueField(field)
                copied.setIntegerValueField(field, value: value)
            }
        }
        for id in dataFields {
            guard let field = CGEventField(rawValue: id) else { return nil }
            let value = self.magnification
            // Note: should be Float32, not Double
            copied.setIntegerValueField(field, value: Int64(value.bitPattern))
        }
        // TODO: see difference of copied and posted
        // if copy: 60. if untack: 0
        copied.setIntegerValueField(CGEventField(rawValue: 101)!, value: 52) // magic?
        if let refer = proto {
            // Forcely set location
            copied.location = refer.location
            let data = copied.data
            let mutableData = CFDataCreateMutableCopy(kCFAllocatorDefault, 0, data)
            // bytes before: version(4) + Int32*3[53, 54, 55](24) + 2Float32[56](12) + header(4)
            let idx = 4 + 24 + 12 + 4 // 44
            let referData = refer.data
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 8)
            CFDataGetBytes(referData, CFRange(location: idx, length: 8), buffer)
            CFDataReplaceBytes(mutableData, CFRange(location: idx, length: 8), buffer, 8)
            copied = CGEvent(withDataAllocator: kCFAllocatorDefault, data: mutableData)!
        }
        lastEvent = copied
        untackedEvent!.post(tap: .cgSessionEventTap)
        return copied
    }
}
