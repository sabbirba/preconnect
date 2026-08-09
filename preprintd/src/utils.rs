use uuid::Uuid;

pub fn create_new_ident() -> String {
    let mut ident = Uuid::new_v4().to_string();
    ident.push('_');
    ident.push_str(std::env::consts::ARCH);
    ident
}
