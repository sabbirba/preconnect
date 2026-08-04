use serde::Deserialize;

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Job {
    pub id: Option<String>,
    pub printer_host: Option<String>,
    pub printer_queue: Option<String>,
    pub q_cmd: Option<String>,
    pub cf_hdr: Option<String>,
    pub ctl: Option<String>,
    pub df_hdr: Option<String>,
    pub control_file: Option<String>,
    pub payload: Option<String>,
}
