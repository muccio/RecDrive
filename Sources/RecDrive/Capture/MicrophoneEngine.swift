import Foundation
import AVFoundation
import CoreAudio

/// Captures audio from the default input device (microphone) via AVAudioEngine
/// and transforms PCM audio buffers into CMSampleBuffer instances with accurate presentation timestamps.
public final class MicrophoneEngine: @unchecked Sendable {
    private let audioEngine = AVAudioEngine()
    private var isRunning = false
    private let lock = NSLock()
    
    private var onAudioSampleBuffer: ((CMSampleBuffer) -> Void)?
    private var sampleRate: Double = 48000.0
    private var channelCount: AVAudioChannelCount = 2
    
    public init() {}
    
    public func startCapture(handler: @escaping (CMSampleBuffer) -> Void) throws {
        lock.lock()
        defer { lock.unlock() }
        
        guard !isRunning else { return }
        self.onAudioSampleBuffer = handler
        
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        
        guard inputFormat.sampleRate > 0 && inputFormat.channelCount > 0 else {
            throw NSError(domain: "RecDrive.MicEngine", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid microphone audio input format."])
        }
        
        self.sampleRate = inputFormat.sampleRate
        self.channelCount = min(inputFormat.channelCount, 2)
        
        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: self.sampleRate,
            channels: self.channelCount,
            interleaved: true
        ) ?? inputFormat
        
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] (buffer, when) in
            guard let self = self else { return }
            self.processMicrophoneBuffer(buffer: buffer, when: when, targetFormat: targetFormat)
        }
        
        audioEngine.prepare()
        try audioEngine.start()
        isRunning = true
    }
    
    public func stopCapture() {
        lock.lock()
        defer { lock.unlock() }
        
        guard isRunning else { return }
        onAudioSampleBuffer = nil
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        isRunning = false
    }
    
    // MARK: - Buffer Conversion to CMSampleBuffer
    
    private func processMicrophoneBuffer(buffer: AVAudioPCMBuffer, when: AVAudioTime, targetFormat: AVAudioFormat) {
        guard let sampleBuffer = createSampleBuffer(from: buffer, presentationTime: when) else {
            return
        }
        onAudioSampleBuffer?(sampleBuffer)
    }
    
    private func createSampleBuffer(from pcmBuffer: AVAudioPCMBuffer, presentationTime: AVAudioTime) -> CMSampleBuffer? {
        let audioBufferList = pcmBuffer.audioBufferList
        let streamDesc = pcmBuffer.format.streamDescription
        
        var formatDesc: CMAudioFormatDescription?
        let status = CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: streamDesc,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDesc
        )
        guard status == noErr, let format = formatDesc else { return nil }
        
        // Compute presentation timestamp aligned with CoreMedia host time clock
        let pts: CMTime
        if presentationTime.isHostTimeValid && presentationTime.hostTime > 0 {
            pts = CMClockMakeHostTimeFromSystemUnits(presentationTime.hostTime)
        } else {
            pts = CMClockGetTime(CMClockGetHostTimeClock())
        }
        
        var timingInfo = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(pcmBuffer.format.sampleRate)),
            presentationTimeStamp: pts,
            decodeTimeStamp: .invalid
        )
        
        var sampleBuffer: CMSampleBuffer?
        let sampleCount = CMItemCount(pcmBuffer.frameLength)
        
        let createStatus = CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: nil,
            dataReady: false,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: format,
            sampleCount: sampleCount,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timingInfo,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        )
        
        guard createStatus == noErr, let createdBuffer = sampleBuffer else { return nil }
        
        let setStatus = CMSampleBufferSetDataBufferFromAudioBufferList(
            createdBuffer,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: 0,
            bufferList: audioBufferList
        )
        guard setStatus == noErr else { return nil }
        
        return createdBuffer
    }
    
    private func machTimeToSeconds(_ machTime: UInt64) -> Double {
        var timebaseInfo = mach_timebase_info_data_t()
        mach_timebase_info(&timebaseInfo)
        let nanos = Double(machTime * UInt64(timebaseInfo.numer)) / Double(timebaseInfo.denom)
        return nanos / 1_000_000_000.0
    }
}
