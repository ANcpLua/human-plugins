// mic-active: prints "1" if the current default input device is actively
// running (i.e. some app has the mic open — a call/recording), else "0".
// Uses CoreAudio's canonical kAudioDevicePropertyDeviceIsRunningSomewhere.
import CoreAudio
import Foundation

func defaultInputDevice() -> AudioDeviceID? {
    var id = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    var addr = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultInputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    let st = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                        &addr, 0, nil, &size, &id)
    return st == noErr ? id : nil
}

func isRunning(_ dev: AudioDeviceID) -> Bool {
    var running = UInt32(0)
    var size = UInt32(MemoryLayout<UInt32>.size)
    var addr = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    let st = AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &running)
    return st == noErr && running != 0
}

if let dev = defaultInputDevice(), isRunning(dev) {
    print("1")
} else {
    print("0")
}
