macro_rules! debug_log {
    ($l:expr, $($arg:tt)*) => {
        if *DEBUG {
            eprintln!(
                "[{}] {}",
                match $l {
                    LogLevel::Ok => "OK",
                    LogLevel::Error => "ERR",
                    LogLevel::Warn => "WARNING"
                },
                format_args!($($arg)*)
            );
        }
    };
}

macro_rules! sock {
    ($x:ident, $h:ident, $p:ident, $t:expr) => {
        let $x = (|| -> std::io::Result<TcpStream> {
            let addrs = ($h, $p).to_socket_addrs()?;
            let mut last_error = None;

            for addr in addrs {
                match TcpStream::connect_timeout(&addr, $t) {
                    Ok(socket) => return Ok(socket),
                    Err(error) => last_error = Some(error),
                }
            }

            Err(last_error.unwrap_or_else(|| {
                std::io::Error::new(
                    std::io::ErrorKind::AddrNotAvailable,
                    "no socket addresses resolved",
                )
            }))
        })();
    };
}
