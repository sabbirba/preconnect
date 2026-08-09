#[cfg(target_os = "linux")]
use zbus::blocking::Connection;
#[cfg(target_os = "linux")]
use zbus::zvariant::OwnedFd;

#[cfg(target_os = "linux")]
use crate::ALIAS;

#[cfg(target_os = "linux")]
pub fn acquire_sleep_inhibitor() -> zbus::Result<OwnedFd> {
    let connection = Connection::system()?;

    let proxy = zbus::blocking::Proxy::new(
        &connection,
        "org.freedesktop.login1",
        "/org/freedesktop/login1",
        "org.freedesktop.login1.Manager",
    )?;

    let fd: OwnedFd = proxy.call(
        "Inhibit",
        &(
            "sleep",
            ALIAS.as_str(),
            "Required for sustained streaming operation.",
            "block",
        ),
    )?;

    Ok(fd)
}
