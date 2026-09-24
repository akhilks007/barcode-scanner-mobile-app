import AVFoundation

/// Plays a short scanner-style beep. The sound is generated in code, so no audio file is needed.
@MainActor
final class BeepPlayer {
    static let shared = BeepPlayer()

    private var player: AVAudioPlayer?

    private init() {
        // .ambient: mixes with music/podcasts and follows the ring/silent switch.
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        player = try? AVAudioPlayer(data: Self.makeBeepWAV())
        player?.volume = 1.0
        player?.prepareToPlay()
    }

    func play() {
        guard let player else { return }
        player.currentTime = 0
        player.play()
    }

    /// Builds a mono 16-bit WAV of a sine-wave tone with short fade in/out (avoids clicks).
    private static func makeBeepWAV(frequency: Double = 2400,
                                    duration: Double = 0.12,
                                    sampleRate: Double = 44_100,
                                    amplitude: Double = 0.7) -> Data {
        let sampleCount = Int(duration * sampleRate)
        let fadeCount = Int(0.006 * sampleRate)
        var data = Data()

        func append<T: FixedWidthInteger>(_ value: T) {
            var le = value.littleEndian
            withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
        }

        let dataSize = UInt32(sampleCount * 2)
        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36) + dataSize)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        append(UInt32(16))                    // fmt chunk size
        append(UInt16(1))                     // PCM
        append(UInt16(1))                     // mono
        append(UInt32(sampleRate))            // sample rate
        append(UInt32(sampleRate) * 2)        // byte rate
        append(UInt16(2))                     // block align
        append(UInt16(16))                    // bits per sample
        data.append(contentsOf: Array("data".utf8))
        append(dataSize)

        for i in 0..<sampleCount {
            var level = amplitude
            if i < fadeCount {
                level *= Double(i) / Double(fadeCount)
            } else if i > sampleCount - fadeCount {
                level *= Double(sampleCount - i) / Double(fadeCount)
            }
            let value = sin(2 * .pi * frequency * Double(i) / sampleRate) * level
            append(Int16(value * Double(Int16.max)))
        }
        return data
    }
}

import AudioToolbox

/// Vibration on scan. Uses the classic system vibrate (like dedicated scanner apps), which is
/// stronger than a haptic tap and still works when "System Haptics" is off in iPhone Settings.
enum Vibration {
    static func play() {
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
    }
}
