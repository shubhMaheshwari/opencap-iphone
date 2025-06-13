# Testing Plan

This document outlines how to test a local clone of the OpenCap iPhone app in single camera mode.

1. **Clone the repository**
   ```bash
   git clone https://github.com/shubhMaheshwari/opencap-iphone.git
   cd opencap-iphone
   ```
2. **Open the project**
   - Launch Xcode (version 14 or later recommended).
   - Open `OpenCap.xcodeproj`.
3. **Configure signing**
   - Select a development team in the project settings so the app can run on a device.
4. **Build and Run**
   - Connect an iPhone to your Mac.
   - Select the connected device as the run target.
   - Build and run the app via Xcode.
5. **Record a test video**
   - The app starts in single camera mode without needing calibration.
   - Use the action button to start a new session and record.
6. **Verify results**
   - Ensure the recording completes and uploads without errors.

