# RecDrive Implementation Plan

> **For Antigravity:** REQUIRED WORKFLOW: Use `.agent/workflows/execute-plan.md` to execute this plan in single-flow mode.

**Goal:** Build "RecDrive", a native ultra-lightweight macOS menu bar application (macOS 13+) for hardware-accelerated screen & audio capture via ScreenCaptureKit and AVAssetWriter, with seamless resumable upload to Google Drive.

**Architecture:** Pure native Swift without heavy dependencies; modular separation into `Capture/`, `Drive/`, `Storage/`, `UI/`, and `App/`. Uses ScreenCaptureKit and VideoToolbox for zero-overhead NV12 hardware encoding, OAuth 2.0 PKCE with Keychain persistence, and chunked background Google Drive REST API v3 resumable uploads.

**Tech Stack:** Swift 5.9 / 6.0, SwiftUI, AppKit (`NSStatusItem`), ScreenCaptureKit, AVFoundation (`AVAssetWriter`, `AVAudioEngine`), Security framework (macOS Keychain), URLSession.

---

### Task 1: Package Configuration & Scaffolding
**Files:**
- Create: `Package.swift`
- Create: `Resources/Info.plist`
- Create: `Resources/RecDrive.entitlements`

**Step 1: Define Package.swift and project structure**
Setup Swift Package targeting macOS 13.0+ with an executable target `RecDrive`.

**Step 2: Create Info.plist and entitlements**
Add `LSUIElement = true`, `NSScreenCaptureUsageDescription`, `NSMicrophoneUsageDescription`.

**Step 3: Verify SwiftPM initialization**
Run `swift package dump-package` to confirm package syntax and integrity.

**Step 4: Commit**
Commit Task 1 changes.

---

### Task 2: Storage & Security Subsystem
**Files:**
- Create: `Sources/RecDrive/Storage/KeychainHelper.swift`
- Create: `Sources/RecDrive/Storage/PreferencesStorage.swift`
- Create: `Sources/RecDrive/Storage/LocalStorageManager.swift`

**Step 1: Implement KeychainHelper**
Safe wrapper for macOS Keychain Services API (`SecItemAdd`, `SecItemCopyMatching`, `SecItemDelete`) targeting service `com.recdrive.tokens`.

**Step 2: Implement PreferencesStorage**
App preferences wrapper around `UserDefaults`: `autoDeleteAfterUpload`, `copyLinkToClipboard`, `selectedFolderId`, `videoCodec`, `targetFPS`.

**Step 3: Implement LocalStorageManager**
Manager for temporary video storage in `~/Movies/RecDrive/`, generating unique timestamps and cleanup utilities.

**Step 4: Verify build**
Run compilation test to verify storage modules.

**Step 5: Commit**
Commit Task 2 changes.

---

### Task 3: Google Drive OAuth 2.0 PKCE & Models
**Files:**
- Create: `Sources/RecDrive/Drive/AuthConfig.swift`
- Create: `Sources/RecDrive/Drive/DriveModels.swift`
- Create: `Sources/RecDrive/Drive/OAuthManager.swift`

**Step 1: Implement AuthConfig and DriveModels**
Define OAuth endpoints, scopes (`https://www.googleapis.com/auth/drive.file`), and Decodable models for tokens, Drive files, and folders.

**Step 2: Implement OAuthManager with PKCE**
Cryptographic generation of `code_verifier` (RFC 7636) and SHA256 `code_challenge`. Ephemeral local HTTP server (`NWListener` / loopback socket) to capture redirect authorization code. Token exchange and refresh methods.

**Step 3: Verify build**
Verify compilation of OAuth & models.

**Step 4: Commit**
Commit Task 3 changes.

---

### Task 4: Google Drive Resumable Upload Engine
**Files:**
- Create: `Sources/RecDrive/Drive/DriveService.swift`

**Step 1: Implement DriveService Resumable Engine**
- `startResumableSession(fileURL:metadata:)` -> returns Upload URL from Google API.
- `uploadFileChunked(uploadURL:fileURL:progressHandler:)` -> executes 2MB chunk uploads with `Content-Range: bytes START-END/TOTAL`.
- `queryUploadStatus(uploadURL:fileSize:)` -> handles disconnection recovery via `308 Resume Incomplete` range checks.
- `fetchFolders(parentID:)` -> lists accessible Google Drive folders.

**Step 2: Verify build**
Verify compilation of `DriveService`.

**Step 3: Commit**
Commit Task 4 changes.

---

### Task 5: ScreenCaptureKit Video & Audio Capture Engine
**Files:**
- Create: `Sources/RecDrive/Capture/CaptureModels.swift`
- Create: `Sources/RecDrive/Capture/MicrophoneEngine.swift`
- Create: `Sources/RecDrive/Capture/ScreenCaptureManager.swift`

**Step 1: Implement CaptureModels**
Define `CaptureSource` (Display vs Window), `AudioSourceConfig`, and recording metrics.

**Step 2: Implement MicrophoneEngine**
`AVAudioEngine` pipeline for streaming external microphone buffers synchronously to `MediaWriter`.

**Step 3: Implement ScreenCaptureManager**
- Query shareable content (`SCShareableContent`).
- Configure `SCStream` for display or individual window.
- Implement `SCStreamOutput` and `SCStreamDelegate` callbacks for video frames and system audio.

**Step 4: Verify build**
Verify compilation of ScreenCapture modules.

**Step 5: Commit**
Commit Task 5 changes.

---

### Task 6: Hardware-Accelerated Media Writer
**Files:**
- Create: `Sources/RecDrive/Capture/MediaWriter.swift`

**Step 1: Implement MediaWriter with AVAssetWriter**
- Setup `AVAssetWriterInput` for video with `AVVideoCodecType.hevc` / `h264`, native dimensions, bitrate control, hardware acceleration.
- Setup `AVAssetWriterInput` for system audio and microphone audio (AAC 48kHz).
- Coordinate session start time on first valid video sample.
- Non-blocking asynchronous sample buffer writing on dedicated queues.
- Clean finalization on `stopWriting()` returning completed file URL.

**Step 2: Verify build**
Verify compilation of `MediaWriter`.

**Step 3: Commit**
Commit Task 6 changes.

---

### Task 7: UI & Menu Bar Integration
**Files:**
- Create: `Sources/RecDrive/App/AppState.swift`
- Create: `Sources/RecDrive/UI/StatusItemController.swift`
- Create: `Sources/RecDrive/UI/MenuBarView.swift`
- Create: `Sources/RecDrive/UI/SourcePickerView.swift`
- Create: `Sources/RecDrive/UI/SettingsView.swift`
- Create: `Sources/RecDrive/App/RecDriveApp.swift`

**Step 1: Implement AppState**
Main coordinator connecting `ScreenCaptureManager`, `MediaWriter`, `DriveService`, and `OAuthManager`.

**Step 2: Implement StatusItemController**
AppKit menu bar item managing dynamic states: Idle, Recording (pulsing indicator), Uploading (spinner/progress), Completed.

**Step 3: Implement SwiftUI Views**
- `MenuBarView`: Quick controls, source selection, recording timer, audio toggles.
- `SourcePickerView`: Visual picker for screen vs individual app windows.
- `SettingsView`: Google account authentication, drive destination folder, toggles.

**Step 4: Implement RecDriveApp**
Application entry point configuring `NSApplication`, menu bar extra, and permission handshakes.

**Step 5: Verify build**
Verify compilation of the complete application.

**Step 6: Commit**
Commit Task 7 changes.

---

### Task 8: Xcode Project Integration & Build Documentation
**Files:**
- Create: `scripts/generate_xcode_project.sh`
- Create: `README.md`

**Step 1: Provide build scripts and Xcode generator instructions**
Setup script for compiling via Swift CLI and generating/opening Xcode project.

**Step 2: End-to-end compilation & verification**
Run build commands, verify zero warnings/errors, and test binary structure.

**Step 3: Final Commit & Summary**
Commit all files, update task tracking table, and present deliverables.
