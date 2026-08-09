use serde::Deserialize;

#[derive(Debug, Deserialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct Job {
    pub id: Option<String>,
    pub printer_host: Option<String>,
    pub printer_queue: Option<String>,
    pub timeout: Option<f64>,

    pub q_cmd: Option<String>,
    pub cf_hdr: Option<String>,
    pub ctl: Option<String>,
    pub df_hdr: Option<String>,
    pub payload: Option<String>,
}

pub enum LogLevel {
    Ok,
    Warn,
    Error,
}
