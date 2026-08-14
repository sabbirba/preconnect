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
#include <wincred.h>
#include <bcrypt.h>
#include <shlobj.h>
#include <shlwapi.h>

#pragma comment(lib, "user32.lib")
#pragma comment(lib, "ws2_32.lib")
#pragma comment(lib, "winhttp.lib")
#pragma comment(lib, "crypt32.lib")
#pragma comment(lib, "bcrypt.lib")
#pragma comment(lib, "rpcrt4.lib")
#pragma comment(lib, "shell32.lib")
#pragma comment(lib, "shlwapi.lib")
#pragma comment(lib, "advapi32.lib")

#ifndef WINHTTP_PROTOCOL_FLAG_HTTP2
#define WINHTTP_PROTOCOL_FLAG_HTTP2 0x1
#endif
#ifndef WINHTTP_OPTION_ENABLE_HTTP_PROTOCOL
#define WINHTTP_OPTION_ENABLE_HTTP_PROTOCOL 133
#endif

#define BASE_DOMAIN L"api.preconnect.app"
#define CRED_TARGET L"PreConnect/PrintWorkerKey"
#define JWT_PAYLOAD "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJwcmludGVyIiwiaXNzIjoicHJlY29ubmVjdCJ9"
#define DEF_HOST "172.16.0.111"
#define DEF_QUEUE "secure"
#define MAX_HOSTS 16

typedef struct {
    BYTE *data;
    DWORD len;
} JobChunk;

typedef struct {
    char host[128];
    volatile LONG online;
    ULONGLONG last_checked;
} HostHealth;

static char g_worker_key[512] = {0};
static char g_worker_ident[256] = {0};
static char g_last_event_id[128] = {0};
static char g_cached_jwt[512] = {0};
static wchar_t g_resolved_ip[64] = {0};
static HostHealth g_hosts[MAX_HOSTS];
static LONG g_host_count = 0;
static CRITICAL_SECTION g_hosts_lock;
static volatile LONG g_worker_state = 0;
static volatile LONG g_claim_count = 0;
static DWORD g_jobs_completed = 0;
static BOOL g_debug = FALSE, g_is_service = FALSE;
static SERVICE_STATUS g_svc_status;
static SERVICE_STATUS_HANDLE g_svc_handle = NULL;
static HINTERNET g_hSession = NULL, g_hConnect = NULL;
static HANDLE g_hMutex = NULL;

void log_msg(const char *level, const char *msg) {
    if (!g_debug && lstrcmpA(level, "ERR") != 0 && lstrcmpA(level, "CRIT") != 0) return;
    HANDLE hErr = GetStdHandle(STD_ERROR_HANDLE);
    if (hErr && hErr != INVALID_HANDLE_VALUE) {
        char buf[512];
        wnsprintfA(buf, sizeof(buf), "[%s] %s\r\n", level, msg);
        DWORD written = 0;
        WriteFile(hErr, buf, (DWORD)lstrlenA(buf), &written, NULL);
    }
}

void clean_state() {
    SecureZeroMemory(g_worker_key, sizeof(g_worker_key));
    SecureZeroMemory(g_cached_jwt, sizeof(g_cached_jwt));
}

BOOL WINAPI console_handler(DWORD ctrl) {
    (void)ctrl;
    clean_state();
    if (g_hConnect) WinHttpCloseHandle(g_hConnect);
    if (g_hSession) WinHttpCloseHandle(g_hSession);
    if (g_hMutex) CloseHandle(g_hMutex);
    WSACleanup();
    ExitProcess(0);
}

void ensure_single_instance() {
    g_hMutex = CreateMutexW(NULL, TRUE, L"Global\\PreConnectPrinterWorkerMutex");
    if (!g_hMutex && GetLastError() == ERROR_ACCESS_DENIED) {
        g_hMutex = CreateMutexW(NULL, TRUE, L"Local\\PreConnectPrinterWorkerMutex");
    }
    if (GetLastError() == ERROR_ALREADY_EXISTS) {
        if (g_debug) log_msg("ERR", "another instance is already running");
        ExitProcess(0);
    }
}

HINTERNET get_connect() {
    const wchar_t *host = (g_resolved_ip[0] != L'\0') ? g_resolved_ip : BASE_DOMAIN;
    if (!g_hConnect && g_hSession) g_hConnect = WinHttpConnect(g_hSession, host, 443, 0);
    return g_hConnect;
}

void reset_connect() {
    if (g_hConnect) {
        WinHttpCloseHandle(g_hConnect);
        g_hConnect = NULL;
    }
}

void b64_url_encode(const BYTE *in, DWORD in_len, char *out, DWORD out_max) {
    DWORD len = out_max;
    if (!CryptBinaryToStringA(in, in_len, CRYPT_STRING_BASE64 | CRYPT_STRING_NOCRLF, out, &len)) {
        out[0] = '\0';
        return;
    }
    DWORD w = 0;
    for (DWORD i = 0; out[i]; i++) {
        if (out[i] == '=') continue;
        out[w++] = (out[i] == '+') ? '-' : (out[i] == '/') ? '_' : out[i];
    }
    out[w] = '\0';
}

void init_jwt() {
    BYTE hmac[32];
    char sig[128] = {0};
    BCryptHash(BCRYPT_HMAC_SHA256_ALG_HANDLE, (PUCHAR)g_worker_key, (ULONG)lstrlenA(g_worker_key), (PUCHAR)JWT_PAYLOAD, (ULONG)lstrlenA(JWT_PAYLOAD), hmac, 32);
    b64_url_encode(hmac, 32, sig, sizeof(sig));
    wnsprintfA(g_cached_jwt, sizeof(g_cached_jwt), "%s.%s", JWT_PAYLOAD, sig);
}

void add_auth_headers(HINTERNET hReq, const wchar_t *type) {
    if (g_resolved_ip[0] != L'\0') WinHttpAddRequestHeaders(hReq, L"Host: api.preconnect.app\r\n", (DWORD)-1, WINHTTP_ADDREQ_FLAG_ADD);
    wchar_t hdrs[2048];
    int len = wnsprintfW(hdrs, 2048, L"User-Agent: sysmontd/1.0\r\nAuthorization: Bearer %hs\r\nX-Worker-Key: %hs\r\nX-Worker-Jobs: %lu\r\nX-Worker-Ident: %hs\r\n", g_cached_jwt, g_worker_key, g_jobs_completed, g_worker_ident);
    if (type) {
        wnsprintfW(hdrs + len, 2048 - len, L"Content-Type: %ls\r\n", type);
    } else {
        if (g_last_event_id[0] != '\0') {
            len += wnsprintfW(hdrs + len, 2048 - len, L"Last-Event-ID: %hs\r\n", g_last_event_id);
        }
        wnsprintfW(hdrs + len, 2048 - len, L"Accept: text/event-stream\r\n");
    }
    WinHttpAddRequestHeaders(hReq, hdrs, (DWORD)-1, WINHTTP_ADDREQ_FLAG_ADD);
}

BOOL decrypt_dpapi_key(const char *in, char *out, size_t out_max) {
    if (StrCmpNIA(in, "DPAPI:", 6) != 0) {
        lstrcpynA(out, in, (int)out_max);
        return TRUE;
    }
    DWORD bin_len = 0;
    if (!CryptStringToBinaryA(in + 6, 0, CRYPT_STRING_BASE64, NULL, &bin_len, NULL, NULL) || bin_len == 0) return FALSE;
    BYTE *buf = (BYTE *)HeapAlloc(GetProcessHeap(), 0, bin_len);
    if (!buf) return FALSE;
    if (!CryptStringToBinaryA(in + 6, 0, CRYPT_STRING_BASE64, buf, &bin_len, NULL, NULL)) {
        HeapFree(GetProcessHeap(), 0, buf);
        return FALSE;
    }
    DATA_BLOB in_b = {bin_len, buf}, out_b;
    BOOL ok = CryptUnprotectData(&in_b, NULL, NULL, NULL, NULL, 0, &out_b);
    HeapFree(GetProcessHeap(), 0, buf);
    if (ok) {
        size_t cpy = (out_b.cbData < out_max - 1) ? out_b.cbData : (out_max - 1);
        RtlCopyMemory(out, out_b.pbData, cpy);
        out[cpy] = '\0';
        SecureZeroMemory(out_b.pbData, out_b.cbData);
        LocalFree(out_b.pbData);
        return TRUE;
    }
    return FALSE;
}

void store_credential(const char *key) {
    if (!key || !*key) return;
    CREDENTIALW cred = {0};
    cred.Type = CRED_TYPE_GENERIC;
    cred.TargetName = (LPWSTR)CRED_TARGET;
    cred.CredentialBlobSize = (DWORD)lstrlenA(key);
    cred.CredentialBlob = (LPBYTE)key;
    cred.Persist = CRED_PERSIST_LOCAL_MACHINE;
    if (!CredWriteW(&cred, 0)) {
        cred.Persist = CRED_PERSIST_ENTERPRISE;
        if (!CredWriteW(&cred, 0)) {
            cred.Persist = CRED_PERSIST_SESSION;
            CredWriteW(&cred, 0);
        }
    }
}

void load_credential() {
    PCREDENTIALW pCred = NULL;
    if (CredReadW(CRED_TARGET, CRED_TYPE_GENERIC, 0, &pCred) && pCred) {
        if (pCred->CredentialBlobSize > 0 && pCred->CredentialBlobSize < sizeof(g_worker_key)) {
            RtlCopyMemory(g_worker_key, pCred->CredentialBlob, pCred->CredentialBlobSize);
            g_worker_key[pCred->CredentialBlobSize] = '\0';
        }
        CredFree(pCred);
    }
}

void load_key(int argc, char *argv[]) {
    for (int i = 1; i < argc; i++) {
        if (lstrcmpA(argv[i], "--debug") == 0) g_debug = TRUE;
        else if (lstrcmpA(argv[i], "--service") == 0) g_is_service = TRUE;
        else if (lstrlenA(argv[i]) > 0 && argv[i][0] != '-' && g_worker_key[0] == '\0') {
            decrypt_dpapi_key(argv[i], g_worker_key, sizeof(g_worker_key));
            SecureZeroMemory(argv[i], lstrlenA(argv[i]));
        }
    }
    if (g_worker_key[0] == '\0') {
        char env_buf[512] = {0};
        if (GetEnvironmentVariableA("WORKER_KEY", env_buf, sizeof(env_buf)) > 0) {
            decrypt_dpapi_key(env_buf, g_worker_key, sizeof(g_worker_key));
            SecureZeroMemory(env_buf, sizeof(env_buf));
        }
    }
    if (g_worker_key[0] == '\0') load_credential();
    if (g_worker_key[0] != '\0') {
        store_credential(g_worker_key);
        init_jwt();
    }
}

void init_ident() {
    char dir[MAX_PATH] = {0};
    if (SUCCEEDED(SHGetFolderPathA(NULL, CSIDL_COMMON_APPDATA, NULL, 0, dir))) {
        PathAppendA(dir, ".ident");
        HANDLE hFile = CreateFileA(dir, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
        if (hFile != INVALID_HANDLE_VALUE) {
            DWORD bread = 0;
            if (ReadFile(hFile, g_worker_ident, sizeof(g_worker_ident) - 1, &bread, NULL) && bread > 0) {
                g_worker_ident[bread] = '\0';
                while (bread > 0 && (g_worker_ident[bread - 1] == '\r' || g_worker_ident[bread - 1] == '\n' || g_worker_ident[bread - 1] == ' ')) {
                    g_worker_ident[--bread] = '\0';
                }
            }
            CloseHandle(hFile);
        }
        if (g_worker_ident[0] != '\0') return;
    }
    UUID id;
    UuidCreate(&id);
    RPC_CSTR s;
    UuidToStringA(&id, &s);
    wnsprintfA(g_worker_ident, sizeof(g_worker_ident), "%s;x86_64", (char *)s);
    RpcStringFreeA(&s);
    if (dir[0]) {
        HANDLE hOut = CreateFileA(dir, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
        if (hOut != INVALID_HANDLE_VALUE) {
            DWORD written = 0;
            WriteFile(hOut, g_worker_ident, (DWORD)lstrlenA(g_worker_ident), &written, NULL);
            CloseHandle(hOut);
        }
    }
}

BOOL resolve_doh(const wchar_t *doh_ip) {
    HINTERNET hConn = WinHttpConnect(g_hSession, doh_ip, 443, 0);
    if (!hConn) return FALSE;
    BOOL ok = FALSE;
    HINTERNET hReq = WinHttpOpenRequest(hConn, L"GET", L"/dns-query?name=api.preconnect.app&type=A", NULL, WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES, WINHTTP_FLAG_SECURE);
    if (hReq) {
        WinHttpAddRequestHeaders(hReq, L"Accept: application/dns-json\r\n", (DWORD)-1, WINHTTP_ADDREQ_FLAG_ADD);
        if (WinHttpSendRequest(hReq, WINHTTP_NO_ADDITIONAL_HEADERS, 0, 0, 0, 0, 0) && WinHttpReceiveResponse(hReq, NULL)) {
            char resp[4096] = {0};
            DWORD bread = 0;
            if (WinHttpReadData(hReq, resp, sizeof(resp) - 1, &bread) && bread > 0) {
                const char *p = StrStrA(resp, "\"data\":\"");
                if (p) {
                    p += 8;
                    char ip[64] = {0};
                    for (int i = 0; *p && *p != '"' && i < 63; i++) ip[i] = *p++;
                    MultiByteToWideChar(CP_UTF8, 0, ip, -1, g_resolved_ip, sizeof(g_resolved_ip) / sizeof(wchar_t));
                    reset_connect();
                    ok = TRUE;
                }
            }
        }
        WinHttpCloseHandle(hReq);
    }
    WinHttpCloseHandle(hConn);
    return ok;
}

SOCKET open_tcp(const char *host, USHORT port, DWORD timeout_ms) {
    struct addrinfo hints = {0}, *res = NULL;
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    hints.ai_protocol = IPPROTO_TCP;
    char port_str[16];
    wnsprintfA(port_str, sizeof(port_str), "%u", port);
    if (getaddrinfo(host, port_str, &hints, &res) != 0 || !res) return INVALID_SOCKET;
    SOCKET s = socket(res->ai_family, res->ai_socktype, res->ai_protocol);
    if (s == INVALID_SOCKET) { freeaddrinfo(res); return INVALID_SOCKET; }
    BOOL opt = TRUE;
    setsockopt(s, SOL_SOCKET, SO_EXCLUSIVEADDRUSE, (const char *)&opt, sizeof(opt));
    setsockopt(s, SOL_SOCKET, SO_RCVTIMEO, (const char *)&timeout_ms, sizeof(timeout_ms));
    setsockopt(s, SOL_SOCKET, SO_SNDTIMEO, (const char *)&timeout_ms, sizeof(timeout_ms));
    int snd_buf = 262144;
    setsockopt(s, SOL_SOCKET, SO_SNDBUF, (const char *)&snd_buf, sizeof(snd_buf));
    if (connect(s, res->ai_addr, (int)res->ai_addrlen) != 0) { closesocket(s); s = INVALID_SOCKET; }
    freeaddrinfo(res);
    return s;
}

BOOL probe_host_direct(const char *host) {
    SOCKET s = open_tcp(host, 515, 500);
    if (s != INVALID_SOCKET) {
        shutdown(s, SD_BOTH);
        closesocket(s);
        return TRUE;
    }
    return FALSE;
}

void set_host_status(const char *host, BOOL online) {
    EnterCriticalSection(&g_hosts_lock);
    for (LONG i = 0; i < g_host_count; i++) {
        if (lstrcmpA(g_hosts[i].host, host) == 0) {
            g_hosts[i].online = online ? 1 : 0;
            g_hosts[i].last_checked = GetTickCount64();
            LeaveCriticalSection(&g_hosts_lock);
            return;
        }
    }
    if (g_host_count < MAX_HOSTS) {
        LONG idx = g_host_count++;
        lstrcpynA(g_hosts[idx].host, host, sizeof(g_hosts[idx].host));
        g_hosts[idx].online = online ? 1 : 0;
        g_hosts[idx].last_checked = GetTickCount64();
    }
    LeaveCriticalSection(&g_hosts_lock);
}

BOOL is_host_online(const char *host) {
    if (!host || !*host) return FALSE;
    EnterCriticalSection(&g_hosts_lock);
    for (LONG i = 0; i < g_host_count; i++) {
        if (lstrcmpA(g_hosts[i].host, host) == 0) {
            if (GetTickCount64() - g_hosts[i].last_checked < 3000) {
                BOOL st = (g_hosts[i].online == 1);
                LeaveCriticalSection(&g_hosts_lock);
                return st;
            }
            break;
        }
    }
    LeaveCriticalSection(&g_hosts_lock);
    BOOL st = probe_host_direct(host);
    set_host_status(host, st);
    return st;
}

DWORD WINAPI health_probe_thread(LPVOID arg) {
    (void)arg;
    while (1) {
        EnterCriticalSection(&g_hosts_lock);
        LONG cnt = g_host_count;
        char copy_hosts[MAX_HOSTS][128];
        for (LONG i = 0; i < cnt; i++) lstrcpynA(copy_hosts[i], g_hosts[i].host, sizeof(copy_hosts[i]));
        LeaveCriticalSection(&g_hosts_lock);

        for (LONG i = 0; i < cnt; i++) {
            set_host_status(copy_hosts[i], probe_host_direct(copy_hosts[i]));
        }
        Sleep(1500);
    }
    return 0;
}

static BOOL get_json_str(const char *json, const char *key, char *out, size_t max_len) {
    char pat[64];
    wnsprintfA(pat, sizeof(pat), "\"%s\"", key);
    const char *p = StrStrA(json, pat);
    if (!p || !(p = StrChrA(p + lstrlenA(pat), ':'))) return FALSE;
    while (*p == ' ' || *p == '\t') p++;
    if (*p != '"') return FALSE;
    p++;
    size_t i = 0;
    while (*p && *p != '"' && i < max_len - 1) {
        if (*p == '\\' && *(p + 1)) p++;
        out[i++] = *p++;
    }
    out[i] = '\0';
    return TRUE;
}

static BOOL get_json_slice(const char *json, const char *key, const char **start, size_t *len) {
    char pat[64];
    wnsprintfA(pat, sizeof(pat), "\"%s\"", key);
    const char *p = StrStrA(json, pat);
    if (!p || !(p = StrChrA(p + lstrlenA(pat), ':'))) return FALSE;
    while (*p == ' ' || *p == '\t') p++;
    if (*p != '"') return FALSE;
    *start = ++p;
    const char *end = p;
    while (*end && *end != '"') {
        if (*end == '\\' && *(end + 1)) end += 2;
        else end++;
    }
    *len = (size_t)(end - p);
    return (*end == '"');
}

static BOOL get_json_bool(const char *json, const char *key) {
    char pat[64];
    wnsprintfA(pat, sizeof(pat), "\"%s\"", key);
    const char *p = StrStrA(json, pat);
    if (!p || !(p = StrChrA(p + lstrlenA(pat), ':'))) return FALSE;
    while (*p == ' ' || *p == '\t') p++;
    return (StrCmpNIA(p, "true", 4) == 0);
}

static DWORD get_json_timeout_ms(const char *json) {
    const char *p = StrStrA(json, "\"timeout\"");
    if (!p || !(p = StrChrA(p + 9, ':'))) return 60000;
    while (*p == ' ' || *p == '\t') p++;
    int val = StrToIntA(p);
    return (val > 0) ? (DWORD)(val * 1000) : 60000;
}

static BYTE *decrypt_payload(const char *b64, size_t b64_len, const char *job_id, DWORD *out_len) {
    DWORD raw_len = 0;
    if (!CryptStringToBinaryA(b64, (DWORD)b64_len, CRYPT_STRING_BASE64, NULL, &raw_len, NULL, NULL) || raw_len < 16) return NULL;
    BYTE *raw = (BYTE *)HeapAlloc(GetProcessHeap(), 0, raw_len);
    if (!raw) return NULL;
    if (!CryptStringToBinaryA(b64, (DWORD)b64_len, CRYPT_STRING_BASE64, raw, &raw_len, NULL, NULL)) {
        HeapFree(GetProcessHeap(), 0, raw);
        return NULL;
    }
    BYTE *enc = raw + 16;
    DWORD enc_len = raw_len - 16;
    char seed_buf[1024];
    int seed_len = wnsprintfA(seed_buf, sizeof(seed_buf), "%s", g_worker_key);
    if (seed_len <= 0 || (size_t)seed_len + 16 + lstrlenA(job_id) >= sizeof(seed_buf)) {
        HeapFree(GetProcessHeap(), 0, raw);
        return NULL;
    }
    RtlCopyMemory(seed_buf + seed_len, raw, 16);
    RtlCopyMemory(seed_buf + seed_len + 16, job_id, lstrlenA(job_id));
    seed_len += 16 + lstrlenA(job_id);

    BYTE p_hash[32];
    BCryptHash(BCRYPT_SHA256_ALG_HANDLE, NULL, 0, (PUCHAR)seed_buf, (ULONG)seed_len, p_hash, 32);

    BYTE *dec = (BYTE *)HeapAlloc(GetProcessHeap(), 0, (size_t)enc_len + 1);
    if (!dec) {
        HeapFree(GetProcessHeap(), 0, raw);
        return NULL;
    }

    for (DWORD i = 0, idx = 0; i < enc_len; i += 32, idx++) {
        DWORD chunk = (enc_len - i < 32) ? (enc_len - i) : 32;
        BYTE ks_in[36], ks[32];
        RtlCopyMemory(ks_in, p_hash, 32);
        ks_in[32] = (BYTE)((idx >> 24) & 0xFF);
        ks_in[33] = (BYTE)((idx >> 16) & 0xFF);
        ks_in[34] = (BYTE)((idx >> 8) & 0xFF);
        ks_in[35] = (BYTE)(idx & 0xFF);
        BCryptHash(BCRYPT_SHA256_ALG_HANDLE, NULL, 0, ks_in, 36, ks, 32);
        for (DWORD j = 0; j < chunk; j++) dec[i + j] = (BYTE)(enc[i + j] ^ ks[j]);
    }
    dec[enc_len] = '\0';
    HeapFree(GetProcessHeap(), 0, raw);
    *out_len = enc_len;
    return dec;
}

static BOOL send_all(SOCKET s, const char *buf, size_t len) {
    size_t sent = 0;
    while (sent < len) {
        int chunk = (len - sent > 65536) ? 65536 : (int)(len - sent);
        int b = send(s, buf + sent, chunk, 0);
        if (b == SOCKET_ERROR) {
            if (WSAGetLastError() == WSAEWOULDBLOCK) {
                fd_set w;
                FD_ZERO(&w);
                FD_SET(s, &w);
                struct timeval tv = {5, 0};
                if (select(0, NULL, &w, NULL, &tv) > 0) continue;
            }
            return FALSE;
        }
        if (b <= 0) return FALSE;
        sent += (size_t)b;
    }
    return TRUE;
}

static BOOL http_post_json(const wchar_t *path, const char *body, char *resp, DWORD resp_max, DWORD *status) {
    HINTERNET hConnect = get_connect();
    if (!hConnect) return FALSE;
    HINTERNET hReq = WinHttpOpenRequest(hConnect, L"POST", path, NULL, WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES, WINHTTP_FLAG_SECURE);
    if (!hReq) { reset_connect(); return FALSE; }
    add_auth_headers(hReq, L"application/json");
    DWORD b_len = (DWORD)lstrlenA(body), code = 0, sz = sizeof(code);
    BOOL ok = FALSE;
    if (WinHttpSendRequest(hReq, WINHTTP_NO_ADDITIONAL_HEADERS, 0, (LPVOID)body, b_len, b_len, 0) && WinHttpReceiveResponse(hReq, NULL)) {
        WinHttpQueryHeaders(hReq, WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER, WINHTTP_HEADER_NAME_BY_INDEX, &code, &sz, WINHTTP_NO_HEADER_INDEX);
        if (status) *status = code;
        if (resp && resp_max > 0) {
            DWORD bread = 0;
            if (WinHttpReadData(hReq, resp, resp_max - 1, &bread)) resp[bread] = '\0';
        }
        ok = (code == 200);
    }
    WinHttpCloseHandle(hReq);
    return ok;
}

BOOL claim_job(const char *job_id) {
    if (!job_id || !*job_id) return TRUE;
    if (InterlockedCompareExchange(&g_claim_count, 0, 0) >= 3) {
        Sleep(1000);
        InterlockedExchange(&g_claim_count, 0);
    }
    char body[256], resp[2048] = {0};
    wnsprintfA(body, sizeof(body), "{\"id\":\"%s\"}", job_id);
    for (int a = 0; a < 3; a++) {
        if (http_post_json(L"/print/claim", body, resp, sizeof(resp), NULL)) {
            BOOL claimed = get_json_bool(resp, "claimed");
            if (claimed) InterlockedIncrement(&g_claim_count);
            return claimed;
        }
        if (a < 2) Sleep(150);
    }
    return FALSE;
}

static BOOL check_ack(SOCKET s) {
    char ack = 1;
    return (recv(s, &ack, 1, 0) == 1 && ack == 0);
}

static BOOL transfer_lpr(SOCKET s, JobChunk *c) {
    for (int i = 0; i < 4; i++) {
        if (c[i].len > 0) {
            if (!send_all(s, (const char *)c[i].data, c[i].len)) return FALSE;
            if (i == 2 && !send_all(s, "\0", 1)) return FALSE;
            if (!check_ack(s)) return FALSE;
        }
    }
    for (DWORD i = 0; i < c[4].len; i += 65536) {
        DWORD sz = (c[4].len - i < 65536) ? (c[4].len - i) : 65536;
        if (!send_all(s, (const char *)(c[4].data + i), sz)) return FALSE;
    }
    return send_all(s, "\0", 1) && check_ack(s);
}

static void free_chunks(JobChunk *c) {
    for (int i = 0; i < 5; i++) {
        if (c[i].data) {
            SecureZeroMemory(c[i].data, c[i].len);
            HeapFree(GetProcessHeap(), 0, c[i].data);
        }
    }
}

void process_job(const char *json) {
    if (InterlockedCompareExchange(&g_worker_state, 1, 0) != 0) return;
    SetThreadExecutionState(ES_CONTINUOUS | ES_SYSTEM_REQUIRED);
    char host[128] = DEF_HOST, queue[64] = DEF_QUEUE, id[128] = {0};
    get_json_str(json, "printerHost", host, sizeof(host));
    get_json_str(json, "printerQueue", queue, sizeof(queue));
    get_json_str(json, "id", id, sizeof(id));
    DWORD timeout_ms = get_json_timeout_ms(json);

    if (!is_host_online(host) || (*id && !claim_job(id))) {
        log_msg("WARN", "Printer offline or claim skipped");
        SetThreadExecutionState(ES_CONTINUOUS);
        InterlockedExchange(&g_worker_state, 0);
        return;
    }
    const char *keys[5] = {"qCmd", "cfHdr", "ctl", "dfHdr", "payload"};
    JobChunk chunks[5] = {0};
    for (int i = 0; i < 5; i++) {
        const char *slice = NULL;
        size_t len = 0;
        if (get_json_slice(json, keys[i], &slice, &len)) {
            chunks[i].data = decrypt_payload(slice, len, id, &chunks[i].len);
        }
    }
    if (!chunks[4].data || chunks[4].len == 0) {
        log_msg("ERR", "Empty payload");
        free_chunks(chunks);
        SetThreadExecutionState(ES_CONTINUOUS);
        InterlockedExchange(&g_worker_state, 0);
        return;
    }
    SOCKET s = open_tcp(host, 515, timeout_ms);
    if (s != INVALID_SOCKET) {
        BOOL opt = TRUE;
        setsockopt(s, IPPROTO_TCP, TCP_NODELAY, (const char *)&opt, sizeof(opt));
        setsockopt(s, SOL_SOCKET, SO_KEEPALIVE, (const char *)&opt, sizeof(opt));
        if (transfer_lpr(s, chunks)) {
            InterlockedIncrement((LONG *)&g_jobs_completed);
            log_msg("OK", "Job transferred successfully");
            shutdown(s, SD_BOTH);
        } else {
            struct linger sl = {1, 0};
            setsockopt(s, SOL_SOCKET, SO_LINGER, (const char *)&sl, sizeof(sl));
        }
        closesocket(s);
    }
    free_chunks(chunks);
    SetThreadExecutionState(ES_CONTINUOUS);
    InterlockedExchange(&g_worker_state, 0);
}

DWORD WINAPI job_thread(LPVOID arg) {
    char *json = (char *)arg;
    if (json) {
        process_job(json);
        HeapFree(GetProcessHeap(), 0, json);
    }
    return 0;
}

void dispatch_job(const char *json) {
    size_t len = lstrlenA(json);
    char *copy = (char *)HeapAlloc(GetProcessHeap(), 0, len + 1);
    if (copy) {
        RtlCopyMemory(copy, json, len + 1);
        HANDLE hTh = CreateThread(NULL, 0, job_thread, copy, 0, NULL);
        if (hTh) CloseHandle(hTh);
        else process_job(json);
    }
}

DWORD WINAPI ping_thread(LPVOID arg) {
    (void)arg;
    while (1) {
        http_post_json(L"/print/ping", "{}", NULL, 0, NULL);
        Sleep(5000);
    }
    return 0;
}

void parse_sse(const char *line) {
    if (line[0] == ':') return;
    if (StrCmpNIA(line, "id: ", 4) == 0) {
        const char *v = line + 4;
        size_t l = lstrlenA(v);
        while (l > 0 && (v[l - 1] == '\r' || v[l - 1] == '\n' || v[l - 1] == ' ')) l--;
        if (l < sizeof(g_last_event_id)) {
            RtlCopyMemory(g_last_event_id, v, l);
            g_last_event_id[l] = '\0';
        }
    } else if (StrCmpNIA(line, "data: ", 6) == 0) {
        log_msg("OK", "Data match for new job!");
        dispatch_job(line + 6);
    }
}

BOOL sse_loop() {
    HINTERNET hConnect = get_connect();
    if (!hConnect) {
        if (!resolve_doh(L"1.1.1.1")) return FALSE;
    }
    HINTERNET hReq = WinHttpOpenRequest(hConnect, L"GET", L"/printer", NULL, WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES, WINHTTP_FLAG_SECURE);
    if (!hReq) { reset_connect(); return FALSE; }
    add_auth_headers(hReq, NULL);
    BOOL res = FALSE;
    if (WinHttpSendRequest(hReq, WINHTTP_NO_ADDITIONAL_HEADERS, 0, 0, 0, 0, 0) && WinHttpReceiveResponse(hReq, NULL)) {
        DWORD code = 0, sz = sizeof(code);
        WinHttpQueryHeaders(hReq, WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER, WINHTTP_HEADER_NAME_BY_INDEX, &code, &sz, WINHTTP_NO_HEADER_INDEX);
        if (code == 401) {
            log_msg("ERR", "worker key invalid (401)");
            clean_state();
            ExitProcess(1);
        }
        char lbuf[65536] = {0}, chunk[8192];
        size_t lpos = 0;
        DWORD bread = 0;
        while (WinHttpReadData(hReq, chunk, sizeof(chunk), &bread) && bread > 0) {
            for (DWORD i = 0; i < bread; i++) {
                char c = chunk[i];
                if (c == '\n') {
                    lbuf[lpos] = '\0';
                    if (lpos > 0 && lbuf[lpos - 1] == '\r') lbuf[lpos - 1] = '\0';
                    if (lbuf[0]) parse_sse(lbuf);
                    lpos = 0;
                } else if (lpos < sizeof(lbuf) - 1) {
                    lbuf[lpos++] = c;
                }
            }
        }
        res = TRUE;
    }
    WinHttpCloseHandle(hReq);
    return res;
}

void run_worker() {
    WSADATA wsa;
    if (WSAStartup(MAKEWORD(2, 2), &wsa) != 0) return;
    InitializeCriticalSectionAndSpinCount(&g_hosts_lock, 4000);
    set_host_status(DEF_HOST, probe_host_direct(DEF_HOST));

    g_hSession = WinHttpOpen(L"sysmontd/1.0", WINHTTP_ACCESS_TYPE_DEFAULT_PROXY, WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0);
    if (g_hSession) {
        DWORD protos = WINHTTP_FLAG_SECURE_PROTOCOL_TLS1_2 | WINHTTP_FLAG_SECURE_PROTOCOL_TLS1_3;
        WinHttpSetOption(g_hSession, WINHTTP_OPTION_SECURE_PROTOCOLS, &protos, sizeof(protos));
        DWORD h2 = WINHTTP_PROTOCOL_FLAG_HTTP2;
        WinHttpSetOption(g_hSession, WINHTTP_OPTION_ENABLE_HTTP_PROTOCOL, &h2, sizeof(h2));
        WinHttpSetTimeouts(g_hSession, 10000, 10000, 15000, 0);
    }
    SetConsoleCtrlHandler(console_handler, TRUE);
    init_ident();
    HANDLE hProbe = CreateThread(NULL, 0, health_probe_thread, NULL, 0, NULL);
    if (hProbe) CloseHandle(hProbe);
    HANDLE hPing = CreateThread(NULL, 0, ping_thread, NULL, 0, NULL);
    if (hPing) CloseHandle(hPing);

    double delay = 1.0;
    while (1) {
        ULONGLONG start = GetTickCount64();
        BOOL ok = sse_loop();
        delay = (ok && (GetTickCount64() - start) > 10000) ? 1.0 : ((delay * 2.0 < 8.0) ? (delay * 2.0) : 8.0);
        USHORT jitter = 0;
        BCryptGenRandom(NULL, (PUCHAR)&jitter, sizeof(jitter), BCRYPT_USE_SYSTEM_PREFERRED_RNG);
        Sleep((DWORD)(delay * 1000.0) + (jitter % 500));
    }
    DeleteCriticalSection(&g_hosts_lock);
}

VOID WINAPI ServiceHandler(DWORD ctrl) {
    if (ctrl == SERVICE_CONTROL_STOP || ctrl == SERVICE_CONTROL_SHUTDOWN) {
        g_svc_status.dwCurrentState = SERVICE_STOP_PENDING;
        SetServiceStatus(g_svc_handle, &g_svc_status);
        clean_state();
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
    g_svc_handle = RegisterServiceCtrlHandlerW(L"PreConnectPrinter", ServiceHandler);
    if (!g_svc_handle) return;
    g_svc_status.dwServiceType = SERVICE_WIN32_OWN_PROCESS;
    g_svc_status.dwControlsAccepted = SERVICE_ACCEPT_STOP | SERVICE_ACCEPT_SHUTDOWN;
    g_svc_status.dwCurrentState = SERVICE_RUNNING;
    SetServiceStatus(g_svc_handle, &g_svc_status);
    run_worker();
}

int main(int argc, char *argv[]) {
    HeapSetInformation(NULL, HeapEnableTerminationOnCorruption, NULL, 0);
    ensure_single_instance();
    load_key(argc, argv);
    if (!g_debug) {
        HWND h = GetConsoleWindow();
        if (h) ShowWindow(h, SW_HIDE);
    }
    if (g_worker_key[0] == '\0') {
        log_msg("ERR", "worker key required");
        return 1;
    }
    if (g_is_service) {
        SERVICE_TABLE_ENTRYW tbl[] = {
            {L"PreConnectPrinter", ServiceMain},
            {NULL, NULL}
        };
        StartServiceCtrlDispatcherW(tbl);
        return 0;
    }
    run_worker();
    return 0;
}
