import Foundation
import CoreMedia
import AVFoundation

/// High-performance real-time audio mixer that merges System Audio (ScreenCaptureKit)
/// and Microphone Audio into a single, continuous stereo 48000 Hz PCM stream.
/// Ensures 100% compatibility with standard media players (QuickTime, Safari, Chrome, VLC)
/// by providing a single unified primary audio track in the exported MP4 file.
public final class RealTimeAudioMixer: @unchecked Sendable {
    public let sampleRate: Double = 48000.0
    public let channelCount: Int = 2
    
    private let onMixedSampleBuffer: (CMSampleBuffer) -> Void
    private let lock = NSLock()
    
    // Timeline window buffer for real-time accumulation
    // Buffer represents a continuous sequence of stereo frames: [Left0, Right0, Left1, Right1, ...]
    private var timelineBuffer: [Float] = []
    private var timelineStartPTS: CMTime = .invalid
    private var lastEmittedPTS: CMTime = .invalid
    
    // Session tracking
    private var isSessionActive = false
    private let latencyWindowFrames: Int = 4800 // 100ms at 48kHz
    private let emitChunkFrames: Int = 1024    // Output chunk size
    
    private var formatDescription: CMAudioFormatDescription?
    
    public init(onMixedSampleBuffer: @escaping (CMSampleBuffer) -> Void) {
        self.onMixedSampleBuffer = onMixedSampleBuffer
        createFormatDescription()
    }
    
    private func createFormatDescription() {
        var asbd = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(channelCount * MemoryLayout<Float>.size),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(channelCount * MemoryLayout<Float>.size),
            mChannelsPerFrame: UInt32(channelCount),
            mBitsPerChannel: UInt32(8 * MemoryLayout<Float>.size),
            mReserved: 0
        )
        CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &asbd,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDescription
        )
    }
    
    // MARK: - Input Ingestion
    
    public func appendSystemAudio(_ sampleBuffer: CMSampleBuffer) {
        ingest(sampleBuffer: sampleBuffer, isMicrophone: false)
    }
    
    public func appendMicrophoneAudio(_ sampleBuffer: CMSampleBuffer) {
        ingest(sampleBuffer: sampleBuffer, isMicrophone: true)
    }
    
    private func ingest(sampleBuffer: CMSampleBuffer, isMicrophone: Bool) {
        guard sampleBuffer.isValid,
              let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)?.pointee else {
            return
        }
        
        let numSamples = CMSampleBufferGetNumSamples(sampleBuffer)
        guard numSamples > 0 else { return }
        
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard pts.isValid else { return }
        
        // Extract interleaved Float stereo samples from the incoming CMSampleBuffer
        guard let stereoFloats = extractStereoFloatSamples(from: sampleBuffer, asbd: asbd, numSamples: numSamples) else {
            return
        }
        
        lock.lock()
        defer { lock.unlock() }
        
        if !isSessionActive || !timelineStartPTS.isValid {
            isSessionActive = true
            timelineStartPTS = pts
            lastEmittedPTS = .invalid
        }
        
        // Calculate frame offset relative to timelineStartPTS
        let diffSeconds = CMTimeGetSeconds(pts - timelineStartPTS)
        let frameOffset = Int(round(diffSeconds * sampleRate))
        guard frameOffset >= 0 else {
            // Buffer is from the past before our timeline started, ignore to avoid retroactive corruption
            return
        }
        
        let sampleFrameCount = stereoFloats.count / channelCount
        let requiredTotalFrames = frameOffset + sampleFrameCount
        let requiredTotalFloats = requiredTotalFrames * channelCount
        
        if timelineBuffer.count < requiredTotalFloats {
            let paddingCount = requiredTotalFloats - timelineBuffer.count
            timelineBuffer.append(contentsOf: repeatElement(0.0, count: paddingCount))
        }
        
        // Mix incoming samples with saturation addition
        let startFloatIndex = frameOffset * channelCount
        for i in 0..<stereoFloats.count {
            let targetIdx = startFloatIndex + i
            if targetIdx < timelineBuffer.count {
                timelineBuffer[targetIdx] += stereoFloats[i]
            }
        }
        
        // Check if we can drain frames beyond the latency window
        drainReadyFramesLocked()
    }
    
    private func drainReadyFramesLocked() {
        guard timelineStartPTS.isValid else { return }
        
        let totalBufferedFrames = timelineBuffer.count / channelCount
        // Only drain when we have more than the latency window (100ms)
        let drainableFrames = totalBufferedFrames - latencyWindowFrames
        guard drainableFrames >= emitChunkFrames else { return }
        
        var framesToEmit = (drainableFrames / emitChunkFrames) * emitChunkFrames
        // Cap to reasonable chunk to prevent large spikes
        framesToEmit = min(framesToEmit, 8192)
        
        let floatsToEmit = framesToEmit * channelCount
        let chunkFloats = Array(timelineBuffer[0..<floatsToEmit])
        timelineBuffer.removeFirst(floatsToEmit)
        
        let chunkPTS = timelineStartPTS
        // Advance timelineStartPTS
        let advancedTime = CMTime(value: CMTimeValue(framesToEmit), timescale: CMTimeScale(sampleRate))
        timelineStartPTS = timelineStartPTS + advancedTime
        
        emitMixedChunk(floats: chunkFloats, frameCount: framesToEmit, pts: chunkPTS)
    }
    
    public func flush() {
        lock.lock()
        defer { lock.unlock() }
        
        guard timelineStartPTS.isValid && !timelineBuffer.isEmpty else {
            timelineBuffer.removeAll()
            return
        }
        
        let totalFrames = timelineBuffer.count / channelCount
        if totalFrames > 0 {
            let floatsToEmit = timelineBuffer
            let chunkPTS = timelineStartPTS
            timelineBuffer.removeAll()
            emitMixedChunk(floats: floatsToEmit, frameCount: totalFrames, pts: chunkPTS)
        }
    }
    
    private func emitMixedChunk(floats: [Float], frameCount: Int, pts: CMTime) {
        guard frameCount > 0, let format = formatDescription else { return }
        
        // Clamp all mixed samples between -1.0 and 1.0 to prevent audio clipping distortion
        var clampedFloats = floats
        for i in 0..<clampedFloats.count {
            let val = clampedFloats[i]
            if val > 1.0 { clampedFloats[i] = 1.0 }
            else if val < -1.0 { clampedFloats[i] = -1.0 }
        }
        
        // Ensure strictly monotonic and continuous PTS
        let finalPTS: CMTime
        if lastEmittedPTS.isValid {
            finalPTS = (pts < lastEmittedPTS) ? lastEmittedPTS : pts
        } else {
            finalPTS = pts
        }
        
        let chunkDuration = CMTime(value: CMTimeValue(frameCount), timescale: CMTimeScale(sampleRate))
        self.lastEmittedPTS = finalPTS + chunkDuration
        
        let byteCount = frameCount * channelCount * MemoryLayout<Float>.size
        var blockBuffer: CMBlockBuffer?
        let bbStatus = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: byteCount,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: byteCount,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard bbStatus == kCMBlockBufferNoErr, let bBuffer = blockBuffer else { return }
        
        let replaceStatus = clampedFloats.withUnsafeBytes { rawPtr in
            CMBlockBufferReplaceDataBytes(
                with: rawPtr.baseAddress!,
                blockBuffer: bBuffer,
                offsetIntoDestination: 0,
                dataLength: byteCount
            )
        }
        guard replaceStatus == kCMBlockBufferNoErr else { return }
        
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(sampleRate)),
            presentationTimeStamp: finalPTS,
            decodeTimeStamp: .invalid
        )
        
        var sampleBuffer: CMSampleBuffer?
        var sampleSize = channelCount * MemoryLayout<Float>.size
        let sbStatus = CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: bBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: format,
            sampleCount: CMItemCount(frameCount),
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
            sampleBufferOut: &sampleBuffer
        )
        
        if sbStatus == noErr, let createdBuffer = sampleBuffer {
            onMixedSampleBuffer(createdBuffer)
        }
    }
    
    // MARK: - Sample Extraction Helper
    
    private func extractStereoFloatSamples(
        from sampleBuffer: CMSampleBuffer,
        asbd: AudioStreamBasicDescription,
        numSamples: Int
    ) -> [Float]? {
        var bufferListSizeNeeded: Int = 0
        let sizeStatus = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &bufferListSizeNeeded,
            bufferListOut: nil,
            bufferListSize: 0,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: nil
        )
        guard sizeStatus == noErr, bufferListSizeNeeded > 0 else { return nil }
        
        let rawBuffer = UnsafeMutableRawPointer.allocate(
            byteCount: bufferListSizeNeeded,
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { rawBuffer.deallocate() }
        
        let ablPtr = rawBuffer.bindMemory(to: AudioBufferList.self, capacity: 1)
        var retainedBlockBuffer: CMBlockBuffer?
        
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: ablPtr,
            bufferListSize: bufferListSizeNeeded,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: &retainedBlockBuffer
        )
        guard status == noErr else { return nil }
        
        let bufferList = UnsafeMutableAudioBufferListPointer(ablPtr)
        guard bufferList.count > 0 else { return nil }
        
        var result = [Float](repeating: 0, count: numSamples * channelCount)
        
        let isFloat = (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        let isNonInterleaved = (asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0
        let channels = Int(asbd.mChannelsPerFrame)
        
        if isFloat {
            if isNonInterleaved && bufferList.count >= 2 {
                // Non-interleaved stereo
                if let m0 = bufferList[0].mData, let m1 = bufferList[1].mData {
                    let ptr0 = m0.assumingMemoryBound(to: Float.self)
                    let ptr1 = m1.assumingMemoryBound(to: Float.self)
                    for i in 0..<numSamples {
                        result[i * 2] = ptr0[i]
                        result[i * 2 + 1] = ptr1[i]
                    }
                }
            } else if let m0 = bufferList[0].mData {
                let ptr0 = m0.assumingMemoryBound(to: Float.self)
                if isNonInterleaved || channels == 1 {
                    // Non-interleaved mono or single channel -> replicate to Left and Right
                    for i in 0..<numSamples {
                        let val = ptr0[i]
                        result[i * 2] = val
                        result[i * 2 + 1] = val
                    }
                } else if channels >= 2 {
                    // Interleaved stereo
                    for i in 0..<numSamples {
                        result[i * 2] = ptr0[i * channels]
                        result[i * 2 + 1] = ptr0[i * channels + 1]
                    }
                }
            }
        } else {
            // 16-bit Int PCM conversion to Float [-1.0, 1.0]
            let factor: Float = 1.0 / 32768.0
            if isNonInterleaved && bufferList.count >= 2 {
                if let m0 = bufferList[0].mData, let m1 = bufferList[1].mData {
                    let ptr0 = m0.assumingMemoryBound(to: Int16.self)
                    let ptr1 = m1.assumingMemoryBound(to: Int16.self)
                    for i in 0..<numSamples {
                        result[i * 2] = Float(ptr0[i]) * factor
                        result[i * 2 + 1] = Float(ptr1[i]) * factor
                    }
                }
            } else if let m0 = bufferList[0].mData {
                let ptr0 = m0.assumingMemoryBound(to: Int16.self)
                if channels >= 2 && !isNonInterleaved {
                    for i in 0..<numSamples {
                        result[i * 2] = Float(ptr0[i * channels]) * factor
                        result[i * 2 + 1] = Float(ptr0[i * channels + 1]) * factor
                    }
                } else {
                    for i in 0..<numSamples {
                        let val = Float(ptr0[i]) * factor
                        result[i * 2] = val
                        result[i * 2 + 1] = val
                    }
                }
            }
        }
        
        // Handle resampling if input sample rate differs from 48000 Hz
        let inSampleRate = asbd.mSampleRate
        if inSampleRate > 0 && abs(inSampleRate - sampleRate) > 1.0 {
            let outSampleCount = Int(round(Double(numSamples) * sampleRate / inSampleRate))
            guard outSampleCount > 0 else { return result }
            var resampled = [Float](repeating: 0, count: outSampleCount * channelCount)
            let ratio = Double(numSamples - 1) / Double(max(1, outSampleCount - 1))
            for i in 0..<outSampleCount {
                let srcPos = Double(i) * ratio
                let srcIdx = Int(srcPos)
                let frac = Float(srcPos - Double(srcIdx))
                let nextIdx = min(srcIdx + 1, numSamples - 1)
                for ch in 0..<channelCount {
                    let s0 = result[srcIdx * channelCount + ch]
                    let s1 = result[nextIdx * channelCount + ch]
                    resampled[i * channelCount + ch] = s0 + frac * (s1 - s0)
                }
            }
            return resampled
        }
        
        return result
    }
}
