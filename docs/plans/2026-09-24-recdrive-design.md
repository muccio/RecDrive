# RecDrive - Architectural Design Document

**Date:** 2026-09-24  
**Target:** macOS 13.0+ (Ventura, Sonoma, Sequoia+)  
**Architecture:** Apple Silicon Native (ARM64)  
**Type:** Menu Bar App (`LSUIElement = true`), Zero Heavy Dependencies  

---

## 1. Executive Summary & Product Vision

**RecDrive** is an ultra-lightweight, hardware-accelerated macOS menu bar application designed for recording screen activity and system/microphone audio, with immediate resumable upload to Google Drive.

Key pillars:
- **Zero Overhead**: Native Swift + SwiftUI / AppKit. No Electron, no web wrappers, no third-party framework overhead.
- **Apple Silicon Hardware Acceleration**: Direct NV12 (`kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange`) frame pipeline through `ScreenCaptureKit` into `AVAssetWriter` using `VideoToolbox` hardware H.264 / HEVC encoders.
- **Background Resumable Upload**: Non-blocking Google Drive REST API v3 resumable chunked upload (`uploadType=resumable`) with automatic retry and byte-range reconciliation (`Content-Range`).
- **Security & Privacy First**: OAuth 2.0 with PKCE (Proof Key for Code Exchange), Refresh Token stored securely in macOS Keychain (`kSecClassGenericPassword`), permissions explicitly scoped to `drive.file`.

---

## 2. System Architecture & Module Structure

```
_SCREEN_CAPTURER/
├── Package.swift                       # Swift Package Manager build definition
├── Sources/
│   └── RecDrive/
│       ├── App/
│       │   ├── RecDriveApp.swift       # Application entry point (@main, NSApplicationDelegate)
│       │   └── AppState.swift          # Central reactive state manager (@Observable / ObservableObject)
│       ├── Capture/
│       │   ├── ScreenCaptureManager.swift # SCStream and SCShareableContent controller
│       │   ├── MediaWriter.swift       # AVAssetWriter video/audio sync & hardware encoding
│       │   ├── MicrophoneEngine.swift  # AVAudioEngine microphone stream capture
│       │   └── CaptureModels.swift     # Data models (CaptureSource, AudioSourceConfig, StreamQuality)
│       ├── Drive/
│       │   ├── DriveService.swift      # Google Drive REST API v3 Resumable Upload Engine
│       │   ├── OAuthManager.swift      # OAuth 2.0 PKCE flow, loopback server, token refresh
│       │   ├── AuthConfig.swift        # Client ID, Redirect URI, endpoints, scope definitions
│       │   └── DriveModels.swift       # File/Folder representations and API responses
│       ├── Storage/
│       │   ├── KeychainHelper.swift    # macOS Keychain Services wrapper
│       │   ├── PreferencesStorage.swift # UserDefaults for app settings
│       │   └── LocalStorageManager.swift# File directory management (~/Movies/RecDrive/)
│       └── UI/
│           ├── MenuBarView.swift       # SwiftUI Menu Bar popover and quick actions
│           ├── StatusItemController.swift # NSStatusItem coordinator with animated icons
│           ├── SettingsView.swift      # Preferences window (OAuth, folder picker, options)
│           └── SourcePickerView.swift  # Display & Window visual selector
├── Resources/
│   ├── Info.plist                      # LSUIElement, usage descriptions, URL schemes
│   └── RecDrive.entitlements           # App entitlements (Network, Audio, Screen Capture)
└── docs/
    └── plans/
        ├── task.md                     # Live task checklist tracker
        └── 2026-09-24-recdrive-design.md
```

---

## 3. Core Engine Specifications

### 3.1 Video & Audio Capture Pipeline (`ScreenCaptureKit` + `AVAssetWriter`)

#### Video Path:
1. `SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)` enumerates displays (`SCDisplay`) and on-screen windows (`SCWindow`).
2. `SCStreamConfiguration`:
   - `pixelFormat`: `kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange` (NV12), directly ingestible by Apple Silicon media engine.
   - `minimumFrameInterval`: `CMTime(value: 1, timescale: 60)` (60 fps target) or 30 fps eco mode.
   - `showsCursor`: Configurable (default `true`).
   - `capturesAudio`: `true` (intercepts system audio at kernel/HAL level via ScreenCaptureKit).
3. `SCStreamOutput` callback delivers `CMSampleBuffer`:
   - Route `sampleBuffer` to `MediaWriter` on a dedicated serial dispatch queue (`com.recdrive.videowriter`).

#### Audio Path:
1. **System Audio**: Provided directly by `SCStream` with `SCStreamOutputType.audio`.
2. **Microphone Audio**: Captured via `AVAudioEngine.inputNode` on a 48 kHz float32/int16 stream, converted into `CMSampleBuffer` or mixed synchronously before AAC encoding.
3. `MediaWriter` initializes:
   - Video Input: `AVAssetWriterInput` with `AVVideoCodecType.hevc` (or `h264` fallback), bitrate capped (e.g. 8-15 Mbps depending on resolution).
   - Audio Input: `AVAssetWriterInput` with `kAudioFormatMPEG4AAC`, 48 kHz, stereo 192 kbps.
4. Synchronizer: First video frame timestamp establishes session start (`startSession(atSourceTime:)`). Audio samples prior to session start are dropped to guarantee lipsync.

---

### 3.2 Google Drive Resumable Upload Pipeline

Conformant to Google Drive API v3:
1. **Initiate Session**:
   - `POST https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable`
   - Headers:
     - `Authorization: Bearer <access_token>`
     - `X-Upload-Content-Type: video/mp4`
     - `X-Upload-Content-Length: <file_size>`
     - `Content-Type: application/json; charset=UTF-8`
   - Body: JSON metadata `{"name": "RecDrive_2026-09-24_11-45.mp4", "parents": ["<folderId>"]}`
   - Response: `200 OK` with header `Location: <resumable_upload_uri>`
2. **Chunked Upload Execution**:
   - Chunk size: 2,097,152 bytes (2 MB - exactly $8 \times 256$ KB as mandated by Google Drive API).
   - `PUT <resumable_upload_uri>`
   - Headers:
     - `Content-Length: <chunk_length>`
     - `Content-Range: bytes <start>-<end>/<total>`
   - Status code `308 Resume Incomplete`: advance chunk window.
   - Status code `200` or `201`: upload complete, parse returned file object ID, construct web link `https://drive.google.com/file/d/<fileId>/view`.
3. **Recovery & Disconnection Handling**:
   - If a chunk upload fails with network timeout or error:
     - Query upload status: `PUT <resumable_upload_uri>` with `Content-Range: bytes */<total>`.
     - Google responds `308 Resume Incomplete` with header `Range: bytes=0-<last_byte>`.
     - Next chunk begins at `<last_byte> + 1`.

---

### 3.3 OAuth 2.0 PKCE & Keychain Architecture

- Standard RFC 7636 PKCE:
  - Generate cryptographically secure `code_verifier` (64 random bytes, Base64URL-encoded).
  - Compute SHA256 digest: `code_challenge = Base64URLEncode(SHA256(code_verifier))`.
- Interactive Authorization:
  - Open user's default browser to `https://accounts.google.com/o/oauth2/v2/auth`.
  - Local loopback server (`http://127.0.0.1:port`) receives authorization code.
- Token Exchange:
  - Exchange authorization code + `code_verifier` for Access Token & Refresh Token.
  - Refresh Token stored in macOS Keychain via `SecItemAdd` / `SecItemUpdate` with service `com.recdrive.token`.
  - Access Token stored in memory with expiry cache; refreshed automatically prior to API requests.

---

### 3.4 Menu Bar UI & States

- `StatusItemController`:
  - **Idle**: Clean monochrome camera icon.
  - **Recording**: Pulsing red dot with dynamic recording timer.
  - **Uploading**: Rotating upload indicator / progress percentage in tooltip.
  - **Completed**: Brief green checkmark + system notification with action to open/copy link.
  - **Error**: Warning icon with alert popover.
- Menu Bar Popover:
  - Quick Recording Toggle (Start/Stop).
  - Source selector (Full Screen vs Window picker with preview).
  - Audio switches (System Audio on/off, Mic on/off + mic device selector).
  - Settings shortcut & Quit button.
- Preferences Window:
  - Google Account status (Logged in as user@domain / Connect button).
  - Drive destination folder picker (Folder ID or Root Drive).
  - Checkboxes:
    - [x] Auto-delete local file upon successful upload.
    - [x] Automatically copy Drive sharing link to clipboard.
    - [x] Launch at login (`SMAppService` on macOS 13+).
    - Codec choice: HEVC (Default) vs H.264.

---

## 4. Verification and Validation Criteria

1. **Build Validation**: Clean compilation via `swift build` and Xcode.
2. **Permission Check**: Clean prompting for Screen Recording (`CGPreflightScreenCaptureAccess`) and Microphone permissions.
3. **Capture Integrity**: Generated `.mp4` file playable in QuickTime Player with synchronized audio and video tracks.
4. **Drive Protocol**: Unit & integration test vectors for chunk calculations, `Content-Range` headers, and Keychain operations.
