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

#[derive(serde::Deserialize)]
#[serde(rename_all = "camelCase")]
struct RawSection {
    course_code: String,
    section_name: String,
    semester_session_id: i32,
    section_schedule: RawSectionSchedule,
}

#[derive(serde::Deserialize)]
#[serde(rename_all = "camelCase")]
struct RawSectionSchedule {
    class_start_date: String,
    class_end_date: String,
    class_schedules: Vec<RawClassScheduleSlot>,
}

#[derive(serde::Deserialize)]
#[serde(rename_all = "camelCase")]
struct RawClassScheduleSlot {
    start_time: String,
    end_time: String,
    day: String,
}

#[derive(serde::Deserialize, serde::Serialize, Clone)]
#[serde(rename_all = "camelCase")]
struct OutputWindow {
    start_at: i64,
    end_at: i64,
    source: String,
    label: String,
}

fn parse_date(s: &str) -> Option<(i32, u32, u32)> {
    let parts: Vec<&str> = s.split(|c: char| !c.is_numeric()).filter(|p| !p.is_empty()).collect();
    if parts.len() < 3 {
        return None;
    }
    let n1 = parts[0].parse::<i32>().ok()?;
    let n2 = parts[1].parse::<u32>().ok()?;
    let n3 = parts[2].parse::<i32>().ok()?;
    
    if n1 > 1000 {
        Some((n1, n2, n3 as u32))
    } else if n3 > 1000 {
        Some((n3, n2, n1 as u32))
    } else {
        None
    }
}

fn parse_time(s: &str) -> Option<(u32, u32)> {
    let s_upper = s.trim().to_uppercase();
    let is_pm = s_upper.contains("PM");
    let is_am = s_upper.contains("AM");
    
    let parts: Vec<&str> = s_upper
        .split(|c: char| !c.is_numeric())
        .filter(|p| !p.is_empty())
        .collect();
    if parts.len() < 2 {
        return None;
    }
    let mut hour = parts[0].parse::<u32>().ok()?;
    let minute = parts[1].parse::<u32>().ok()?;
    
    if is_am || is_pm {
        if hour == 12 {
            hour = if is_am { 0 } else { 12 };
        } else if is_pm {
            hour += 12;
        }
    }
    
    if hour < 24 && minute < 60 {
        Some((hour, minute))
    } else {
        None
    }
}

fn weekday_num(day: &str) -> Option<u32> {
    match day.trim().to_uppercase().as_str() {
        "MONDAY" => Some(1),
        "TUESDAY" => Some(2),
        "WEDNESDAY" => Some(3),
        "THURSDAY" => Some(4),
        "FRIDAY" => Some(5),
        "SATURDAY" => Some(6),
        "SUNDAY" => Some(7),
        _ => None,
    }
}

fn is_leap_year(y: i32) -> bool {
    (y % 4 == 0 && y % 100 != 0) || (y % 400 == 0)
}

fn date_to_epoch_ms(y: i32, m: u32, d: u32, h: u32, min: u32) -> i64 {
    let days_in_months = [0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    let mut total_days = 0i64;
    
    let year_start = 1970;
    if y >= year_start {
        for year in year_start..y {
            total_days += if is_leap_year(year) { 366 } else { 365 };
        }
    } else {
        for year in y..year_start {
            total_days -= if is_leap_year(year) { 366 } else { 365 };
        }
    }
    
    for month in 1..m {
        if month == 2 && is_leap_year(y) {
            total_days += 29;
        } else {
            total_days += days_in_months[month as usize] as i64;
        }
    }
    
    total_days += (d as i64) - 1;
    
    let total_hours = total_days * 24 + (h as i64);
    let total_minutes = total_hours * 60 + (min as i64);
    total_minutes * 60 * 1000
}

fn epoch_ms_to_date(epoch_ms: i64) -> (i32, u32, u32) {
    let days_in_months = [0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    let mut days = epoch_ms / (24 * 60 * 60 * 1000);
    if epoch_ms % (24 * 60 * 60 * 1000) < 0 {
        days -= 1;
    }
    
    let mut y = 1970;
    loop {
        let leap = is_leap_year(y);
        let days_in_year = if leap { 366 } else { 365 };
        if days >= days_in_year {
            days -= days_in_year;
            y += 1;
        } else if days < 0 {
            y -= 1;
            let leap_prev = is_leap_year(y);
            days += if leap_prev { 366 } else { 365 };
        } else {
            break;
        }
    }
    
    let mut m = 1u32;
    loop {
        let days_in_month = if m == 2 && is_leap_year(y) {
            29
        } else {
            days_in_months[m as usize] as i64
        };
        if days >= days_in_month {
            days -= days_in_month;
            m += 1;
        } else {
            break;
        }
    }
    
    (y, m, (days + 1) as u32)
}

fn day_of_week(y: i32, m: u32, d: u32) -> u32 {
    let t = [0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4];
    let mut y = y;
    if m < 3 {
        y -= 1;
    }
    let m_idx = (m - 1) as usize;
    let val = (y + y / 4 - y / 100 + y / 400 + t[m_idx] + d as i32) % 7;
    if val == 0 {
        7
    } else {
        val as u32
    }
}

fn adjust_ramadan_range(start_min: u32, end_min: u32) -> (u32, u32) {
    match (start_min, end_min) {
        (480, 560) => (480, 545),
        (570, 650) => (555, 620),
        (660, 740) => (630, 695),
        (750, 830) => (705, 770),
        (840, 920) => (780, 845),
        (930, 1010) => (855, 920),
        (1020, 1100) => (930, 995),
        (1110, 1290) => (960, 1080),
        (480, 650) => (480, 620),
        (570, 740) => (555, 695),
        (660, 830) => (630, 770),
        (750, 920) => (705, 845),
        (840, 1010) => (780, 920),
        (930, 1100) => (855, 995),
        (1020, 1290) => (930, 1080),
        _ => (start_min, end_min),
    }
}

fn merge_windows(mut windows: Vec<OutputWindow>) -> Vec<OutputWindow> {
    if windows.is_empty() {
        return Vec::new();
    }
    windows.sort_by_key(|w| w.start_at);
    
    let mut merged = Vec::new();
    merged.push(windows[0].clone());
    
    for window in windows.into_iter().skip(1) {
        let last_idx = merged.len() - 1;
        let last = &mut merged[last_idx];
        if window.start_at > last.end_at {
            merged.push(window);
        } else {
            if window.end_at > last.end_at {
                last.end_at = window.end_at;
            }
        }
    }
    merged
}

#[no_mangle]
pub unsafe extern "C" fn preconnect_native_expand_and_merge_class_schedules(
    sections_json_ptr: *const c_char,
    extra_windows_json_ptr: *const c_char,
    semester_session_id: i32,
    is_ramadan: i32,
    now_ms: i64,
    timezone_offset_ms: i64,
) -> *mut c_char {
    if sections_json_ptr.is_null() {
        return std::ptr::null_mut();
    }
    
    let c_str = std::ffi::CStr::from_ptr(sections_json_ptr);
    let str_slice = match c_str.to_str() {
        Ok(s) => s,
        Err(_) => return std::ptr::null_mut(),
    };
    
    let sections: Vec<RawSection> = match serde_json::from_str(str_slice) {
        Ok(s) => s,
        Err(_) => return std::ptr::null_mut(),
    };
    
    let mut raw_windows = Vec::new();
    
    // Add any pre-computed extra windows (midterms, finals, custom schedules) from Dart
    if !extra_windows_json_ptr.is_null() {
        let c_extra = std::ffi::CStr::from_ptr(extra_windows_json_ptr);
        if let Ok(extra_slice) = c_extra.to_str() {
            if let Ok(extra_wins) = serde_json::from_str::<Vec<OutputWindow>>(extra_slice) {
                raw_windows.extend(extra_wins);
            }
        }
    }
    
    let is_ramadan_bool = is_ramadan == 1;
    
    for section in sections {
        if section.semester_session_id != semester_session_id {
            continue;
        }
        
        let start_date = match parse_date(&section.section_schedule.class_start_date) {
            Some(d) => d,
            None => continue,
        };
        let end_date = match parse_date(&section.section_schedule.class_end_date) {
            Some(d) => d,
            None => continue,
        };
        
        let start_epoch = date_to_epoch_ms(start_date.0, start_date.1, start_date.2, 0, 0);
        let end_epoch = date_to_epoch_ms(end_date.0, end_date.1, end_date.2, 0, 0);
        
        let mut current_epoch = start_epoch;
        while current_epoch <= end_epoch {
            let (cy, cm, cd) = epoch_ms_to_date(current_epoch);
            let weekday = day_of_week(cy, cm, cd);
            
            for slot in &section.section_schedule.class_schedules {
                let slot_weekday = match weekday_num(&slot.day) {
                    Some(w) => w,
                    None => continue,
                };
                if weekday != slot_weekday {
                    continue;
                }
                
                let start_hm = match parse_time(&slot.start_time) {
                    Some(t) => t,
                    None => continue,
                };
                let end_hm = match parse_time(&slot.end_time) {
                    Some(t) => t,
                    None => continue,
                };
                
                let (adj_start_h, adj_start_m, adj_end_h, adj_end_m) = if is_ramadan_bool {
                    let start_min = start_hm.0 * 60 + start_hm.1;
                    let end_min = end_hm.0 * 60 + end_hm.1;
                    let (a_start, a_end) = adjust_ramadan_range(start_min, end_min);
                    (a_start / 60, a_start % 60, a_end / 60, a_end % 60)
                } else {
                    (start_hm.0, start_hm.1, end_hm.0, end_hm.1)
                };
                
                let start_at = date_to_epoch_ms(cy, cm, cd, adj_start_h, adj_start_m) - timezone_offset_ms;
                let end_at = date_to_epoch_ms(cy, cm, cd, adj_end_h, adj_end_m) - timezone_offset_ms;
                
                if end_at <= start_at || end_at < now_ms {
                    continue;
                }
                
                raw_windows.push(OutputWindow {
                    start_at,
                    end_at,
                    source: "class".to_string(),
                    label: format!("{} {}", section.course_code.trim().to_uppercase(), section.section_name.trim()),
                });
            }
            
            current_epoch += 24 * 60 * 60 * 1000;
        }
    }
    
    let merged = merge_windows(raw_windows);
    
    let out_str = match serde_json::to_string(&merged) {
        Ok(s) => s,
        Err(_) => return std::ptr::null_mut(),
    };
    
    CString::new(out_str).unwrap().into_raw()
}
