## `preprintd`

Printer swarm-worker daemon implementation for [PreConnect](https://github.com/sabbirba/preconnect).

### Overview

This tiny worker is just a `TcpStream` under the hood, constantly listening for jobs and claiming one if open. It works by constantly listening for incoming data from the `api.preconnect.app` endpoint (which uses [Mercure](https://mercure.rocks) under the hood for streaming real-time data), and then initiating the claiming procedure.

### Compiling

Requires [Rust](https://rust-lang.org/) (2024 edition or later) to be installed.

To compile and run:

```bash
cargo build --release
./target/release/preprintd --key WORKERKEYHERE
```

> [!NOTE]
> The release binary is optimized for the smallest-possible size, although you can change this behavior by disabling the optimizations specified in the `[profile.release]` section of [Cargo.toml](./Cargo.toml).

For running the binary in debug mode, use the `--debug` flag:

```bash
cargo run -- --debug --key WORKERKEYHERE
```

### Prebuilt Binaries

See the [GitHub Releases](https://github.com/hitblast/preprintd/releases) for a prebuilt binary for either Windows, Linux (built via CI workers running Ubuntu), or macOS.

### Code Inspection

When you're going through the code, you'll see these:

- Some `decode_b64()` calls - those are primarily for obfuscation needs but since the inner value is Base64-encoded, you can easily use a decoder to decouple the values underneath. One such tool that you can use is [this](https://www.base64decode.org).
- The standard LPR/LPD sequence (except the code doing HTTP requests via [reqwest's](https://github.com/seanmonstar/reqwest) blocking API and every other code surrounding/using this logic).

### Reference Implementation

See: https://github.com/sabbirba/preconnect/blob/main/printer.py (courtesy: [@sabbirba](https://github.com/sabbirba))

### License

Licensed under the [GNU General Public License v3](./LICENSE).

```

```
