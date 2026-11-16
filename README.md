# NØAD — 3-in-1 iOS AdBlocker (Free Apple ID Ready)

**NØAD** is a Swift + JavaScript iOS adblocker built with **all 3 features working on a $0 Free Apple ID** (no paid VPN entitlement required, no subscription paywall, all rules bundled offline + OTA updates):

1. **NØAD Block — Safari Content Blocker (`NOADContentBlocker`)**
   - Pre-bundled offline with **57,506** Core rules (`default.json`), **3,732** Annoyances/Pop-up rules (`annoyances.json`), **2,773** Anti-Adblock rules (`anti-adblock.json`), **308** Cryptomining rules (`cryptomining.json`), **17** YouTube rules (`youtube.json`), and **13** Strict Mode rules (`strictmode-inactive.json`).
   - Supports Custom Blocklist & Allowlist domains and Over-the-Air rule updates.
2. **NØAD Web — Safari Web Extension (`NOADWebExtension`)**
   - Injects `inject-youtube.js` and `inject-youtube.css` into `*://*.youtube.com/*` in the `MAIN` world at `document_start`.
   - Strips `playerAds`, `adPlacements`, and `adSlots` from `ytInitialPlayerResponse`, `playerResponse`, and `fetch` calls to `player?key=`, and auto-skips any fallback video ad.
3. **NØAD System-Wide In-App Ad & Tracker Blocking (iOS Encrypted DNS)**
   - Works on a **Free Apple ID** without `com.apple.developer.networking.networkextension` by generating and installing an iOS `com.apple.dnsSettings.managed` Encrypted DNS (DoH) `.mobileconfig` profile (or applying `NEDNSSettingsManager`), with custom allowlist (`NeverConnect` domain evaluation rules) and Wi-Fi SSID exclusions.
   - Pre-built **NØAD** `.mobileconfig` profiles ([NOAD-AdGuard-AdBlock.mobileconfig](./NOAD-AdGuard-AdBlock.mobileconfig) and [NOAD-Mullvad-AdBlock.mobileconfig](./NOAD-Mullvad-AdBlock.mobileconfig)) are also ready in the root folder.

---

## How to Build the NØAD `.ipa` on Windows (No Mac Needed)

1. Create a new (private) GitHub repository and push this `NOAD` folder to it:
   ```powershell
   cd C:\Users\User\OneDrive\Documents\REA\NOAD
   git init
   git add .
   git commit -m "Initial NØAD 3-in-1 AdBlocker"
   git branch -M main
   git remote add origin https://github.com/<your-username>/NOAD.git
   git push -u origin main
   ```
2. On GitHub, open the **Actions** tab → **Build NØAD IPA (Free Apple ID Ready)**.
3. Once it finishes (~2 minutes on GitHub's free `macos-15` runner), download the **`NOAD-IPA`** artifact, which contains **`NOAD-unsigned.ipa`**.
4. Sideload **`NOAD-unsigned.ipa`** onto your iPhone with **Sideloadly**, **AltStore**, or **SideStore** using your Free Apple ID.
   - *(Note: A Free Apple ID allows up to **3 active App IDs** at a time. Because this `.ipa` contains the Main App (`com.noad.app`) + Content Blocker Extension (`com.noad.app.ContentBlocker`) + Web Extension (`com.noad.app.WebExtension`) = **3 App IDs**, make sure you don't have other sideloaded apps taking up your 3-slot limit).*
5. On your iPhone:
   - Open **Settings → Apps → Safari → Extensions** and turn on **NØAD Block** and **NØAD Web**.
   - Open **NØAD** and tap **Install NØAD Encrypted DNS Profile (Free Apple ID)** (or AirDrop [NOAD-AdGuard-AdBlock.mobileconfig](./NOAD-AdGuard-AdBlock.mobileconfig) to your iPhone), then enable it in **Settings → General → VPN & Device Management → DNS**.
