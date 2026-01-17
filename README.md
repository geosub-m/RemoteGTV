# RemoteGTV 📺

<p align="center">
  <img src="AppIcon.png" width="128" height="128" alt="RemoteGTV Icon">
</p>

**RemoteGTV** is a native macOS application designed to control **Android TV** and **Google TV** devices directly from your desktop. It provides a lightweight, responsive, and aesthetically pleasing interface to navigate your TV without needing to reach for the physical remote or your phone.

Built with **SwiftUI** and native system frameworks, it ensures high performance and seamlessly blends with the macOS ecosystem.

---

## ✨ Features

*   **Native macOS Experience**: Designed with modern SwiftUI components for a look and feel that belongs on your Mac.
*   **Auto-Discovery**: Automatically finds Android TV / Google TV devices on your local network using Bonjour (mDNS) / Network Service Discovery.
*   **Secure Pairing**: Implements the official Android TV pairing protocol using TLS certificates for a secure and authenticated connection.
*   **Full Remote Control**: Supports standard navigation keys (D-Pad), Back, Home, Volume control, Mute, and Power.
*   **Keyboard Support**: (Planned) Type on your Mac keyboard to input text on the TV.
*   **Instant Connection**: Remembers previously paired devices for quick reconnection.

## 🛠 Technology Stack

This project is built using:

*   **Language**: [Swift 5.9+](https://swift.org/)
*   **UI Framework**: [SwiftUI](https://developer.apple.com/xcode/swiftui/)
*   **Networking**: `Network.framework` (NWConnection) for raw TCP/TLS socket communication.
*   **Protocol**: Custom implementation of the **Android TV Remote Protocol v2**.
    *   Uses **Protocol Buffers** (Protobuf) for message serialization.
    *   Implements a lightweight, dependency-free Protobuf encoder/decoder (`ProtocolBuffer.swift`).
*   **Security**: Native `Security` framework for generating self-signed RSA certificates required for the pairing handshake.

## 🚀 How to Build & Install

### Prerequisites
*   macOS 13.0 (Ventura) or later.
*   Xcode 15+ (for Swift compiler tools) or just the Command Line Tools.

### Building from Source

There is no need to open Xcode for a quick build. The project includes a shell script to compile and bundle the app automatically.

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/geosub-m/RemoteGTV.git
    cd RemoteGTV
    ```

2.  **Run the build script:**
    ```bash
    ./build_app.sh
    ```
    This script will:
    *   Compile all Swift sources.
    *   Generate the `RemoteGTV.app` bundle.
    *   Create the application icon.
    *   Sign the application (ad-hoc).

3.  **Run the App:**
    The application will be created in the project folder as `RemoteGTV.app`. You can double-click it or move it to your `/Applications` folder.

## 🎮 How to Use

1.  Ensure your **Mac** and **Android TV** are connected to the **same Wi-Fi network**.
2.  Launch **RemoteGTV**.
3.  The app will scan for devices. Click **"Connect"** (or enter the IP manually if needed).
4.  **First Time Pairing**:
    *   A alphanumeric code will appear on your TV screen.
    *   Enter this code into the prompt in the RemoteGTV app.
5.  Once paired, the interface will change to the remote view. You can now control your TV!

## 📂 Project Structure

*   `RemoteTVApp.swift`: The entry point of the SwiftUI application.
*   `ContentView.swift`: The main user interface implementation.
*   `NetworkManager.swift`: Handles TCP/TLS connections, handshake logic, and data transmission.
*   `RemoteProtocol.swift`: Defines the specific command structures and pairing logic for Android TV.
*   `ProtocolBuffer.swift`: A custom, lightweight Swift implementation for encoding/decoding Protobuf messages without external dependencies.
*   `CertUtils.swift`: Utilities for generating the SSL certificates required for authentication.
*   `RemoteMote.proto`: (Reference) The standard Protobuf definitions used by the protocol.

## 🤝 Contributing

Contributions are welcome! If you find a bug or want to suggest a new feature (like Voice Search or App launching), feel free to open an issue or submit a pull request.

## 📄 License

This project is open-source. Feel free to use and modify it.

---
*Disclaimer: "Android TV" and "Google TV" are trademarks of Google LLC. This project is an unofficial client and is not affiliated with Google.*
