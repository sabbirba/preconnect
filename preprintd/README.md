## `preprintd`

Printer swarm-worker daemon implementation for [PreConnect](https://github.com/sabbirba/preconnect).

[(Codeberg Mirror)](https://codeberg.org/hitblast/preprintd)

### Overview

This tiny worker is just a `TcpStream` under the hood, constantly listening for jobs and claiming one if open. It works by constantly listening for incoming data from the `api.preconnect.app` endpoint (which uses [Mercure](https://mercure.rocks) under the hood for streaming real-time data), and then initiating the claiming procedure.

### Compiling

Requires [Rust](https://rust-lang.org/) (2024 edition or later) to be installed.

Run the traditional release command:

```bash
cargo build --release
```

You can also directly install the `preprintd` binary globally using [cargo](https://github.com/rust-lang/cargo):

```bash
cargo install preprintd
```

> [!NOTE]
> The release binary is optimized for the smallest-possible size, although you can change this behavior by disabling the optimizations specified in the `[profile.release]` section of [Cargo.toml](./Cargo.toml).

### Prebuilt Binaries

See the [GitHub Releases](https://github.com/hitblast/preprintd/releases) for a prebuilt binary for either Windows, Linux (built via CI workers running Ubuntu), or macOS.

### Daemon Usage

Create a new `systemd` service which you can enable later:

```bash
sudo nano /etc/systemd/system/preprintd.service
```

Write [this INI configuration](./preprintd.service) in your `preprintd.service` file. Make sure to replace the following fields/values:

1. Under `Environment=`:

- `WORKER_KEY`: Your worker key credential (from the PreConnect API).
- `DEF_HOST`: The default printer host to use in case the API cannot provide one.
- `DEF_QUEUE`: The default queue name to send printable data to.
- (Optional) `ALIAS`: The name which determines the program's identity on the system and in TCP requests.

2. Replace `/usr/bin/preprintd` with the appropriate path to the daemon binary.

> [!WARNING]
> Since `preprintd` does not require access to user-specific paths, the `User` field under `[Service]` could be virtually any value depending on your environment.

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

#### Inhibitor Locks (Linux-only)

You may pass in the `--inhibit` flag with the execution command in order to acquire an inhibitor file descriptor (or FD) for the lifetime of the program. This will prevent your Linux machine from sleeping (since sleeping disrupts the TCP connections that happen when running `preprintd`) and keep the program stable.

### Code Inspection

When you're going through the code, you'll see these:

- The standard LPR/LPD sequence (except the code doing HTTP requests via [reqwest's](https://github.com/seanmonstar/reqwest) blocking API and every other code surrounding/using this logic).
- Lots of `LazyLock` usage. Although this is not optimal for a program that's supposed to be tiny, we've kept this pattern to reuse as much data as physically possible without hardcoding and messing up.

More specific parts of the codebase that you may be more curious about are described below:

#### Mercure SSE Connection Protocol

`preprintd` streams real-time job notifications from the Mercure Hub (`/.well-known/mercure`).

1. **Endpoint**: `https://api.preconnect.app/.well-known/mercure?topic=https%3A%2F%2Fpreconnect.app%2Fprinter`
2. **Authorization**: `Bearer <subscriber-jwt>`
   - The subscriber JWT is created by signing `{"mercure":{"subscribe":["https://preconnect.app/printer"]}}` with HMAC-SHA256 using `WORKER_KEY`.
3. **Replay Support**: On reconnect, pass the `Last-Event-ID` header containing the last `id: ` value received from the stream to receive any missed jobs.

#### Windows Inconsistencies

Although most of the instructions above are primarily made for Linux (and can be migrated over to Unix/macOS), some built-in features are not available on the Windows operating system by default. For example, the `STATE_DIRECTORY` environment variable set via `systemd` during runtime never shows up there. Moreover, some Windows-specific features might be missing from this implementation entirely, for which it is encouraged that you give the [Reference Implementation](#reference-implementation) a try.

#### Identifying Workers

While claiming a job, each worker identifies itself with an `X-Worker-Ident` header which has a pattern of `<UUID>_<ARCH>` (e.g. `03780793-e7af-49c1-b55d-92ff57be8c6e_aarch64-apple-darwin`).

When split at an underscore (`_`), the latter part indicates the architecture _of the compiled binary_. The first part is the UUID, which is generated once and kept static for the daemon's entire lifecycle on Unix/Linux if the state directory is set properly within the daemon's service file. However, on Windows, or in environments where the state directory is unset (as partially mentioned in [Windows Inconsistencies](#windows-inconsistencies)), the worker identity is dynamic, meaning that the identity would be reset for each new session. You can easily overcome this by just setting `STATE_DIRECTORY` to a valid absolute path on your system.

### Reference Implementation

See: https://github.com/sabbirba/preconnect/blob/main/printer.py (courtesy: [@sabbirba](https://github.com/sabbirba))

### License

Licensed under the [GNU General Public License v3](./LICENSE).
