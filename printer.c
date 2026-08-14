#ifndef _CRT_SECURE_NO_WARNINGS
#define _CRT_SECURE_NO_WARNINGS
#endif

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif

#include <windows.h>
#include <winsock2.h>
#include <ws2tcpip.h>
#include <winhttp.h>
#include <wincrypt.h>
#include <winspool.h>
#include <shlobj.h>
#include <wincred.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <process.h>

#pragma comment(lib, "user32.lib")
#pragma comment(lib, "ws2_32.lib")
#pragma comment(lib, "winhttp.lib")
#pragma comment(lib, "crypt32.lib")
#pragma comment(lib, "winspool.lib")
#pragma comment(lib, "rpcrt4.lib")
#pragma comment(lib, "shell32.lib")
#pragma comment(lib, "advapi32.lib")

#define BASE_DOMAIN L"api.preconnect.app"
#define BASE_PORT 443
#define CRED_TARGET_NAME L"PreConnect/PrintWorkerKey"
#define JWT_HDR_PAY "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJwcmludGVyIiwiaXNzIjoicHJlY29ubmVjdCJ9"
#define DEF_HOST_STR "172.16.0.111"
#define DEF_QUEUE_STR "secure"

typedef struct {
    BYTE *data;
    DWORD len;
} JobChunk;

static char g_worker_key[512] = {0};
static char g_worker_ident[256] = {0};
static char g_last_event_id[128] = {0};
static wchar_t g_resolved_ip[64] = {0};
static DWORD g_jobs_completed = 0;
static LONG g_claim_count = 0;
static BOOL g_debug_mode = FALSE;
static BOOL g_is_service = FALSE;
static SERVICE_STATUS g_svc_status;
static SERVICE_STATUS_HANDLE g_svc_handle = NULL;
static CRITICAL_SECTION g_print_lock;
static HINTERNET g_hSession = NULL;
static HINTERNET g_hConnect = NULL;
static HCRYPTPROV g_hProv = 0;
static HANDLE g_hMutex = NULL;

void log_msg(const char *level, const char *msg) {
    SYSTEMTIME st;
    GetLocalTime(&st);
    char time_str[64];
    snprintf(time_str, sizeof(time_str), "%04d-%02d-%02d %02d:%02d:%02d",
             st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond);

    if (g_debug_mode || strcmp(level, "ERR") == 0 || strcmp(level, "CRIT") == 0) {
        fprintf(stderr, "[%s] [%s] %s\n", time_str, level, msg);
        fflush(stderr);
    }

    char log_path[MAX_PATH] = {0};
    if (SUCCEEDED(SHGetFolderPathA(NULL, CSIDL_COMMON_APPDATA, NULL, 0, log_path))) {
        strcat(log_path, "\\printer\\printer.log");
        FILE *f = fopen(log_path, "a+");
        if (f) {
            fseek(f, 0, SEEK_END);
            long sz = ftell(f);
            if (sz > 64 * 1024) {
                fclose(f);
                char old_path[MAX_PATH] = {0};
                snprintf(old_path, sizeof(old_path), "%s.old", log_path);
                DeleteFileA(old_path);
                MoveFileA(log_path, old_path);
                f = fopen(log_path, "w");
            }
            if (f) {
                fprintf(f, "[%s] [%s] %s\n", time_str, level, msg);
                fclose(f);
            }
        }
    }
}

void clean_key() {
    SecureZeroMemory(g_worker_key, sizeof(g_worker_key));
}

void *mem_alloc(size_t size) {
    return size ? HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, size) : NULL;
}

void mem_free(void *ptr, size_t size) {
    if (ptr) {
        if (size) SecureZeroMemory(ptr, size);
        HeapFree(GetProcessHeap(), 0, ptr);
    }
}

void _trim_working_set() {
    SetProcessWorkingSetSize(GetCurrentProcess(), (SIZE_T)-1, (SIZE_T)-1);
}

double get_hires_time_ms() {
    LARGE_INTEGER count, freq;
    QueryPerformanceCounter(&count);
    QueryPerformanceFrequency(&freq);
    return ((double)count.QuadPart * 1000.0) / (double)freq.QuadPart;
}

BOOL WINAPI console_ctrl_handler(DWORD ctrl_type) {
    (void)ctrl_type;
    clean_key();
    if (g_hConnect) WinHttpCloseHandle(g_hConnect);
    if (g_hSession) WinHttpCloseHandle(g_hSession);
    if (g_hProv) CryptReleaseContext(g_hProv, 0);
    if (g_hMutex) CloseHandle(g_hMutex);
    WSACleanup();
    ExitProcess(0);
}

void hide_console_window() {
    HWND hwnd = GetConsoleWindow();
    if (hwnd) {
        ShowWindow(hwnd, SW_HIDE);
    }
}

void ensure_single_instance() {
    g_hMutex = CreateMutexW(NULL, TRUE, L"Global\\PreConnectPrinterWorkerMutex");
    if (!g_hMutex && GetLastError() == ERROR_ACCESS_DENIED) {
        g_hMutex = CreateMutexW(NULL, TRUE, L"Local\\PreConnectPrinterWorkerMutex");
    }
    if (GetLastError() == ERROR_ALREADY_EXISTS) {
        if (g_debug_mode) fprintf(stderr, "error: another instance is already running\n");
        ExitProcess(0);
    }
}

void ensure_crypto_provider() {
    if (!g_hProv) {
        CryptAcquireContextW(&g_hProv, NULL, NULL, PROV_RSA_AES, CRYPT_VERIFYCONTEXT);
    }
}

BOOL save_key_to_cred_vault(const char *key) {
    CREDENTIALW cred = {0};
    cred.Type = CRED_TYPE_GENERIC;
    cred.TargetName = CRED_TARGET_NAME;
    cred.CredentialBlobSize = (DWORD)strlen(key);
    cred.CredentialBlob = (LPBYTE)key;
    cred.Persist = CRED_PERSIST_LOCAL_MACHINE;
    cred.UserName = L"PreConnectWorker";
    return CredWriteW(&cred, 0);
}

BOOL read_key_from_cred_vault(char *out_key, size_t out_size) {
    PCREDENTIALW pcred = NULL;
    if (CredReadW(CRED_TARGET_NAME, CRED_TYPE_GENERIC, 0, &pcred) && pcred) {
        size_t len = (pcred->CredentialBlobSize < out_size - 1) ? pcred->CredentialBlobSize : (out_size - 1);
        memcpy(out_key, pcred->CredentialBlob, len);
        out_key[len] = '\0';
        CredFree(pcred);
        return TRUE;
    }
    return FALSE;
}

HINTERNET get_persistent_connect() {
    const wchar_t *host = (g_resolved_ip[0] != L'\0') ? g_resolved_ip : BASE_DOMAIN;
    if (!g_hConnect && g_hSession) {
        g_hConnect = WinHttpConnect(g_hSession, host, BASE_PORT, 0);
    }
    return g_hConnect;
}

void reset_persistent_connect() {
    if (g_hConnect) {
        WinHttpCloseHandle(g_hConnect);
        g_hConnect = NULL;
    }
}

void base64_url_encode(const unsigned char *input, size_t input_len, char *output, size_t output_size) {
    DWORD out_len = (DWORD)output_size;
    if (!CryptBinaryToStringA(input, (DWORD)input_len, CRYPT_STRING_BASE64 | CRYPT_STRING_NOCRLF, output, &out_len)) {
        output[0] = '\0';
        return;
    }
    size_t len = strlen(output), write_idx = 0;
    for (size_t i = 0; i < len; i++) {
        if (output[i] == '=') continue;
        output[write_idx++] = (output[i] == '+') ? '-' : (output[i] == '/') ? '_' : output[i];
    }
    output[write_idx] = '\0';
}

BOOL compute_hmac_sha256(const char *key, const char *data, unsigned char *out_sig) {
    HCRYPTHASH hHash = 0;
    HCRYPTKEY hKey = 0;
    BOOL res = FALSE;

    ensure_crypto_provider();
    if (!g_hProv) return FALSE;

    struct {
        BLOBHEADER hdr;
        DWORD dwKeySize;
        BYTE rgbKeyData[512];
    } keyBlob;

    size_t key_len = strlen(key);
    if (key_len > 512) key_len = 512;

    keyBlob.hdr.bType = PLAINTEXTKEYBLOB;
    keyBlob.hdr.bVersion = CUR_BLOB_VERSION;
    keyBlob.hdr.reserved = 0;
    keyBlob.hdr.aiKeyAlg = CALG_RC2;
    keyBlob.dwKeySize = (DWORD)key_len;
    memcpy(keyBlob.rgbKeyData, key, key_len);

    if (CryptImportKey(g_hProv, (BYTE *)&keyBlob, sizeof(BLOBHEADER) + sizeof(DWORD) + (DWORD)key_len, 0, CRYPT_IPSEC_HMAC_KEY, &hKey)) {
        if (CryptCreateHash(g_hProv, CALG_HMAC, hKey, 0, &hHash)) {
            HMAC_INFO hmacInfo = {0};
            hmacInfo.HashAlgid = CALG_SHA_256;
            CryptSetHashParam(hHash, HP_HMAC_INFO, (BYTE *)&hmacInfo, 0);

            if (CryptHashData(hHash, (const BYTE *)data, (DWORD)strlen(data), 0)) {
                DWORD hash_len = 32;
                if (CryptGetHashParam(hHash, HP_HASHVAL, out_sig, &hash_len, 0)) res = TRUE;
            }
            CryptDestroyHash(hHash);
        }
        CryptDestroyKey(hKey);
    }
    return res;
}

BOOL sha256_hash(const BYTE *data, DWORD len, BYTE out_hash[32]) {
    HCRYPTHASH hHash = 0;
    BOOL res = FALSE;
    ensure_crypto_provider();
    if (!g_hProv) return FALSE;
    if (CryptCreateHash(g_hProv, CALG_SHA_256, 0, 0, &hHash)) {
        if (CryptHashData(hHash, data, len, 0)) {
            DWORD hash_len = 32;
            if (CryptGetHashParam(hHash, HP_HASHVAL, out_hash, &hash_len, 0)) res = TRUE;
        }
        CryptDestroyHash(hHash);
    }
    return res;
}

void make_subscriber_jwt(char *out_jwt, size_t out_size) {
    unsigned char hmac_buf[32];
    char sig_b64[128] = {0};
    if (compute_hmac_sha256(g_worker_key, JWT_HDR_PAY, hmac_buf)) {
        base64_url_encode(hmac_buf, 32, sig_b64, sizeof(sig_b64));
    }
    snprintf(out_jwt, out_size, "%s.%s", JWT_HDR_PAY, sig_b64);
}

void add_worker_auth_headers(HINTERNET hRequest, const wchar_t *content_type) {
    if (g_resolved_ip[0] != L'\0') {
        WinHttpAddRequestHeaders(hRequest, L"Host: api.preconnect.app\r\n", (DWORD)-1, WINHTTP_ADDREQ_FLAG_ADD);
    }

    char jwt[512] = {0};
    make_subscriber_jwt(jwt, sizeof(jwt));

    wchar_t headers[2048];
    if (g_last_event_id[0] != '\0' && !content_type) {
        swprintf(headers, 2048, L"Authorization: Bearer %hs\r\nX-Worker-Key: %hs\r\nX-Worker-Jobs: %lu\r\nX-Worker-Ident: %hs\r\nLast-Event-ID: %hs\r\nAccept: text/event-stream\r\n", jwt, g_worker_key, g_jobs_completed, g_worker_ident, g_last_event_id);
    } else if (content_type) {
        swprintf(headers, 2048, L"Authorization: Bearer %hs\r\nX-Worker-Key: %hs\r\nX-Worker-Jobs: %lu\r\nX-Worker-Ident: %hs\r\nContent-Type: %ls\r\n", jwt, g_worker_key, g_jobs_completed, g_worker_ident, content_type);
    } else {
        swprintf(headers, 2048, L"Authorization: Bearer %hs\r\nX-Worker-Key: %hs\r\nX-Worker-Jobs: %lu\r\nX-Worker-Ident: %hs\r\nAccept: text/event-stream\r\n", jwt, g_worker_key, g_jobs_completed, g_worker_ident);
    }
    WinHttpAddRequestHeaders(hRequest, headers, (DWORD)-1, WINHTTP_ADDREQ_FLAG_ADD);
}

BOOL decrypt_dpapi_key(const char *b64_input, char *out_key, size_t out_size) {
    if (strncmp(b64_input, "DPAPI:", 6) != 0) {
        strncpy(out_key, b64_input, out_size - 1);
        return TRUE;
    }
    const char *encoded = b64_input + 6;
    DWORD bin_len = 0;
    if (!CryptStringToBinaryA(encoded, 0, CRYPT_STRING_BASE64, NULL, &bin_len, NULL, NULL)) return FALSE;

    BYTE *bin_data = (BYTE *)mem_alloc(bin_len);
    if (!bin_data) return FALSE;

    if (!CryptStringToBinaryA(encoded, 0, CRYPT_STRING_BASE64, bin_data, &bin_len, NULL, NULL)) {
        mem_free(bin_data, bin_len);
        return FALSE;
    }

    DATA_BLOB in_blob = {bin_len, bin_data}, out_blob;
    BOOL ok = CryptUnprotectData(&in_blob, NULL, NULL, NULL, NULL, 0, &out_blob);
    mem_free(bin_data, bin_len);

    if (ok) {
        size_t copy_len = (out_blob.cbData < out_size - 1) ? out_blob.cbData : (out_size - 1);
        memcpy(out_key, out_blob.pbData, copy_len);
        out_key[copy_len] = '\0';
        SecureZeroMemory(out_blob.pbData, out_blob.cbData);
        LocalFree(out_blob.pbData);
        return TRUE;
    }
    return FALSE;
}

void load_worker_key(int argc, char *argv[]) {
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--debug") == 0) {
            g_debug_mode = TRUE;
        } else if (strcmp(argv[i], "--service") == 0) {
            g_is_service = TRUE;
        } else if (strlen(argv[i]) > 0 && argv[i][0] != '-' && g_worker_key[0] == '\0') {
            decrypt_dpapi_key(argv[i], g_worker_key, sizeof(g_worker_key));
            save_key_to_cred_vault(g_worker_key);
            SecureZeroMemory(argv[i], strlen(argv[i]));
        }
    }
    if (g_worker_key[0] == '\0') read_key_from_cred_vault(g_worker_key, sizeof(g_worker_key));
}

void generate_uuid_ident(char *out, size_t out_size) {
    UUID uuid;
    UuidCreate(&uuid);
    RPC_CSTR uuid_str;
    UuidToStringA(&uuid, &uuid_str);
    snprintf(out, out_size, "%s_x86_64", (char *)uuid_str);
    RpcStringFreeA(&uuid_str);
}

void generate_worker_ident() {
    char dir_path[MAX_PATH] = {0};
    if (SUCCEEDED(SHGetFolderPathA(NULL, CSIDL_COMMON_APPDATA, NULL, 0, dir_path))) {
        strcat(dir_path, "\\ident.dat");

        FILE *f = fopen(dir_path, "r");
        if (f) {
            if (fgets(g_worker_ident, sizeof(g_worker_ident), f)) {
                size_t l = strlen(g_worker_ident);
                while (l > 0 && (g_worker_ident[l - 1] == '\r' || g_worker_ident[l - 1] == '\n' || g_worker_ident[l - 1] == ' ')) g_worker_ident[--l] = '\0';
            }
            fclose(f);
        }

        if (g_worker_ident[0] == '\0') {
            generate_uuid_ident(g_worker_ident, sizeof(g_worker_ident));
            f = fopen(dir_path, "w");
            if (f) {
                fputs(g_worker_ident, f);
                fclose(f);
            }
        }
        return;
    }
    generate_uuid_ident(g_worker_ident, sizeof(g_worker_ident));
}

BOOL resolve_doh(const wchar_t *doh_ip, wchar_t *out_ip_str, size_t out_size) {
    HINTERNET hConn = WinHttpConnect(g_hSession, doh_ip, 443, 0);
    if (!hConn) return FALSE;

    BOOL ok = FALSE;
    HINTERNET hReq = WinHttpOpenRequest(hConn, L"GET", L"/dns-query?name=api.preconnect.app&type=A", NULL, WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES, WINHTTP_FLAG_SECURE);
    if (hReq) {
        WinHttpAddRequestHeaders(hReq, L"Accept: application/dns-json\r\n", (DWORD)-1, WINHTTP_ADDREQ_FLAG_ADD);
        if (WinHttpSendRequest(hReq, WINHTTP_NO_ADDITIONAL_HEADERS, 0, WINHTTP_NO_REQUEST_DATA, 0, 0, 0)) {
            if (WinHttpReceiveResponse(hReq, NULL)) {
                char resp[4096] = {0};
                DWORD bread = 0;
                if (WinHttpReadData(hReq, resp, sizeof(resp) - 1, &bread) && bread > 0) {
                    resp[bread] = '\0';
                    const char *data_p = strstr(resp, "\"data\":\"");
                    if (data_p) {
                        data_p += 8;
                        char ip_a[64] = {0};
                        size_t idx = 0;
                        while (*data_p && *data_p != '"' && idx < sizeof(ip_a) - 1) ip_a[idx++] = *data_p++;
                        ip_a[idx] = '\0';
                        MultiByteToWideChar(CP_UTF8, 0, ip_a, -1, out_ip_str, (int)out_size);
                        ok = TRUE;
                    }
                }
            }
        }
        WinHttpCloseHandle(hReq);
    }
    WinHttpCloseHandle(hConn);
    return ok;
}

const char *find_json_value_start(const char *json, const char *key) {
    char pattern[128];
    snprintf(pattern, sizeof(pattern), "\"%s\"", key);
    const char *p = strstr(json, pattern);
    if (!p) return NULL;
    p = strchr(p + strlen(pattern), ':');
    return p ? p + 1 : NULL;
}

static BOOL parse_json_str(const char *json, const char *key, char *out, size_t out_size) {
    const char *p = find_json_value_start(json, key);
    if (!p) return FALSE;
    p = strchr(p, '"');
    if (!p) return FALSE;
    p++;
    size_t idx = 0;
    while (*p && *p != '"' && idx < out_size - 1) {
        if (*p == '\\' && *(p + 1)) p++;
        out[idx++] = *p++;
    }
    out[idx] = '\0';
    return TRUE;
}

static BOOL parse_json_bool(const char *json, const char *key) {
    const char *p = find_json_value_start(json, key);
    if (!p) return FALSE;
    while (*p == ' ' || *p == '\t') p++;
    return (strncmp(p, "true", 4) == 0);
}

BYTE *base64_decode_raw(const char *input, DWORD *out_len) {
    DWORD bin_len = 0;
    if (!CryptStringToBinaryA(input, 0, CRYPT_STRING_BASE64, NULL, &bin_len, NULL, NULL)) return NULL;
    BYTE *buf = (BYTE *)mem_alloc(bin_len);
    if (!buf) return NULL;
    if (!CryptStringToBinaryA(input, 0, CRYPT_STRING_BASE64, buf, &bin_len, NULL, NULL)) {
        mem_free(buf, bin_len);
        return NULL;
    }
    *out_len = bin_len;
    return buf;
}

BYTE *decrypt_payload_buf(const char *b64_str, const char *job_id, DWORD *out_size) {
    if (!b64_str || strlen(b64_str) == 0) return NULL;
    DWORD raw_len = 0;
    BYTE *raw = base64_decode_raw(b64_str, &raw_len);
    if (!raw || raw_len < 16) {
        if (raw) mem_free(raw, raw_len);
        return NULL;
    }

    BYTE iv[16];
    memcpy(iv, raw, 16);
    BYTE *enc = raw + 16;
    DWORD enc_len = raw_len - 16;

    char seed_buf[1024];
    snprintf(seed_buf, sizeof(seed_buf), "%s", g_worker_key);
    size_t seed_len = strlen(seed_buf);
    memcpy(seed_buf + seed_len, iv, 16);
    seed_len += 16;
    size_t jid_len = strlen(job_id);
    memcpy(seed_buf + seed_len, job_id, jid_len);
    seed_len += jid_len;

    BYTE p_hash[32];
    sha256_hash((const BYTE *)seed_buf, (DWORD)seed_len, p_hash);

    BYTE *dec = (BYTE *)mem_alloc(enc_len + 1);
    if (!dec) {
        mem_free(raw, raw_len);
        return NULL;
    }

    DWORD idx = 0;
    for (DWORD i = 0; i < enc_len; i += 32) {
        DWORD chunk_len = (enc_len - i < 32) ? (enc_len - i) : 32;
        BYTE ks_in[36];
        memcpy(ks_in, p_hash, 32);
        ks_in[32] = (BYTE)((idx >> 24) & 0xFF);
        ks_in[33] = (BYTE)((idx >> 16) & 0xFF);
        ks_in[34] = (BYTE)((idx >> 8) & 0xFF);
        ks_in[35] = (BYTE)(idx & 0xFF);

        BYTE ks[32];
        sha256_hash(ks_in, 36, ks);

        DWORD j = 0;
        for (; j + 8 <= chunk_len; j += 8) *(UINT64 *)(dec + i + j) = *(UINT64 *)(enc + i + j) ^ *(UINT64 *)(ks + j);
        for (; j < chunk_len; j++) dec[i + j] = enc[i + j] ^ ks[j];
        idx++;
    }
    dec[enc_len] = '\0';
    mem_free(raw, raw_len);
    *out_size = enc_len;
    return dec;
}

SOCKET open_tcp_socket(const char *host, USHORT port, DWORD timeout_ms, int snd_buf, int rcv_buf) {
    struct addrinfo hints = {0}, *res = NULL;
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    hints.ai_protocol = IPPROTO_TCP;

    char port_str[16];
    snprintf(port_str, sizeof(port_str), "%u", port);
    if (getaddrinfo(host, port_str, &hints, &res) != 0 || !res) return INVALID_SOCKET;

    SOCKET s = socket(res->ai_family, res->ai_socktype, res->ai_protocol);
    if (s == INVALID_SOCKET) {
        freeaddrinfo(res);
        return INVALID_SOCKET;
    }

    BOOL opt_excl = TRUE;
    setsockopt(s, SOL_SOCKET, SO_EXCLUSIVEADDRUSE, (const char *)&opt_excl, sizeof(opt_excl));
    setsockopt(s, SOL_SOCKET, SO_RCVTIMEO, (const char *)&timeout_ms, sizeof(timeout_ms));
    setsockopt(s, SOL_SOCKET, SO_SNDTIMEO, (const char *)&timeout_ms, sizeof(timeout_ms));

    if (snd_buf > 0) setsockopt(s, SOL_SOCKET, SO_SNDBUF, (const char *)&snd_buf, sizeof(snd_buf));
    if (rcv_buf > 0) setsockopt(s, SOL_SOCKET, SO_RCVBUF, (const char *)&rcv_buf, sizeof(rcv_buf));

    if (connect(s, res->ai_addr, (int)res->ai_addrlen) != 0) {
        closesocket(s);
        s = INVALID_SOCKET;
    }
    freeaddrinfo(res);
    return s;
}

BOOL is_printer_online(const char *host, USHORT port) {
    SOCKET s = open_tcp_socket(host, port, 800, 0, 0);
    if (s == INVALID_SOCKET) return FALSE;
    shutdown(s, SD_BOTH);
    closesocket(s);
    return TRUE;
}

BOOL claim_job(const char *job_id) {
    if (!job_id || strlen(job_id) == 0) return TRUE;
    HINTERNET hConnect = get_persistent_connect();
    if (!hConnect) return FALSE;

    if (InterlockedIncrement(&g_claim_count) >= 3) {
        log_msg("OK", "Exhausted worker, resting...");
        Sleep(1000);
        InterlockedExchange(&g_claim_count, 0);
    }

    BOOL claimed = FALSE;
    HINTERNET hRequest = WinHttpOpenRequest(hConnect, L"POST", L"/print/claim", NULL, WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES, WINHTTP_FLAG_SECURE);
    if (hRequest) {
        add_worker_auth_headers(hRequest, L"application/json");
        char body[256];
        snprintf(body, sizeof(body), "{\"id\":\"%s\"}", job_id);
        if (WinHttpSendRequest(hRequest, WINHTTP_NO_ADDITIONAL_HEADERS, 0, (LPVOID)body, (DWORD)strlen(body), (DWORD)strlen(body), 0)) {
            if (WinHttpReceiveResponse(hRequest, NULL)) {
                char resp_buf[2048] = {0};
                DWORD bytes_read = 0;
                if (WinHttpReadData(hRequest, resp_buf, sizeof(resp_buf) - 1, &bytes_read) && bytes_read > 0) {
                    resp_buf[bytes_read] = '\0';
                    claimed = parse_json_bool(resp_buf, "claimed");
                }
            }
        }
        WinHttpCloseHandle(hRequest);
    } else {
        reset_persistent_connect();
    }
    return claimed;
}

static BOOL check_lpr_ack(SOCKET s) {
    char ack = 1;
    int r = recv(s, &ack, 1, 0);
    return (r == 1 && ack == 0);
}

void process_job_json(const char *json_str) {
    SetThreadExecutionState(ES_CONTINUOUS | ES_SYSTEM_REQUIRED);

    char host[128] = DEF_HOST_STR, queue[64] = DEF_QUEUE_STR, job_id[128] = {0};
    parse_json_str(json_str, "printerHost", host, sizeof(host));
    parse_json_str(json_str, "printerQueue", queue, sizeof(queue));
    parse_json_str(json_str, "id", job_id, sizeof(job_id));

    if (!is_printer_online(host, 515) || (strlen(job_id) > 0 && !claim_job(job_id))) {
        log_msg("WARN", "Printer offline or job claim skipped");
        SetThreadExecutionState(ES_CONTINUOUS);
        _trim_working_set();
        return;
    }

    size_t json_len = strlen(json_str);
    const char *keys[5] = {"qCmd", "cfHdr", "ctl", "dfHdr", "payload"};
    char *b64_bufs[5] = {0};
    JobChunk chunks[5] = {0};

    BOOL alloc_ok = TRUE;
    for (int i = 0; i < 5; i++) {
        b64_bufs[i] = (char *)mem_alloc(json_len + 1);
        if (!b64_bufs[i]) alloc_ok = FALSE;
        else parse_json_str(json_str, keys[i], b64_bufs[i], json_len + 1);
    }

    if (alloc_ok) {
        for (int i = 0; i < 5; i++) {
            chunks[i].data = decrypt_payload_buf(b64_bufs[i], job_id, &chunks[i].len);
        }
    }

    for (int i = 0; i < 5; i++) mem_free(b64_bufs[i], json_len + 1);

    if (!chunks[4].data || chunks[4].len == 0) {
        log_msg("ERR", "Empty job payload");
        for (int i = 0; i < 5; i++) mem_free(chunks[i].data, chunks[i].len);
        SetThreadExecutionState(ES_CONTINUOUS);
        _trim_working_set();
        return;
    }

    EnterCriticalSection(&g_print_lock);
    SOCKET s = open_tcp_socket(host, 515, 60000, 131072, 65536);
    if (s != INVALID_SOCKET) {
        BOOL opt_val = TRUE;
        setsockopt(s, IPPROTO_TCP, TCP_NODELAY, (const char *)&opt_val, sizeof(opt_val));
        setsockopt(s, SOL_SOCKET, SO_KEEPALIVE, (const char *)&opt_val, sizeof(opt_val));

        BOOL success = FALSE;
        send(s, (const char *)chunks[0].data, chunks[0].len, 0);
        if (check_lpr_ack(s)) {
            send(s, (const char *)chunks[1].data, chunks[1].len, 0);
            if (check_lpr_ack(s)) {
                send(s, (const char *)chunks[2].data, chunks[2].len, 0);
                send(s, "\0", 1, 0);
                if (check_lpr_ack(s)) {
                    send(s, (const char *)chunks[3].data, chunks[3].len, 0);
                    if (check_lpr_ack(s)) {
                        for (DWORD i = 0; i < chunks[4].len; i += 65536) {
                            DWORD chunk_size = (chunks[4].len - i < 65536) ? (chunks[4].len - i) : 65536;
                            send(s, (const char *)(chunks[4].data + i), chunk_size, 0);
                        }
                        send(s, "\0", 1, 0);
                        if (check_lpr_ack(s)) {
                            InterlockedIncrement((LONG *)&g_jobs_completed);
                            log_msg("OK", "Job transferred successfully");
                            success = TRUE;
                        }
                    }
                }
            }
        }
        if (!success) {
            struct linger sl = {1, 0};
            setsockopt(s, SOL_SOCKET, SO_LINGER, (const char *)&sl, sizeof(sl));
        } else {
            shutdown(s, SD_BOTH);
        }
        closesocket(s);
    }
    LeaveCriticalSection(&g_print_lock);

    for (int i = 0; i < 5; i++) mem_free(chunks[i].data, chunks[i].len);
    SetThreadExecutionState(ES_CONTINUOUS);
    _trim_working_set();
}

unsigned __stdcall job_thread_proc(void *arg) {
    char *json_str = (char *)arg;
    if (json_str) {
        process_job_json(json_str);
        mem_free(json_str, strlen(json_str) + 1);
    }
    return 0;
}

void dispatch_job_async(const char *json_str) {
    size_t len = strlen(json_str);
    char *copy = (char *)mem_alloc(len + 1);
    if (copy) {
        memcpy(copy, json_str, len + 1);
        uintptr_t th = _beginthreadex(NULL, 0, job_thread_proc, copy, 0, NULL);
        if (th) CloseHandle((HANDLE)th);
        else process_job_json(json_str);
    }
}

unsigned __stdcall ping_loop_thread(void *arg) {
    (void)arg;
    while (1) {
        HINTERNET hConnect = get_persistent_connect();
        if (hConnect) {
            HINTERNET hRequest = WinHttpOpenRequest(hConnect, L"POST", L"/print/ping", NULL, WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES, WINHTTP_FLAG_SECURE);
            if (hRequest) {
                add_worker_auth_headers(hRequest, L"application/json");
                const char *body = "{}";
                if (WinHttpSendRequest(hRequest, WINHTTP_NO_ADDITIONAL_HEADERS, 0, (LPVOID)body, (DWORD)strlen(body), (DWORD)strlen(body), 0)) {
                    if (WinHttpReceiveResponse(hRequest, NULL)) log_msg("OK", "Ping heartbeat sent");
                }
                WinHttpCloseHandle(hRequest);
            } else {
                reset_persistent_connect();
            }
        }
        Sleep(5000);
    }
    return 0;
}

void parse_sse_line(const char *line) {
    if (line[0] == ':') return;

    if (strncmp(line, "id: ", 4) == 0) {
        const char *id_val = line + 4;
        size_t len = strlen(id_val);
        while (len > 0 && (id_val[len - 1] == '\r' || id_val[len - 1] == '\n' || id_val[len - 1] == ' ')) len--;
        if (len < sizeof(g_last_event_id)) {
            memcpy(g_last_event_id, id_val, len);
            g_last_event_id[len] = '\0';
        }
    } else if (strncmp(line, "data: ", 6) == 0) {
        log_msg("OK", "Data match for new job!");
        dispatch_job_async(line + 6);
    }
}

BOOL start_sse_loop() {
    HINTERNET hConnect = get_persistent_connect();
    if (!hConnect) {
        if (!resolve_doh(L"1.1.1.1", g_resolved_ip, sizeof(g_resolved_ip) / sizeof(wchar_t))) {
            resolve_doh(L"8.8.8.8", g_resolved_ip, sizeof(g_resolved_ip) / sizeof(wchar_t));
        }
        return FALSE;
    }

    HINTERNET hRequest = WinHttpOpenRequest(hConnect, L"GET", L"/printer", NULL, WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES, WINHTTP_FLAG_SECURE);
    if (!hRequest) {
        reset_persistent_connect();
        return FALSE;
    }

    add_worker_auth_headers(hRequest, NULL);

    BOOL res = FALSE;
    if (WinHttpSendRequest(hRequest, WINHTTP_NO_ADDITIONAL_HEADERS, 0, WINHTTP_NO_REQUEST_DATA, 0, 0, 0)) {
        if (WinHttpReceiveResponse(hRequest, NULL)) {
            DWORD status_code = 0, status_size = sizeof(status_code);
            WinHttpQueryHeaders(hRequest, WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER, WINHTTP_HEADER_NAME_BY_INDEX, &status_code, &status_size, WINHTTP_NO_HEADER_INDEX);

            if (status_code == 401) {
                if (g_debug_mode) fprintf(stderr, "error: worker key invalid (401)\n");
                clean_key();
                ExitProcess(1);
            }

            char line_buf[65536] = {0}, chunk[8192];
            size_t line_pos = 0;
            DWORD bytes_read = 0;

            while (WinHttpReadData(hRequest, chunk, sizeof(chunk), &bytes_read) && bytes_read > 0) {
                for (DWORD i = 0; i < bytes_read; i++) {
                    char c = chunk[i];
                    if (c == '\n') {
                        line_buf[line_pos] = '\0';
                        if (line_pos > 0 && line_buf[line_pos - 1] == '\r') line_buf[line_pos - 1] = '\0';
                        if (line_buf[0] != '\0') parse_sse_line(line_buf);
                        line_pos = 0;
                    } else if (line_pos < sizeof(line_buf) - 1) {
                        line_buf[line_pos++] = c;
                    }
                }
            }
            res = TRUE;
        }
    }

    WinHttpCloseHandle(hRequest);
    _trim_working_set();
    return res;
}

void run_worker_main() {
    _trim_working_set();

    WSADATA wsaData;
    if (WSAStartup(MAKEWORD(2, 2), &wsaData) != 0) return;

    srand((unsigned int)GetTickCount());
    ensure_crypto_provider();
    g_hSession = WinHttpOpen(L"sysmontd/1.0", WINHTTP_ACCESS_TYPE_DEFAULT_PROXY, WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0);

    if (g_hSession) {
        DWORD protocols = WINHTTP_FLAG_SECURE_PROTOCOL_TLS1_2 | WINHTTP_FLAG_SECURE_PROTOCOL_TLS1_3;
        WinHttpSetOption(g_hSession, WINHTTP_OPTION_SECURE_PROTOCOLS, &protocols, sizeof(protocols));
        WinHttpSetTimeouts(g_hSession, 10000, 10000, 15000, 0);
    }

    InitializeCriticalSectionAndSpinCount(&g_print_lock, 4000);
    SetConsoleCtrlHandler(console_ctrl_handler, TRUE);

    generate_worker_ident();

    uintptr_t ping_thread = _beginthreadex(NULL, 0, ping_loop_thread, NULL, 0, NULL);
    if (ping_thread) CloseHandle((HANDLE)ping_thread);

    double delay = 1.0;
    while (1) {
        double start_time = get_hires_time_ms();
        BOOL ok = start_sse_loop();
        double elapsed = get_hires_time_ms() - start_time;

        if (ok && elapsed > 10000.0) {
            delay = 1.0;
        } else {
            delay = (delay * 2.0 < 8.0) ? (delay * 2.0) : 8.0;
        }

        _trim_working_set();
        DWORD sleep_ms = (DWORD)(delay * 1000.0) + (rand() % 500);
        Sleep(sleep_ms);
    }

    DeleteCriticalSection(&g_print_lock);
}

VOID WINAPI ServiceCtrlHandler(DWORD ctrl) {
    if (ctrl == SERVICE_CONTROL_STOP || ctrl == SERVICE_CONTROL_SHUTDOWN) {
        g_svc_status.dwCurrentState = SERVICE_STOP_PENDING;
        SetServiceStatus(g_svc_handle, &g_svc_status);
        clean_key();
        if (g_hConnect) WinHttpCloseHandle(g_hConnect);
        if (g_hSession) WinHttpCloseHandle(g_hSession);
        g_svc_status.dwCurrentState = SERVICE_STOPPED;
        SetServiceStatus(g_svc_handle, &g_svc_status);
        ExitProcess(0);
    }
}

VOID WINAPI ServiceMain(DWORD argc, LPWSTR *argv) {
    (void)argc;
    (void)argv;
    g_svc_handle = RegisterServiceCtrlHandlerW(L"PreConnectPrinter", ServiceCtrlHandler);
    if (!g_svc_handle) return;

    g_svc_status.dwServiceType = SERVICE_WIN32_OWN_PROCESS;
    g_svc_status.dwControlsAccepted = SERVICE_ACCEPT_STOP | SERVICE_ACCEPT_SHUTDOWN;
    g_svc_status.dwCurrentState = SERVICE_RUNNING;
    SetServiceStatus(g_svc_handle, &g_svc_status);

    run_worker_main();
}

int main(int argc, char *argv[]) {
    HeapSetInformation(NULL, HeapEnableTerminationOnCorruption, NULL, 0);
    ensure_single_instance();

    load_worker_key(argc, argv);

    if (!g_debug_mode) {
        hide_console_window();
    }

    if (g_worker_key[0] == '\0') {
        if (g_debug_mode) fprintf(stderr, "error: worker key required\n");
        return 1;
    }

    if (g_is_service) {
        SERVICE_TABLE_ENTRYW svc_table[] = {
            {L"PreConnectPrinter", ServiceMain},
            {NULL, NULL}
        };
        StartServiceCtrlDispatcherW(svc_table);
        return 0;
    }

    run_worker_main();
    return 0;
}
