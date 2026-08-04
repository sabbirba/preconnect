use serde::Deserialize;

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Job {
    pub id: Option<String>,
    pub printer_host: Option<String>,
    pub q_cmd: Option<String>,
    pub cf_hdr: String,
    pub ctl: String,
    pub df_hdr: String,
    pub payload: String,
}
