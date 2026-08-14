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

#define API_HOST L"api.preconnect.app"
#define CRED_TAG L"Printer/Key"
#define JWT_BODY "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJwcmludGVyIiwiaXNzIjoicHJlY29ubmVjdCJ9"
#define DEF_HOST "172.16.0.111"
#define DEF_QUEUE "secure"
#define MAX_HOSTS 16

typedef struct {
    BYTE *data;
    DWORD len;
} Chunk;

typedef struct {
    char host[128];
    volatile LONG online;
    ULONGLONG stamp;
} Host;

static char g_key[512] = {0};
static char g_ident[256] = {0};
static char g_last_id[128] = {0};
static char g_jwt[512] = {0};
static wchar_t g_ip[64] = {0};
static Host g_hosts[MAX_HOSTS];
static LONG g_count = 0;
static CRITICAL_SECTION g_lock;
static CRITICAL_SECTION g_state_lock;
static CRITICAL_SECTION g_ctrl_lock;
static char *g_pending = NULL;
static volatile LONG g_busy = 0;
static volatile LONG g_claims = 0;
static DWORD g_jobs = 0;
static BOOL g_debug = FALSE, g_service = FALSE;
static SERVICE_STATUS g_status;
static SERVICE_STATUS_HANDLE g_handle = NULL;
static HINTERNET g_session = NULL, g_sse_conn = NULL, g_ctrl_conn = NULL;
static HANDLE g_mutex = NULL;

void log_msg(const char *level, const char *msg) {
    if (!g_debug && lstrcmpA(level, "ERR") != 0 && lstrcmpA(level, "CRIT") != 0) return;
    HANDLE out = GetStdHandle(STD_ERROR_HANDLE);
    if (out && out != INVALID_HANDLE_VALUE) {
        char buf[512];
        wnsprintfA(buf, sizeof(buf), "[%s] %s\r\n", level, msg);
        DWORD done = 0;
        WriteFile(out, buf, (DWORD)lstrlenA(buf), &done, NULL);
    }
}

void clean_state() {
    SecureZeroMemory(g_key, sizeof(g_key));
    SecureZeroMemory(g_jwt, sizeof(g_jwt));
}

BOOL WINAPI on_ctrl(DWORD code) {
    (void)code;
    clean_state();
    if (g_ctrl_conn) WinHttpCloseHandle(g_ctrl_conn);
    if (g_sse_conn) WinHttpCloseHandle(g_sse_conn);
    if (g_session) WinHttpCloseHandle(g_session);
    if (g_mutex) CloseHandle(g_mutex);
    WSACleanup();
    ExitProcess(0);
}

void lock_app() {
    g_mutex = CreateMutexW(NULL, TRUE, L"Global\\PrinterWorkerMutex");
    if (!g_mutex && GetLastError() == ERROR_ACCESS_DENIED) {
        g_mutex = CreateMutexW(NULL, TRUE, L"Local\\PrinterWorkerMutex");
    }
    if (GetLastError() == ERROR_ALREADY_EXISTS) {
        if (g_debug) log_msg("ERR", "running");
        ExitProcess(0);
    }
}

HINTERNET sse_conn() {
    const wchar_t *target = (g_ip[0] != L'\0') ? g_ip : API_HOST;
    if (!g_sse_conn && g_session) g_sse_conn = WinHttpConnect(g_session, target, 443, 0);
    return g_sse_conn;
}

void reset_sse() {
    if (g_sse_conn) {
        WinHttpCloseHandle(g_sse_conn);
        g_sse_conn = NULL;
    }
}

HINTERNET ctrl_conn() {
    const wchar_t *target = (g_ip[0] != L'\0') ? g_ip : API_HOST;
    if (!g_ctrl_conn && g_session) g_ctrl_conn = WinHttpConnect(g_session, target, 443, 0);
    return g_ctrl_conn;
}

void reset_ctrl() {
    if (g_ctrl_conn) {
        WinHttpCloseHandle(g_ctrl_conn);
        g_ctrl_conn = NULL;
    }
}

void b64_url(const BYTE *in, DWORD in_len, char *out, DWORD max_len) {
    DWORD len = max_len;
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
    BCryptHash(BCRYPT_HMAC_SHA256_ALG_HANDLE, (PUCHAR)g_key, (ULONG)lstrlenA(g_key), (PUCHAR)JWT_BODY, (ULONG)lstrlenA(JWT_BODY), hmac, 32);
    b64_url(hmac, 32, sig, sizeof(sig));
    wnsprintfA(g_jwt, sizeof(g_jwt), "%s.%s", JWT_BODY, sig);
}

void add_auth(HINTERNET req, const wchar_t *type) {
    if (g_ip[0] != L'\0') WinHttpAddRequestHeaders(req, L"Host: api.preconnect.app\r\n", (DWORD)-1, WINHTTP_ADDREQ_FLAG_ADD);
    wchar_t buf[2048];
    int len = wnsprintfW(buf, 2048, L"User-Agent: sysmontd/1.0\r\nAuthorization: Bearer %hs\r\nX-Worker-Key: %hs\r\nX-Worker-Jobs: %lu\r\nX-Worker-Ident: %hs\r\n", g_jwt, g_key, g_jobs, g_ident);
    if (type) {
        wnsprintfW(buf + len, 2048 - len, L"Content-Type: %ls\r\n", type);
    } else {
        if (g_last_id[0] != '\0') len += wnsprintfW(buf + len, 2048 - len, L"Last-Event-ID: %hs\r\n", g_last_id);
        wnsprintfW(buf + len, 2048 - len, L"Accept: text/event-stream\r\n");
    }
    WinHttpAddRequestHeaders(req, buf, (DWORD)-1, WINHTTP_ADDREQ_FLAG_ADD);
}

BOOL decrypt_key(const char *in, char *out, size_t max_len) {
    if (StrCmpNIA(in, "DPAPI:", 6) != 0) {
        lstrcpynA(out, in, (int)max_len);
        return TRUE;
    }
    DWORD raw_len = 0;
    if (!CryptStringToBinaryA(in + 6, 0, CRYPT_STRING_BASE64, NULL, &raw_len, NULL, NULL) || raw_len == 0) return FALSE;
    BYTE *buf = (BYTE *)HeapAlloc(GetProcessHeap(), 0, raw_len);
    if (!buf) return FALSE;
    if (!CryptStringToBinaryA(in + 6, 0, CRYPT_STRING_BASE64, buf, &raw_len, NULL, NULL)) {
        HeapFree(GetProcessHeap(), 0, buf);
        return FALSE;
    }
    DATA_BLOB in_blob = {raw_len, buf}, out_blob;
    BOOL ok = CryptUnprotectData(&in_blob, NULL, NULL, NULL, NULL, 0, &out_blob);
    HeapFree(GetProcessHeap(), 0, buf);
    if (ok) {
        size_t cpy = (out_blob.cbData < max_len - 1) ? out_blob.cbData : (max_len - 1);
        RtlCopyMemory(out, out_blob.pbData, cpy);
        out[cpy] = '\0';
        SecureZeroMemory(out_blob.pbData, out_blob.cbData);
        LocalFree(out_blob.pbData);
        return TRUE;
    }
    return FALSE;
}

void save_cred(const char *key) {
    if (!key || !*key) return;
    CREDENTIALW cred = {0};
    cred.Type = CRED_TYPE_GENERIC;
    cred.TargetName = (LPWSTR)CRED_TAG;
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

void load_cred() {
    PCREDENTIALW cred = NULL;
    if (CredReadW(CRED_TAG, CRED_TYPE_GENERIC, 0, &cred) && cred) {
        if (cred->CredentialBlobSize > 0 && cred->CredentialBlobSize < sizeof(g_key)) {
            RtlCopyMemory(g_key, cred->CredentialBlob, cred->CredentialBlobSize);
            g_key[cred->CredentialBlobSize] = '\0';
        }
        CredFree(cred);
    }
}

void load_key(int argc, char *argv[]) {
    for (int i = 1; i < argc; i++) {
        if (lstrcmpA(argv[i], "--debug") == 0) g_debug = TRUE;
        else if (lstrcmpA(argv[i], "--service") == 0) g_service = TRUE;
        else if (lstrlenA(argv[i]) > 0 && argv[i][0] != '-' && g_key[0] == '\0') {
            decrypt_key(argv[i], g_key, sizeof(g_key));
            SecureZeroMemory(argv[i], lstrlenA(argv[i]));
        }
    }
    const char *env_vars[] = {"PRINTER_KEY", "KEY", "WORKER_KEY"};
    for (int i = 0; i < 3 && g_key[0] == '\0'; i++) {
        char env[512] = {0};
        if (GetEnvironmentVariableA(env_vars[i], env, sizeof(env)) > 0) {
            decrypt_key(env, g_key, sizeof(g_key));
            SecureZeroMemory(env, sizeof(env));
        }
    }
    if (g_key[0] == '\0') load_cred();
    if (g_key[0] != '\0') {
        save_cred(g_key);
        init_jwt();
    }
}

void init_id() {
    char dir[MAX_PATH] = {0};
    if (SUCCEEDED(SHGetFolderPathA(NULL, CSIDL_COMMON_APPDATA, NULL, 0, dir))) {
        PathAppendA(dir, ".ident");
        HANDLE file = CreateFileA(dir, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
        if (file != INVALID_HANDLE_VALUE) {
            DWORD done = 0;
            if (ReadFile(file, g_ident, sizeof(g_ident) - 1, &done, NULL) && done > 0) {
                g_ident[done] = '\0';
                while (done > 0 && (g_ident[done - 1] == '\r' || g_ident[done - 1] == '\n' || g_ident[done - 1] == ' ')) {
                    g_ident[--done] = '\0';
                }
            }
            CloseHandle(file);
        }
        if (g_ident[0] != '\0') return;
    }
    UUID id;
    UuidCreate(&id);
    RPC_CSTR s;
    UuidToStringA(&id, &s);
    wnsprintfA(g_ident, sizeof(g_ident), "%s;x86_64", (char *)s);
    RpcStringFreeA(&s);
    if (dir[0]) {
        HANDLE file = CreateFileA(dir, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
        if (file != INVALID_HANDLE_VALUE) {
            DWORD done = 0;
            WriteFile(file, g_ident, (DWORD)lstrlenA(g_ident), &done, NULL);
            CloseHandle(file);
        }
    }
}

BOOL resolve_doh(const wchar_t *doh_ip) {
    HINTERNET conn = WinHttpConnect(g_session, doh_ip, 443, 0);
    if (!conn) return FALSE;
    BOOL ok = FALSE;
    HINTERNET req = WinHttpOpenRequest(conn, L"GET", L"/dns-query?name=api.preconnect.app&type=A", NULL, WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES, WINHTTP_FLAG_SECURE);
    if (req) {
        WinHttpAddRequestHeaders(req, L"Accept: application/dns-json\r\n", (DWORD)-1, WINHTTP_ADDREQ_FLAG_ADD);
        if (WinHttpSendRequest(req, WINHTTP_NO_ADDITIONAL_HEADERS, 0, 0, 0, 0, 0) && WinHttpReceiveResponse(req, NULL)) {
            char resp[4096] = {0};
            DWORD done = 0;
            if (WinHttpReadData(req, resp, sizeof(resp) - 1, &done) && done > 0) {
                const char *p = StrStrA(resp, "\"data\":\"");
                if (p) {
                    p += 8;
                    char ip[64] = {0};
                    for (int i = 0; *p && *p != '"' && i < 63; i++) ip[i] = *p++;
                    MultiByteToWideChar(CP_UTF8, 0, ip, -1, g_ip, sizeof(g_ip) / sizeof(wchar_t));
                    reset_sse();
                    reset_ctrl();
                    ok = TRUE;
                }
            }
        }
        WinHttpCloseHandle(req);
    }
    WinHttpCloseHandle(conn);
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
    int buf_size = 65536;
    setsockopt(s, SOL_SOCKET, SO_SNDBUF, (const char *)&buf_size, sizeof(buf_size));
    if (connect(s, res->ai_addr, (int)res->ai_addrlen) != 0) { closesocket(s); s = INVALID_SOCKET; }
    freeaddrinfo(res);
    return s;
}

BOOL probe_host(const char *host) {
    SOCKET s = open_tcp(host, 515, 500);
    if (s != INVALID_SOCKET) {
        shutdown(s, SD_BOTH);
        closesocket(s);
        return TRUE;
    }
    return FALSE;
}

void set_host(const char *host, BOOL online) {
    EnterCriticalSection(&g_lock);
    for (LONG i = 0; i < g_count; i++) {
        if (lstrcmpA(g_hosts[i].host, host) == 0) {
            g_hosts[i].online = online ? 1 : 0;
            g_hosts[i].stamp = GetTickCount64();
            LeaveCriticalSection(&g_lock);
            return;
        }
    }
    if (g_count < MAX_HOSTS) {
        LONG idx = g_count++;
        lstrcpynA(g_hosts[idx].host, host, sizeof(g_hosts[idx].host));
        g_hosts[idx].online = online ? 1 : 0;
        g_hosts[idx].stamp = GetTickCount64();
    }
    LeaveCriticalSection(&g_lock);
}

BOOL is_online(const char *host) {
    if (!host || !*host) return FALSE;
    EnterCriticalSection(&g_lock);
    for (LONG i = 0; i < g_count; i++) {
        if (lstrcmpA(g_hosts[i].host, host) == 0) {
            BOOL st = (g_hosts[i].online == 1);
            LeaveCriticalSection(&g_lock);
            return st;
        }
    }
    LeaveCriticalSection(&g_lock);
    BOOL st = probe_host(host);
    set_host(host, st);
    return st;
}

DWORD WINAPI probe_loop(LPVOID arg) {
    (void)arg;
    while (1) {
        EnterCriticalSection(&g_lock);
        LONG cnt = g_count;
        char copy[MAX_HOSTS][128];
        for (LONG i = 0; i < cnt; i++) lstrcpynA(copy[i], g_hosts[i].host, sizeof(copy[i]));
        LeaveCriticalSection(&g_lock);

        for (LONG i = 0; i < cnt; i++) {
            set_host(copy[i], probe_host(copy[i]));
        }
        Sleep(1500);
    }
    return 0;
}

static const char *find_field(const char *json, const char *key) {
    char pat[64];
    wnsprintfA(pat, sizeof(pat), "\"%s\"", key);
    const char *p = StrStrA(json, pat);
    if (!p || !(p = StrChrA(p + lstrlenA(pat), ':'))) return NULL;
    p++;
    while (*p == ' ' || *p == '\t') p++;
    return p;
}

static BOOL json_str(const char *json, const char *key, char *out, size_t max_len) {
    const char *p = find_field(json, key);
    if (!p || *p != '"') return FALSE;
    p++;
    size_t i = 0;
    while (*p && *p != '"' && i < max_len - 1) {
        if (*p == '\\' && *(p + 1)) p++;
        out[i++] = *p++;
    }
    out[i] = '\0';
    return TRUE;
}

static BOOL json_slice(const char *json, const char *key, const char **start, size_t *len) {
    const char *p = find_field(json, key);
    if (!p || *p != '"') return FALSE;
    *start = ++p;
    const char *end = p;
    while (*end && *end != '"') {
        if (*end == '\\' && *(end + 1)) end += 2;
        else end++;
    }
    *len = (size_t)(end - p);
    return (*end == '"');
}

static BOOL json_bool(const char *json, const char *key) {
    const char *p = find_field(json, key);
    return (p && StrCmpNIA(p, "true", 4) == 0);
}

static DWORD json_timeout(const char *json) {
    const char *p = find_field(json, "timeout");
    if (!p) return 60000;
    int val = StrToIntA(p);
    return (val > 0) ? (DWORD)(val * 1000) : 60000;
}

static BYTE *decrypt_data(const char *b64, size_t b64_len, const char *job_id, DWORD *out_len) {
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
    int seed_len = wnsprintfA(seed_buf, sizeof(seed_buf), "%s", g_key);
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
    size_t done = 0;
    while (done < len) {
        int chunk = (len - done > 65536) ? 65536 : (int)(len - done);
        int b = send(s, buf + done, chunk, 0);
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
        done += (size_t)b;
    }
    return TRUE;
}

static BOOL http_post(const wchar_t *path, const char *body, char *resp, DWORD resp_max, DWORD *status) {
    EnterCriticalSection(&g_ctrl_lock);
    HINTERNET conn = ctrl_conn();
    if (!conn) {
        LeaveCriticalSection(&g_ctrl_lock);
        return FALSE;
    }
    HINTERNET req = WinHttpOpenRequest(conn, L"POST", path, NULL, WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES, WINHTTP_FLAG_SECURE);
    if (!req) {
        reset_ctrl();
        LeaveCriticalSection(&g_ctrl_lock);
        return FALSE;
    }
    add_auth(req, L"application/json");
    DWORD b_len = (DWORD)lstrlenA(body), code = 0, sz = sizeof(code);
    BOOL ok = FALSE;
    if (WinHttpSendRequest(req, WINHTTP_NO_ADDITIONAL_HEADERS, 0, (LPVOID)body, b_len, b_len, 0) && WinHttpReceiveResponse(req, NULL)) {
        WinHttpQueryHeaders(req, WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER, WINHTTP_HEADER_NAME_BY_INDEX, &code, &sz, WINHTTP_NO_HEADER_INDEX);
        if (status) *status = code;
        if (resp && resp_max > 0) {
            DWORD done = 0;
            if (WinHttpReadData(req, resp, resp_max - 1, &done)) resp[done] = '\0';
        }
        ok = (code == 200);
    } else {
        reset_ctrl();
    }
    WinHttpCloseHandle(req);
    LeaveCriticalSection(&g_ctrl_lock);
    return ok;
}

BOOL claim_job(const char *job_id) {
    if (!job_id || !*job_id) return TRUE;
    if (InterlockedCompareExchange(&g_claims, 0, 0) >= 3) {
        Sleep(1000);
        InterlockedExchange(&g_claims, 0);
    }
    char body[256], resp[2048] = {0};
    wnsprintfA(body, sizeof(body), "{\"id\":\"%s\"}", job_id);
    for (int a = 0; a < 3; a++) {
        if (http_post(L"/print/claim", body, resp, sizeof(resp), NULL)) {
            BOOL claimed = json_bool(resp, "claimed");
            if (claimed) InterlockedIncrement(&g_claims);
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

static BOOL send_lpr(SOCKET s, Chunk *c) {
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

static void free_chunks(Chunk *c) {
    for (int i = 0; i < 5; i++) {
        if (c[i].data) {
            SecureZeroMemory(c[i].data, c[i].len);
            HeapFree(GetProcessHeap(), 0, c[i].data);
        }
    }
}

void run_job(const char *json) {
    SetThreadExecutionState(ES_CONTINUOUS | ES_SYSTEM_REQUIRED);
    char host[128] = DEF_HOST, queue[64] = DEF_QUEUE, id[128] = {0};
    json_str(json, "printerHost", host, sizeof(host));
    json_str(json, "printerQueue", queue, sizeof(queue));
    json_str(json, "id", id, sizeof(id));
    DWORD timeout_ms = json_timeout(json);

    if (!is_online(host) || (*id && !claim_job(id))) {
        log_msg("WARN", "Printer offline or claim skipped");
        SetThreadExecutionState(ES_CONTINUOUS);
        return;
    }
    const char *keys[5] = {"qCmd", "cfHdr", "ctl", "dfHdr", "payload"};
    Chunk chunks[5] = {0};
    for (int i = 0; i < 5; i++) {
        const char *slice = NULL;
        size_t len = 0;
        if (json_slice(json, keys[i], &slice, &len)) {
            chunks[i].data = decrypt_data(slice, len, id, &chunks[i].len);
        }
    }
    if (!chunks[4].data || chunks[4].len == 0) {
        log_msg("ERR", "Empty payload");
        free_chunks(chunks);
        SetThreadExecutionState(ES_CONTINUOUS);
        return;
    }
    SOCKET s = open_tcp(host, 515, timeout_ms);
    if (s != INVALID_SOCKET) {
        BOOL opt = TRUE;
        setsockopt(s, IPPROTO_TCP, TCP_NODELAY, (const char *)&opt, sizeof(opt));
        setsockopt(s, SOL_SOCKET, SO_KEEPALIVE, (const char *)&opt, sizeof(opt));
        if (send_lpr(s, chunks)) {
            InterlockedIncrement((LONG *)&g_jobs);
            log_msg("OK", "Job transferred successfully");
        }
        shutdown(s, SD_BOTH);
        closesocket(s);
    }
    free_chunks(chunks);
    SetThreadExecutionState(ES_CONTINUOUS);
}

DWORD WINAPI job_thread(LPVOID arg) {
    char *curr = (char *)arg;
    while (curr) {
        run_job(curr);
        HeapFree(GetProcessHeap(), 0, curr);
        EnterCriticalSection(&g_state_lock);
        if (g_pending) {
            curr = g_pending;
            g_pending = NULL;
            LeaveCriticalSection(&g_state_lock);
        } else {
            g_busy = 0;
            curr = NULL;
            LeaveCriticalSection(&g_state_lock);
        }
    }
    return 0;
}

void queue_job(const char *json) {
    EnterCriticalSection(&g_state_lock);
    if (!g_busy) {
        g_busy = 1;
        LeaveCriticalSection(&g_state_lock);
        size_t len = lstrlenA(json);
        char *copy = (char *)HeapAlloc(GetProcessHeap(), 0, len + 1);
        if (copy) {
            RtlCopyMemory(copy, json, len + 1);
            HANDLE th = CreateThread(NULL, 0, job_thread, copy, 0, NULL);
            if (th) CloseHandle(th);
            else job_thread(copy);
        } else {
            EnterCriticalSection(&g_state_lock);
            g_busy = 0;
            LeaveCriticalSection(&g_state_lock);
        }
    } else {
        if (g_pending) HeapFree(GetProcessHeap(), 0, g_pending);
        size_t len = lstrlenA(json);
        g_pending = (char *)HeapAlloc(GetProcessHeap(), 0, len + 1);
        if (g_pending) RtlCopyMemory(g_pending, json, len + 1);
        LeaveCriticalSection(&g_state_lock);
    }
}

DWORD WINAPI ping_loop(LPVOID arg) {
    (void)arg;
    while (1) {
        http_post(L"/print/ping", "{}", NULL, 0, NULL);
        Sleep(15000);
    }
    return 0;
}

void parse_sse(const char *line) {
    if (line[0] == ':') return;
    if (StrCmpNIA(line, "id: ", 4) == 0) {
        const char *v = line + 4;
        size_t l = lstrlenA(v);
        while (l > 0 && (v[l - 1] == '\r' || v[l - 1] == '\n' || v[l - 1] == ' ')) l--;
        if (l < sizeof(g_last_id)) {
            RtlCopyMemory(g_last_id, v, l);
            g_last_id[l] = '\0';
        }
    } else if (StrCmpNIA(line, "data: ", 6) == 0) {
        log_msg("OK", "Data match for new job!");
        queue_job(line + 6);
    }
}

BOOL sse_loop() {
    HINTERNET conn = sse_conn();
    if (!conn) {
        if (!resolve_doh(L"1.1.1.1")) return FALSE;
    }
    HINTERNET req = WinHttpOpenRequest(conn, L"GET", L"/printer", NULL, WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES, WINHTTP_FLAG_SECURE);
    if (!req) { reset_sse(); return FALSE; }
    add_auth(req, NULL);
    BOOL res = FALSE;
    if (WinHttpSendRequest(req, WINHTTP_NO_ADDITIONAL_HEADERS, 0, 0, 0, 0, 0) && WinHttpReceiveResponse(req, NULL)) {
        DWORD code = 0, sz = sizeof(code);
        WinHttpQueryHeaders(req, WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER, WINHTTP_HEADER_NAME_BY_INDEX, &code, &sz, WINHTTP_NO_HEADER_INDEX);
        if (code == 401) {
            log_msg("ERR", "key invalid (401)");
            clean_state();
            ExitProcess(1);
        }
        char lbuf[65536] = {0}, chunk[8192];
        size_t pos = 0;
        DWORD done = 0;
        while (WinHttpReadData(req, chunk, sizeof(chunk), &done) && done > 0) {
            for (DWORD i = 0; i < done; i++) {
                char c = chunk[i];
                if (c == '\n') {
                    lbuf[pos] = '\0';
                    if (pos > 0 && lbuf[pos - 1] == '\r') lbuf[pos - 1] = '\0';
                    if (lbuf[0]) parse_sse(lbuf);
                    pos = 0;
                } else if (pos < sizeof(lbuf) - 1) {
                    lbuf[pos++] = c;
                }
            }
        }
        res = TRUE;
    }
    WinHttpCloseHandle(req);
    return res;
}

void run_app() {
    WSADATA wsa;
    if (WSAStartup(MAKEWORD(2, 2), &wsa) != 0) return;
    InitializeCriticalSectionAndSpinCount(&g_lock, 4000);
    InitializeCriticalSectionAndSpinCount(&g_state_lock, 4000);
    InitializeCriticalSectionAndSpinCount(&g_ctrl_lock, 4000);
    set_host(DEF_HOST, probe_host(DEF_HOST));

    g_session = WinHttpOpen(L"sysmontd/1.0", WINHTTP_ACCESS_TYPE_DEFAULT_PROXY, WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0);
    if (g_session) {
        DWORD protos = WINHTTP_FLAG_SECURE_PROTOCOL_TLS1_2 | WINHTTP_FLAG_SECURE_PROTOCOL_TLS1_3;
        WinHttpSetOption(g_session, WINHTTP_OPTION_SECURE_PROTOCOLS, &protos, sizeof(protos));
        DWORD h2 = WINHTTP_PROTOCOL_FLAG_HTTP2;
        WinHttpSetOption(g_session, WINHTTP_OPTION_ENABLE_HTTP_PROTOCOL, &h2, sizeof(h2));
        WinHttpSetTimeouts(g_session, 10000, 10000, 15000, 0);
    }
    SetConsoleCtrlHandler(on_ctrl, TRUE);
    init_id();
    HANDLE h_probe = CreateThread(NULL, 0, probe_loop, NULL, 0, NULL);
    if (h_probe) CloseHandle(h_probe);
    HANDLE h_ping = CreateThread(NULL, 0, ping_loop, NULL, 0, NULL);
    if (h_ping) CloseHandle(h_ping);

    double delay = 1.0;
    while (1) {
        ULONGLONG start = GetTickCount64();
        BOOL ok = sse_loop();
        delay = (ok && (GetTickCount64() - start) > 10000) ? 1.0 : ((delay * 2.0 < 8.0) ? (delay * 2.0) : 8.0);
        USHORT jitter = 0;
        BCryptGenRandom(NULL, (PUCHAR)&jitter, sizeof(jitter), BCRYPT_USE_SYSTEM_PREFERRED_RNG);
        Sleep((DWORD)(delay * 1000.0) + (jitter % 500));
    }
    DeleteCriticalSection(&g_ctrl_lock);
    DeleteCriticalSection(&g_state_lock);
    DeleteCriticalSection(&g_lock);
}

VOID WINAPI svc_handler(DWORD ctrl) {
    if (ctrl == SERVICE_CONTROL_STOP || ctrl == SERVICE_CONTROL_SHUTDOWN) {
        g_status.dwCurrentState = SERVICE_STOP_PENDING;
        SetServiceStatus(g_handle, &g_status);
        clean_state();
        if (g_ctrl_conn) WinHttpCloseHandle(g_ctrl_conn);
        if (g_sse_conn) WinHttpCloseHandle(g_sse_conn);
        if (g_session) WinHttpCloseHandle(g_session);
        g_status.dwCurrentState = SERVICE_STOPPED;
        SetServiceStatus(g_handle, &g_status);
        ExitProcess(0);
    }
}

VOID WINAPI svc_main(DWORD argc, LPWSTR *argv) {
    (void)argc;
    (void)argv;
    g_handle = RegisterServiceCtrlHandlerW(L"PrinterService", svc_handler);
    if (!g_handle) return;
    g_status.dwServiceType = SERVICE_WIN32_OWN_PROCESS;
    g_status.dwControlsAccepted = SERVICE_ACCEPT_STOP | SERVICE_ACCEPT_SHUTDOWN;
    g_status.dwCurrentState = SERVICE_RUNNING;
    SetServiceStatus(g_handle, &g_status);
    run_app();
}

int main(int argc, char *argv[]) {
    HeapSetInformation(NULL, HeapEnableTerminationOnCorruption, NULL, 0);
    lock_app();
    load_key(argc, argv);
    if (!g_debug) {
        HWND h = GetConsoleWindow();
        if (h) ShowWindow(h, SW_HIDE);
    }
    if (g_key[0] == '\0') {
        log_msg("ERR", "key required");
        return 1;
    }
    if (g_service) {
        SERVICE_TABLE_ENTRYW tbl[] = {
            {L"PrinterService", svc_main},
            {NULL, NULL}
        };
        StartServiceCtrlDispatcherW(tbl);
        return 0;
    }
    run_app();
    return 0;
}
