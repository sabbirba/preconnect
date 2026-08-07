## Changelog

Active since `v0.1.0`.

### v0.2.4

- Enhanced real-time stream handling and logging.
- Detached `AGENT`, `DEF_HOST` and `DEF_QUEUE` from source and used `LazyLock` instances like `WORKER_KEY` to pull them from the environment during runtime instead.

### v0.2.3

(experimental release; no changelog provided during the time of testing)

### v0.2.2

- Changed the `stream()` function so that the `handle()` call is moved to a separate thread.

### v0.2.1

- Removed `X-Worker-Spooler` implementation from the `hdrs()` function.
- Changed signatures of the `hdrs()` and `claim_job()` functions following the change above.

### v0.2.0

- Complete feature parity referencing the Python implementation.

### v0.1.4

- Better `debug_log!()` placement across the codebase.

### v0.1.3

- Experimental changes to socket (more `Option<String>` fields in `crate::types::Job`).

### v0.1.2

- Change write/recv sequence (experimental).

### v0.1.1

- Add support for the `--debug` flag.

### v0.1.0

- Initial launch.
