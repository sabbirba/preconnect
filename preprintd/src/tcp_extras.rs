use std::{
    io::{self, Read, Write},
    net::TcpStream,
};

pub trait TcpExtras {
    fn send_buf(&mut self, buf: &[u8]) -> io::Result<bool>;
    fn recv_ack(&mut self) -> io::Result<bool>;
}

impl TcpExtras for TcpStream {
    fn send_buf(&mut self, buf: &[u8]) -> io::Result<bool> {
        self.write_all(buf)?;
        Ok(true)
    }

    fn recv_ack(&mut self) -> io::Result<bool> {
        let mut ack = [0u8; 1];
        self.read_exact(&mut ack)?;
        Ok(ack == [0u8])
    }
}
