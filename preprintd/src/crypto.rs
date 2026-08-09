use anyhow::Result;
use base64::Engine;
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use base64::prelude::*;
use hmac::{Hmac, KeyInit, Mac};
use rand::Rng;
use sha2::{Digest, Sha256};

use crate::{WORKER_KEY, consts::BASE_DOMAIN_NOAPI};

type HmacSha256 = Hmac<Sha256>;

pub fn make_subscriber_jwt(worker_key: &str) -> String {
    let header = URL_SAFE_NO_PAD.encode(b"{\"alg\":\"HS256\",\"typ\":\"JWT\"}");
    let payload = URL_SAFE_NO_PAD.encode(
        format!(
            "{{\"mercure\":{{\"subscribe\":[\"https://{}/printer\"]}}}}",
            BASE_DOMAIN_NOAPI
        )
        .into_bytes(),
    );

    let sig_input = format!("{}.{}", header, payload);
    let mut mac = HmacSha256::new_from_slice(worker_key.as_bytes()).expect("HMAC init failed");
    mac.update(sig_input.as_bytes());

    let signature = URL_SAFE_NO_PAD.encode(mac.finalize().into_bytes());
    format!("{}.{}.{}", header, payload, signature)
}

pub fn decrypt(opt: Option<&str>, job_id: &str) -> Result<Vec<u8>> {
    let Some(value) = opt.map(str::trim).filter(|value| !value.is_empty()) else {
        return Ok(Vec::new());
    };

    let raw = BASE64_STANDARD.decode(value)?;

    if raw.len() < 16 {
        return Ok(Vec::new());
    }

    let (iv, encrypted) = raw.split_at(16);

    let mut seed = Sha256::new();
    seed.update(WORKER_KEY.as_bytes());
    seed.update(iv);
    seed.update(job_id.as_bytes());
    let p = seed.finalize();

    let mut output = Vec::with_capacity(encrypted.len());

    for (idx, chunk) in encrypted.chunks(32).enumerate() {
        let mut hasher = Sha256::new();
        hasher.update(p);
        hasher.update((idx as u32).to_be_bytes());
        let key_stream = hasher.finalize();

        output.extend(
            chunk
                .iter()
                .zip(key_stream.iter())
                .map(|(byte, key)| byte ^ key),
        );
    }

    Ok(output)
}

#[allow(dead_code)]
pub fn encrypt(plaintext: &str, job_id: &str) -> Result<String> {
    let mut iv = [0u8; 16];
    rand::rng().fill_bytes(&mut iv);

    let mut seed = Sha256::new();
    seed.update(WORKER_KEY.as_bytes());
    seed.update(&iv);
    seed.update(job_id.as_bytes());
    let p = seed.finalize();

    let mut encrypted = Vec::with_capacity(plaintext.len());
    for (idx, chunk) in plaintext.as_bytes().chunks(32).enumerate() {
        let mut hasher = Sha256::new();
        hasher.update(p);
        hasher.update((idx as u32).to_be_bytes());
        let key_stream = hasher.finalize();
        encrypted.extend(
            chunk
                .iter()
                .zip(key_stream.iter())
                .map(|(byte, key)| byte ^ key),
        );
    }

    let mut raw = Vec::with_capacity(16 + encrypted.len());
    raw.extend_from_slice(&iv);
    raw.extend_from_slice(&encrypted);

    Ok(BASE64_STANDARD.encode(raw))
}
