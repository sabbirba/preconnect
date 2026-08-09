use std::{
    net::SocketAddr,
    sync::{LazyLock, Mutex},
    time::{Duration, Instant},
};

use reqwest::blocking::Client;

use crate::{consts::BASE_DOMAIN, doh::resolve_doh};

static CLIENT: LazyLock<Mutex<(Client, Instant)>> =
    LazyLock::new(|| Mutex::new((build_client(), Instant::now())));

fn build_client() -> Client {
    let mut builder = Client::builder()
        .tcp_nodelay(true)
        .tcp_keepalive(Duration::from_secs(15));

    if let Some(ip) = resolve_doh(BASE_DOMAIN) {
        builder = builder.resolve(BASE_DOMAIN, SocketAddr::new(ip, 443));
    }

    builder.build().expect("failed to build HTTP client")
}

pub fn client() -> Client {
    let mut state = CLIENT.lock().expect("HTTP client lock poisoned");

    if state.1.elapsed() >= Duration::from_secs(300) {
        *state = (build_client(), Instant::now());
    }

    state.0.clone()
}
