use serde::Deserialize;

#[derive(Deserialize)]
pub struct Job {
    pub id: Option<String>,
    #[serde(rename = "controlFile")]
    pub control_file: String,
    pub payload: String,
    #[serde(rename = "printerHost")]
    pub printer_host: Option<String>,
    #[serde(rename = "printerQueue")]
    pub printer_queue: Option<String>,
}
