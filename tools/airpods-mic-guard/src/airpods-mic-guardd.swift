// airpods-mic-guardd — event-driven AirPods mic guard.
//
// Problem (Bluetooth physics, not fixable in software): AirPods cannot do
// hi-fi A2DP output and act as a microphone simultaneously. If macOS makes
// AirPods the default INPUT while no app is using the mic, the whole link
// drops to HFP "phone call" quality for nothing. During an actual call the
// AirPods mic is wanted, so the guard must get out of the way.
//
// Design: zero polling. The process parks in CFRunLoopRun() and is woken by
// coreaudiod only when something relevant changes:
//   - system default input device changed
//   - system default output device changed
//   - device list changed (AirPods connected/disconnected)
//   - kAudioDevicePropertyDeviceIsRunningSomewhere on the current default
//     input (an app opened or closed the mic stream — call start/end)
//
// State machine on every wake:
//   AirPods are NOT both in+out .......... cancel grace, sleep
//   kill switch ~/.airpods-guard-off ..... cancel grace, sleep
//   mic stream owned by some app ......... on a call, cancel grace, sleep
//   else ................................. arm one-shot 15 s grace timer;
//                                          if conditions still hold when it
//                                          fires, push default input to the
//                                          built-in mic (AirPods snap back
//                                          to hi-fi A2DP)
//
// The grace window exists so a brief blip (AirPods reconnecting mid-call
// drops the stream for a moment) never yanks the mic away.

import CoreAudio
import Foundation

let queue = DispatchQueue(label: "dev.ancplua.airpods-mic-guard")
let graceSeconds: TimeInterval = 15
let killSwitch = NSString(string: "~/.airpods-guard-off").expandingTildeInPath

func shouldArmGrace(
    airPodsAreInput: Bool,
    airPodsAreOutput: Bool,
    microphoneIsOwned: Bool,
    killSwitchIsActive: Bool
) -> Bool {
    airPodsAreInput
        && airPodsAreOutput
        && !microphoneIsOwned
        && !killSwitchIsActive
}

if CommandLine.arguments.dropFirst() == ["--self-test"] {
    let cases = [
        (true, true, false, false, true),
        (false, true, false, false, false),
        (true, false, false, false, false),
        (true, true, true, false, false),
        (true, true, false, true, false),
    ]
    for (input, output, owned, disabled, expected) in cases {
        precondition(
            shouldArmGrace(
                airPodsAreInput: input,
                airPodsAreOutput: output,
                microphoneIsOwned: owned,
                killSwitchIsActive: disabled
            ) == expected
        )
    }
    print("airpods-mic-guard self-test: ok")
    exit(0)
}

let tsFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return f
}()

func log(_ msg: String) {
    FileHandle.standardError.write(
        "\(tsFormatter.string(from: Date())) \(msg)\n".data(using: .utf8)!)
}

// MARK: - CoreAudio helpers

func systemAddr(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(
        mSelector: selector,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
}

func defaultDevice(_ selector: AudioObjectPropertySelector) -> AudioDeviceID? {
    var id = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    var addr = systemAddr(selector)
    let st = AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
    return (st == noErr && id != kAudioObjectUnknown) ? id : nil
}

func deviceName(_ dev: AudioDeviceID) -> String {
    var addr = systemAddr(kAudioObjectPropertyName)
    var cfName: CFString = "" as CFString
    var size = UInt32(MemoryLayout<CFString>.size)
    let st = withUnsafeMutablePointer(to: &cfName) { ptr in
        AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, ptr)
    }
    return st == noErr ? (cfName as String) : ""
}

func micIsOwned(_ dev: AudioDeviceID) -> Bool {
    var running = UInt32(0)
    var size = UInt32(MemoryLayout<UInt32>.size)
    var addr = systemAddr(kAudioDevicePropertyDeviceIsRunningSomewhere)
    let st = AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &running)
    return st == noErr && running != 0
}

func transportType(_ dev: AudioDeviceID) -> UInt32 {
    var type = UInt32(0)
    var size = UInt32(MemoryLayout<UInt32>.size)
    var addr = systemAddr(kAudioDevicePropertyTransportType)
    let st = AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &type)
    return st == noErr ? type : 0
}

func hasInputStreams(_ dev: AudioDeviceID) -> Bool {
    var addr = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyStreams,
        mScope: kAudioObjectPropertyScopeInput,
        mElement: kAudioObjectPropertyElementMain)
    var size = UInt32(0)
    let st = AudioObjectGetPropertyDataSize(dev, &addr, 0, nil, &size)
    return st == noErr && size > 0
}

func allDevices() -> [AudioDeviceID] {
    var addr = systemAddr(kAudioHardwarePropertyDevices)
    var size = UInt32(0)
    guard AudioObjectGetPropertyDataSize(
        AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr
    else { return [] }
    var ids = [AudioDeviceID](
        repeating: kAudioObjectUnknown,
        count: Int(size) / MemoryLayout<AudioDeviceID>.size)
    guard AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr
    else { return [] }
    return ids
}

func setDefaultInput(_ dev: AudioDeviceID) {
    var id = dev
    var addr = systemAddr(kAudioHardwarePropertyDefaultInputDevice)
    let st = AudioObjectSetPropertyData(
        AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil,
        UInt32(MemoryLayout<AudioDeviceID>.size), &id)
    if st != noErr { log("ERROR setDefaultInput(\(deviceName(dev))) status=\(st)") }
}

/// Built-in mic if present, else the first non-AirPods input device.
func fallbackInput() -> AudioDeviceID? {
    let inputs = allDevices().filter(hasInputStreams)
    if let builtIn = inputs.first(where: {
        transportType($0) == kAudioDeviceTransportTypeBuiltIn
    }) { return builtIn }
    return inputs.first { !deviceName($0).lowercased().contains("airpod") }
}

// MARK: - State machine

var pendingGrace: DispatchWorkItem?
var runningListenerDevice: AudioDeviceID?
var runningAddr = systemAddr(kAudioDevicePropertyDeviceIsRunningSomewhere)

let onAudioEvent: AudioObjectPropertyListenerBlock = { _, _ in evaluate() }

func rebindRunningListener(to dev: AudioDeviceID?) {
    guard dev != runningListenerDevice else { return }
    if let old = runningListenerDevice {
        AudioObjectRemovePropertyListenerBlock(old, &runningAddr, queue, onAudioEvent)
    }
    runningListenerDevice = dev
    if let new = dev {
        AudioObjectAddPropertyListenerBlock(new, &runningAddr, queue, onAudioEvent)
    }
}

func cancelGrace(_ reason: String? = nil) {
    guard pendingGrace != nil else { return }
    pendingGrace?.cancel()
    pendingGrace = nil
    if let reason { log("grace cancelled: \(reason)") }
}

/// True while AirPods are both default output and default input (the bad HFP
/// state) with nobody actually using the mic.
func guardConditionHolds() -> Bool {
    guard let inDev = defaultDevice(kAudioHardwarePropertyDefaultInputDevice),
          let outDev = defaultDevice(kAudioHardwarePropertyDefaultOutputDevice)
    else { return false }
    return shouldArmGrace(
        airPodsAreInput: deviceName(inDev).lowercased().contains("airpod"),
        airPodsAreOutput: deviceName(outDev).lowercased().contains("airpod"),
        microphoneIsOwned: micIsOwned(inDev),
        killSwitchIsActive: FileManager.default.fileExists(atPath: killSwitch)
    )
}

func evaluate() {
    // Keep the mic-ownership listener attached to whatever is default input now.
    rebindRunningListener(to: defaultDevice(kAudioHardwarePropertyDefaultInputDevice))

    guard guardConditionHolds() else {
        cancelGrace()
        return
    }
    guard pendingGrace == nil else { return }  // grace already armed

    let work = DispatchWorkItem {
        pendingGrace = nil
        guard guardConditionHolds() else { return }  // re-verify after the wait
        guard let target = fallbackInput() else {
            log("no fallback input device available")
            return
        }
        setDefaultInput(target)
        log("mic idle for \(Int(graceSeconds))s while AirPods were in+out — moved input to \(deviceName(target))")
    }
    pendingGrace = work
    queue.asyncAfter(deadline: .now() + graceSeconds, execute: work)
    log("AirPods are in+out with idle mic — grace timer armed (\(Int(graceSeconds))s)")
}

// MARK: - Main

for selector: AudioObjectPropertySelector in [
    kAudioHardwarePropertyDefaultInputDevice,
    kAudioHardwarePropertyDefaultOutputDevice,
    kAudioHardwarePropertyDevices,
] {
    var addr = systemAddr(selector)
    AudioObjectAddPropertyListenerBlock(
        AudioObjectID(kAudioObjectSystemObject), &addr, queue, onAudioEvent)
}

queue.async {
    log("airpods-mic-guardd started (event-driven, grace \(Int(graceSeconds))s, kill switch: \(killSwitch))")
    evaluate()
}

CFRunLoopRun()
