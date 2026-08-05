use std::{
    collections::HashMap,
    net::IpAddr,
    sync::{LazyLock, Mutex},
    time::{Duration, Instant},
};

use reqwest::{StatusCode, blocking::Client};
use serde_json::Value;

static DOH_CLIENT: LazyLock<Client> = LazyLock::new(|| {
    Client::builder()
        .timeout(Duration::from_millis(1500))
        .build()
        .expect("failed to build DoH client")
});

static DOH_CACHE: LazyLock<Mutex<HashMap<String, (IpAddr, Instant)>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));

pub fn resolve_doh(domain: &str) -> Option<IpAddr> {
    let now = Instant::now();

    if let Ok(cache) = DOH_CACHE.lock()
        && let Some((ip, stored_at)) = cache.get(domain)
        && now.duration_since(*stored_at) < Duration::from_secs(300)
    {
        return Some(*ip);
    }

    for resolver in ["https://1.1.1.1/dns-query", "https://8.8.8.8/dns-query"] {
        let response = DOH_CLIENT
            .get(format!("{resolver}?name={domain}&type=A"))
            .header("Accept", "application/dns-json")
            .send();

        let Ok(response) = response else {
            continue;
        };
        if response.status() != StatusCode::OK {
            continue;
        }
        let Ok(data) = response.json::<Value>() else {
            continue;
        };
        let Some(answers) = data.get("Answer").and_then(Value::as_array) else {
            continue;
        };

        for answer in answers {
            if answer.get("type").and_then(Value::as_u64) != Some(1) {
                continue;
            }

            let Some(ip) = answer
                .get("data")
                .and_then(Value::as_str)
                .and_then(|value| value.parse::<IpAddr>().ok())
            else {
                continue;
            };

            if let Ok(mut cache) = DOH_CACHE.lock() {
                cache.insert(domain.to_owned(), (ip, now));
            }

            return Some(ip);
        }
    }

    None
}
