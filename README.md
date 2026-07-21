# SMS2

SMS2 is a focused KDE desktop client for reading and sending phone messages through KDE Connect. The application is written in Rust, with a Qt 6 and Kirigami interface connected through CXX-Qt.

## Features

- Discovers reachable, paired KDE Connect devices with SMS support
- Loads and searches conversation threads
- Displays recent messages and image thumbnails
- Sends replies and starts conversations with one or more recipients
- Sends file attachments through the paired phone
- Adapts between split-pane and compact navigation
- Reports disconnected, loading, empty, and error states

SMS2 communicates only with the local `kdeconnectd` session service over D-Bus. KDE Connect remains responsible for phone pairing, transport, and message delivery.

## Requirements

- A phone paired with KDE Connect
- The SMS plugin enabled for that phone
- Rust 1.85 or later
- Qt 6, Qt Declarative, Kirigami, Kirigami Addons, and QQC2 Desktop Style
- CMake 3.28 or later and Extra CMake Modules

The included Nix flake supplies the development dependencies.

## Development

Enter the development shell and run the application:

```sh
nix develop
cargo run
```

Run the Rust tests:

```sh
nix develop --command cargo test
```

The first synchronization can take a moment while KDE Connect requests conversation data from the phone. SMS2 requests the 100 most recent messages when a thread is opened and refreshes the open thread periodically.

## Installation

Build and install with CMake from inside the development shell:

```sh
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$HOME/.local"
cmake --build build
cmake --install build
```

Choose a different `CMAKE_INSTALL_PREFIX` when packaging or installing system-wide.

## Architecture

- `src/kdeconnect.rs` implements the typed asynchronous D-Bus client.
- `src/controller.rs` owns the background Tokio runtime and exposes observable state to QML.
- `src/model.rs` contains wire, domain, and UI serialization types.
- `src/qml/` contains the Kirigami interface.
- `build.rs` embeds the QML module and generates the CXX-Qt bridge.

## Privacy

Message content and attachment thumbnails are held in application memory for display. SMS2 does not persist conversations or send telemetry. Sending a message or attachment forwards it to the selected phone through KDE Connect.

## License

GPL-3.0-or-later
