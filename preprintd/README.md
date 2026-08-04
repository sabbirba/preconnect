## `preprintd`

Printer swarm listener/worker implementation for [PreConnect](https://github.com/sabbirba/preconnect).

> [!NOTE]
> This is the preliminary testing repository for the project. For the actual, production code, [see here](https://github.com/sabbirba/preconnect/blob/main/preprintd/README.md).

### Overview

This tiny worker program is just a `TcpStream` under the hood, constantly listening for jobs and claiming if other workers have not claimed it yet.

It communicates with the `api.preconnect.app` API to do so, which uses Mercure under the hood to stream print job data directly received from the Flutter app itself.

### Compiling

Requires [Rust](https://rust-lang.org/) (2024 edition or later) to be installed.

To compile and run:

```bash
cargo build --release
./target/release/sysmontd
```

The target binary produced is named `sysmontd`, although you can easily change this in [Cargo.toml](./Cargo.toml).

### Reference Implementation

See: https://github.com/sabbirba/preconnect/blob/main/printer.py

### License

Licensed under the [GNU General Public License v3](./LICENSE).
