use std::{
    io::{Read, Write},
    net::TcpStream,
};

pub trait TcpExtras {
    fn send_buf(&mut self, buf: &[u8]) -> bool;
    fn recv_ack(&mut self) -> bool;
}

impl TcpExtras for TcpStream {
    fn send_buf(&mut self, buf: &[u8]) -> bool {
        self.write_all(buf).is_ok()
    }

    fn recv_ack(&mut self) -> bool {
        let mut recv = [0u8; 1];
        match self.read_exact(&mut recv) {
            Ok(_) => recv[0] == 0,
            Err(_) => false,
        }
    }
}
