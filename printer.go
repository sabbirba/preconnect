package main

import (
	"bufio"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net"
	"net/http"
	"strings"
	"time"
)

type PrintJob struct {
	PrinterHost  string `json:"printerHost"`
	PrinterQueue string `json:"printerQueue"`
	ControlFile  string `json:"controlFile"`
	Payload      string `json:"payload"`
}

func main() {
	for {
		stream()
		time.Sleep(5 * time.Second)
	}
}

func stream() {
	req, err := http.NewRequest("GET", "https://api.preconnect.app/printer", nil)
	if err != nil {
		return
	}
	req.Header.Set("Accept", "text/event-stream")
	req.Header.Set("Cache-Control", "no-cache")
	resp, err := (&http.Client{}).Do(req)
	if err != nil {
		return
	}
	defer resp.Body.Close()
	reader := bufio.NewReader(resp.Body)
	for {
		line, err := reader.ReadString('\n')
		if err != nil {
			break
		}
		line = strings.TrimSpace(line)
		if strings.HasPrefix(line, "data: ") {
			var job PrintJob
			if err := json.Unmarshal([]byte(line[6:]), &job); err == nil {
				go handle(job)
			}
		}
	}
}

func handle(job PrintJob) {
	control, err1 := base64.StdEncoding.DecodeString(job.ControlFile)
	payload, err2 := base64.StdEncoding.DecodeString(job.Payload)
	if err1 != nil || err2 != nil {
		return
	}
	conn, err := net.DialTimeout("tcp", net.JoinHostPort(job.PrinterHost, "515"), 10*time.Second)
	if err != nil {
		return
	}
	defer conn.Close()
	if !write(conn, append([]byte{2}, append([]byte(job.PrinterQueue), 10)...)) {
		return
	}
	cf := []byte(fmt.Sprintf("%c%d cfA002sysprint%c", 2, len(control), 10))
	if !write(conn, cf) || !write(conn, append(control, 0)) {
		return
	}
	df := []byte(fmt.Sprintf("%c%d dfA002sysprint%c", 3, len(payload), 10))
	if write(conn, df) {
		write(conn, append(payload, 0))
	}
}

func write(conn net.Conn, data []byte) bool {
	if _, err := conn.Write(data); err != nil {
		return false
	}
	ack := make([]byte, 1)
	_, err := conn.Read(ack)
	return err == nil && ack[0] == 0
}
