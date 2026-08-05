use anyhow::Result;
use base64::prelude::*;
use sha2::{Digest, Sha256};

pub fn decode_b64_string(val: &str) -> Result<String> {
    let x = BASE64_STANDARD.decode(val)?;
    Ok(String::from_utf8(x)?)
}

pub fn decrypt(opt: Option<&str>, worker_key: &str, job_id: &str) -> Result<Vec<u8>> {
    let Some(value) = opt.map(str::trim).filter(|value| !value.is_empty()) else {
        return Ok(Vec::new());
    };

    let raw = BASE64_STANDARD.decode(value)?;

    if raw.len() < 16 {
        return Ok(Vec::new());
    }

    let (iv, encrypted) = raw.split_at(16);

    let mut seed = Sha256::new();
    seed.update(worker_key.as_bytes());
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
