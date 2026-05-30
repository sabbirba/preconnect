use std::ffi::{c_char, CString};

#[no_mangle]
pub extern "C" fn preconnect_native_backend_name() -> *mut c_char {
    CString::new("preconnect-native-rust")
        .expect("static backend name must not contain null bytes")
        .into_raw()
}

#[no_mangle]
pub unsafe extern "C" fn preconnect_native_free_string(value: *mut c_char) {
    if value.is_null() {
        return;
    }
    let _ = CString::from_raw(value);
}

#[no_mangle]
pub unsafe extern "C" fn preconnect_native_validate_json(json_str: *const c_char) -> i32 {
    if json_str.is_null() {
        return 0;
    }
    let c_str = std::ffi::CStr::from_ptr(json_str);
    let str_slice = match c_str.to_str() {
        Ok(s) => s,
        Err(_) => return 0,
    };
    let value: Result<serde_json::Value, _> = serde_json::from_str(str_slice);
    if value.is_ok() {
        1
    } else {
        0
    }
}

use aes_gcm::{
    aead::{Aead, KeyInit},
    Aes256Gcm, Nonce, Key
};
use rand::RngCore;

#[no_mangle]
pub unsafe extern "C" fn preconnect_native_encrypt(
    key_ptr: *const u8,
    data_ptr: *const u8,
    data_len: i32,
    out_len: *mut i32,
) -> *mut u8 {
    if key_ptr.is_null() || data_ptr.is_null() || data_len <= 0 || out_len.is_null() {
        return std::ptr::null_mut();
    }
    let key_slice = std::slice::from_raw_parts(key_ptr, 32);
    let data_slice = std::slice::from_raw_parts(data_ptr, data_len as usize);

    let key = Key::<Aes256Gcm>::from_slice(key_slice);
    let cipher = Aes256Gcm::new(key);

    let mut nonce_bytes = [0u8; 12];
    rand::thread_rng().fill_bytes(&mut nonce_bytes);
    let nonce = Nonce::from_slice(&nonce_bytes);

    let ciphertext = match cipher.encrypt(nonce, data_slice) {
        Ok(c) => c,
        Err(_) => return std::ptr::null_mut(),
    };

    let mut result = Vec::with_capacity(12 + ciphertext.len());
    result.extend_from_slice(&nonce_bytes);
    result.extend_from_slice(&ciphertext);

    *out_len = result.len() as i32;
    let ptr = result.as_mut_ptr();
    std::mem::forget(result);
    ptr
}

#[no_mangle]
pub unsafe extern "C" fn preconnect_native_decrypt(
    key_ptr: *const u8,
    data_ptr: *const u8,
    data_len: i32,
    out_len: *mut i32,
) -> *mut u8 {
    if key_ptr.is_null() || data_ptr.is_null() || data_len <= 12 || out_len.is_null() {
        return std::ptr::null_mut();
    }
    let key_slice = std::slice::from_raw_parts(key_ptr, 32);
    let data_slice = std::slice::from_raw_parts(data_ptr, data_len as usize);

    let key = Key::<Aes256Gcm>::from_slice(key_slice);
    let cipher = Aes256Gcm::new(key);

    let nonce = Nonce::from_slice(&data_slice[..12]);
    let ciphertext = &data_slice[12..];

    let mut plaintext = match cipher.decrypt(nonce, ciphertext) {
        Ok(p) => p,
        Err(_) => return std::ptr::null_mut(),
    };

    *out_len = plaintext.len() as i32;
    let ptr = plaintext.as_mut_ptr();
    std::mem::forget(plaintext);
    ptr
}

#[no_mangle]
pub unsafe extern "C" fn preconnect_native_free_bytes(ptr: *mut u8, len: i32) {
    if ptr.is_null() || len <= 0 {
        return;
    }
    let _ = Vec::from_raw_parts(ptr, len as usize, len as usize);
}
