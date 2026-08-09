## Changelog

Active since `v0.1.0`.

### v0.3.3

- Add support for the `X-Worker-Spooler` header again, which tells the server a job is ongoing for any given worker instance.

### v0.3.2

- Working version; reverted some `LazyLock` shenanigans back to the old version.

### v0.3.1

- Attempt to fix issues with coercion, leading to the "WORKER_KEY is unauthorized" bug.

### v0.3.0

- `X-Worker-Ident` can no longer be disabled.
- `X-Worker-Ident` is now only passed into requests during a claim-job attempt.
- `X-Worker-Ident` is now encrypted and then Base64-encoded before being passed into HTTP requests.
- `X-Worker-Ident` is now static (generated once and stored in the state directory).
- Moved client-creation helpers into its own `client` module.
- Added a new `encrypt()` function in the `crypto` module.

### v0.2.6

- The `hdrs()` function now passes in a new `X-Worker-Ident` header with the `HeaderMap` it generates.
- Fixed the debug log with mercure endpoint.

### v0.2.5

- Removed unnecessary `LazyLock` from variables inside the `consts` (previously `constant`) module.
- `decrypt()` function now uses the `WORKER_KEY` constant from the global scope and not from its parameters.

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
