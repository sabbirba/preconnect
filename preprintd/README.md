## `preprintd`

Printer swarm-worker daemon implementation for [PreConnect](https://github.com/sabbirba/preconnect).

### Overview

This tiny worker is just a `TcpStream` under the hood, constantly listening for jobs and claiming one if open. It works by constantly listening for incoming data from the `api.preconnect.app` endpoint (which uses [Mercure](https://mercure.rocks) under the hood for streaming real-time data), and then initiating the claiming procedure.

### Compiling

Requires [Rust](https://rust-lang.org/) (2024 edition or later) to be installed.

To compile and run:

```bash
cargo build --release
WORKER_KEY=yourworkerkeyhere ./target/release/preprintd
```

> [!NOTE]
> The release binary is optimized for the smallest-possible size, although you can change this behavior by disabling the optimizations specified in the `[profile.release]` section of [Cargo.toml](./Cargo.toml).

For running the binary in debug mode, use the `--debug` flag:

```bash
WORKER_KEY=yourworkerkeyhere cargo run -- --debug
```

> The `WORKER_KEY` can be set just like a regular environment variable. A good option for this is [direnv](https://github.com/direnv/direnv) to set `WORKER_KEY` on the current directory using the `.envrc` file.

### Prebuilt Binaries

See the [GitHub Releases](https://github.com/hitblast/preprintd/releases) for a prebuilt binary for either Windows, Linux (built via CI workers running Ubuntu), or macOS.

### Daemon Usage

Create a new `systemd` service which you can enable later:

```bash
sudo nano /etc/systemd/system/preprintd.service
```

Write the following INI configuration in your `preprintd.service` file. Make sure to replace the following things as well:

1. `yourworkerkeyhere` -> Replace with your worker key credential.
2. `username` -> Replace with the current logged-in user.
3. `/usr/bin/preprintd` -> Replace with the correct execution path based on where you've put your binary.

```ini
[Unit]
Description=PreConnect Printer Worker Daemon
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/preprintd --debug
Restart=always
Environment="WORKER_KEY=yourworkerkeyhere"
User=username

[Install]
WantedBy=multi-user.target
```

Enable and start it once you're done:

```bash
sudo systemctl daemon-reload
sudo systemctl enable preprintd.service
sudo systemctl start preprintd.service

# now check status:
systemctl status preprintd.service
```

To check the logs in real-time, run:

```bash
journalctl -u preprintd.service -f
```

### Code Inspection

When you're going through the code, you'll see these:

- Some `decode_b64_string()` calls - those are primarily for obfuscation needs but since the inner value is Base64-encoded, you can easily use a decoder to decouple the values underneath. One such tool that you can use is [this](https://www.base64decode.org).
- The standard LPR/LPD sequence (except the code doing HTTP requests via [reqwest's](https://github.com/seanmonstar/reqwest) blocking API and every other code surrounding/using this logic).
- LOTS of `LazyLock` usage. ALthough this is not optimal for a program that's supposed to be tiny, we've kept this pattern to reuse as much data as physically possible without hardcoding and messing up.

#### Mercure SSE Connection Protocol

`preprintd` streams real-time job notifications from the Mercure Hub (`/.well-known/mercure`).

1. **Endpoint**: `https://api.preconnect.app/.well-known/mercure?topic=https%3A%2F%2Fpreconnect.app%2Fprinter`
2. **Authorization**: `Bearer <subscriber-jwt>`
   - The subscriber JWT is created by signing `{"mercure":{"subscribe":["https://preconnect.app/printer"]}}` with HMAC-SHA256 using `WORKER_KEY`.
3. **Replay Support**: On reconnect, pass the `Last-Event-ID` header containing the last `id: ` value received from the stream to receive any missed jobs.

### Reference Implementation

See: https://github.com/sabbirba/preconnect/blob/main/printer.py (courtesy: [@sabbirba](https://github.com/sabbirba))

### License

Licensed under the [GNU General Public License v3](./LICENSE).
