# ScanCopy — iPhone barcode / QR scanner → Mac clipboard

Point your iPhone at any barcode or QR code. ScanCopy reads it, copies the text to the
clipboard, and (via Apple's Universal Clipboard) you can press **⌘V on your Mac** to paste it.

## 1. Run it on your iPhone (one-time setup)
1. Open `ScanCopy.xcodeproj` in Xcode (15 or newer).
2. Click the **ScanCopy** project → **ScanCopy** target → **Signing & Capabilities**.
3. Set **Team** to your Apple ID (Xcode ▸ Settings ▸ Accounts to add it; a free account works).
   If Xcode says the bundle ID is taken, change `com.akhilks.ScanCopy` to something unique.
4. Plug in your iPhone (or pair it over Wi-Fi), pick it as the run destination, press **⌘R**.
5. First time only, on the iPhone: Settings ▸ General ▸ VPN & Device Management → trust your
   developer certificate. Also enable **Developer Mode** if iOS asks (Settings ▸ Privacy & Security).

> Free Apple ID builds expire after 7 days — just press ⌘R again to reinstall. A paid developer
> account ($99/yr) makes them last a year.

## 2. Make the clipboard reach your Mac (Universal Clipboard)
- iPhone and Mac signed in to the **same Apple ID**.
- **Wi-Fi and Bluetooth ON** on both.
- **Handoff ON** on both:
  - iPhone: Settings ▸ General ▸ AirPlay & Continuity (or "AirPlay & Handoff") ▸ Handoff
  - Mac: System Settings ▸ General ▸ AirDrop & Handoff ▸ "Allow Handoff between this Mac and your iCloud devices"
- Devices near each other. Paste within ~2 minutes of scanning (Universal Clipboard expires).

## Using the app
- **QR Code / Barcode** (above the result card): switches between a square frame (QR) and a wide frame (barcodes).
  Only codes inside the frame are read, so nearby codes are ignored.
- **Scan**: put a code in the frame and it's copied straight away (you feel a vibration and the frame flashes green).
  Scanning never stops. Each new code is copied as soon as it enters the frame. The same code won't be
  copied twice while it stays in view. Move it out for ~2 s and back to copy it again.
- **Flashlight** (top-left) for dark places.
- **Settings** (gear, top-right): turn the scan **beep** and **vibration** on/off. The beep follows the silent switch.
- **History** (top-right): every scan is saved; tap one to copy it again, swipe to delete, long-press to share/open.
- If the code is a web link, an **Open** button appears.

Supported: QR, Micro QR, EAN-13, EAN-8, UPC-E, Code 128/39/93, ITF-14, Interleaved 2 of 5,
Codabar, PDF417, Aztec, Data Matrix, GS1 DataBar. (UPC-A codes are reported as EAN-13 with a leading 0.)

## Files
- `ScanCopy/ScannerView.swift` — camera + barcode detection (AVFoundation)
- `ScanCopy/ContentView.swift` — main screen, copy-to-clipboard logic
- `ScanCopy/HistoryView.swift` — scan history list
- `ScanCopy/ScanStore.swift` — saves history on the phone
- `ScanCopy/SettingsView.swift` — beep / vibration settings
- `ScanCopy/BeepPlayer.swift` — generates and plays the beep
