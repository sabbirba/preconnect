use anyhow::Result;
use base64::prelude::*;

pub fn decode_b64(val: &str) -> Result<String> {
    let x = BASE64_STANDARD.decode(val)?;
    Ok(String::from_utf8(x)?)
}

pub fn decode_field(opt: Option<&str>) -> Result<Option<Vec<u8>>> {
    match opt.map(str::trim) {
        Some(s) if !s.is_empty() => Ok(Some(BASE64_STANDARD.decode(s)?)),
        _ => Ok(None),
    }
}
