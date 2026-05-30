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
