use std::sync::LazyLock;

pub const BASE_DOMAIN: &str = "api.preconnect.app";
pub const BASE_DOMAIN_NOAPI: &str = "preconnect.app";
pub static BASE_URL: LazyLock<String> = LazyLock::new(|| format!("https://{}", BASE_DOMAIN));
