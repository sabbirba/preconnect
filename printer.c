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

#ifdef _MSC_VER
#pragma comment(lib, "user32.lib")
#pragma comment(lib, "ws2_32.lib")
#pragma comment(lib, "winhttp.lib")
#pragma comment(lib, "crypt32.lib")
#pragma comment(lib, "bcrypt.lib")
#pragma comment(lib, "rpcrt4.lib")
#pragma comment(lib, "shell32.lib")
#pragma comment(lib, "shlwapi.lib")
#pragma comment(lib, "advapi32.lib")
#endif

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
#define MAX_HOSTS 16
#define MAX_SSE_LINE (16 * 1024 * 1024)
#define MAX_SSE_EVENT (32 * 1024 * 1024)
#define Q_MAX 8

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
static CRITICAL_SECTION g_claim_lock;
static CRITICAL_SECTION g_ping_lock;
static CRITICAL_SECTION g_ip_lock;
static char *g_q_slots[Q_MAX] = {0};
static LONG g_q_head = 0, g_q_tail = 0, g_q_len = 0;
static volatile LONG g_busy = 0;
static volatile LONG g_claims = 0;
static DWORD g_jobs = 0;
static BOOL g_debug = FALSE, g_service = FALSE;
static SERVICE_STATUS g_status;
static SERVICE_STATUS_HANDLE g_handle = NULL;
static HINTERNET g_session = NULL, g_sse_conn = NULL, g_claim_conn = NULL, g_ping_conn = NULL;
static HANDLE g_mutex = NULL;
static char g_ev_id[128] = {0};
static char *g_ev_data = NULL;
static size_t g_ev_len = 0, g_ev_cap = 0;
static BOOL g_ev_invalid = FALSE;

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

static void reset_conn(HINTERNET *conn) {
    if (*conn) {
        WinHttpCloseHandle(*conn);
        *conn = NULL;
    }
}

static void reset_all_conns() {
    reset_conn(&g_sse_conn);
    EnterCriticalSection(&g_claim_lock);
    reset_conn(&g_claim_conn);
    LeaveCriticalSection(&g_claim_lock);
    EnterCriticalSection(&g_ping_lock);
    reset_conn(&g_ping_conn);
    LeaveCriticalSection(&g_ping_lock);
}

static void shutdown_net() {
    clean_state();
    reset_all_conns();
    if (g_session) { WinHttpCloseHandle(g_session); g_session = NULL; }
}

BOOL WINAPI on_ctrl(DWORD code) {
    (void)code;
    shutdown_net();
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

static const char *find_field(const char *json, const char *key) {
    char pat[66];
    wnsprintfA(pat, sizeof(pat), "\"%s\"", key);
    DWORD pat_len = (DWORD)lstrlenA(pat);
    const char *p = json;
    while ((p = StrStrA(p, pat)) != NULL) {
        const char *b = p - 1;
        while (b >= json && (*b == ' ' || *b == '\t' || *b == '\r' || *b == '\n')) b--;
        if (b < json || *b == '{' || *b == ',') {
            p += pat_len;
            while (*p == ' ' || *p == '\t' || *p == '\r' || *p == '\n') p++;
            if (*p != ':') continue;
            p++;
            while (*p == ' ' || *p == '\t' || *p == '\r' || *p == '\n') p++;
            return p;
        }
        p += pat_len;
    }
    return NULL;
}

static BOOL json_str(const char *json, const char *key, char *out, size_t max_len) {
    const char *p = find_field(json, key);
    if (!p || *p != '"') return FALSE;
    p++;
    size_t i = 0;
    while (*p && *p != '"' && i < max_len - 1) {
        if (*p == '\\' && *(p + 1)) {
            p++;
            switch (*p) {
                case 'n': out[i++] = '\n'; p++; break;
                case 'r': out[i++] = '\r'; p++; break;
                case 't': out[i++] = '\t'; p++; break;
                default: out[i++] = *p++; break;
            }
        } else {
            out[i++] = *p++;
        }
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
    double val = strtod(p, NULL);
    return (val > 0.0) ? (DWORD)(val * 1000.0) : 60000;
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
    BOOL has_ip = FALSE;
    EnterCriticalSection(&g_ip_lock);
    has_ip = (g_ip[0] != L'\0');
    LeaveCriticalSection(&g_ip_lock);
    if (has_ip) WinHttpAddRequestHeaders(req, L"Host: api.preconnect.app\r\n", (DWORD)-1, WINHTTP_ADDREQ_FLAG_ADD);
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
    BYTE *buf = (BYTE *)HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, raw_len);
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
        WinHttpSetTimeouts(req, 5000, 3000, 3000, 5000);
        WinHttpAddRequestHeaders(req, L"Accept: application/dns-json\r\n", (DWORD)-1, WINHTTP_ADDREQ_FLAG_ADD);
        if (WinHttpSendRequest(req, WINHTTP_NO_ADDITIONAL_HEADERS, 0, 0, 0, 0, 0) && WinHttpReceiveResponse(req, NULL)) {
            char resp[4096] = {0};
            DWORD total = 0;
            while (total + 1 < sizeof(resp)) {
                DWORD got = 0;
                if (!WinHttpReadData(req, resp + total, sizeof(resp) - total - 1, &got) || got == 0) break;
                total += got;
            }
            resp[total] = '\0';
            const char *p = StrStrA(resp, "\"type\":1");
            if (p) {
                const char *d = StrStrA(p, "\"data\":\"");
                if (d) {
                    d += 8;
                    char ip[64] = {0};
                    for (int i = 0; *d && *d != '"' && i < 63; i++) ip[i] = *d++;
                    wchar_t wip[64] = {0};
                    MultiByteToWideChar(CP_UTF8, 0, ip, -1, wip, sizeof(wip) / sizeof(wchar_t));
                    IN_ADDR in4;
                    if (InetPtonW(AF_INET, wip, &in4) == 1) {
                        EnterCriticalSection(&g_ip_lock);
                        lstrcpynW(g_ip, wip, sizeof(g_ip) / sizeof(wchar_t));
                        LeaveCriticalSection(&g_ip_lock);
                        reset_all_conns();
                        ok = TRUE;
                    }
                }
            }
        }
        WinHttpCloseHandle(req);
    }
    WinHttpCloseHandle(conn);
    return ok;
}



SOCKET open_tcp(const char *host, USHORT port, DWORD timeout_ms) {
    struct addrinfo hints = {0}, *res = NULL, *rp;
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    hints.ai_protocol = IPPROTO_TCP;
    char port_str[16];
    wnsprintfA(port_str, sizeof(port_str), "%u", port);
    if (getaddrinfo(host, port_str, &hints, &res) != 0 || !res) return INVALID_SOCKET;
    SOCKET s = INVALID_SOCKET;
    for (rp = res; rp; rp = rp->ai_next) {
        SOCKET t = socket(rp->ai_family, rp->ai_socktype, rp->ai_protocol);
        if (t == INVALID_SOCKET) continue;
        u_long nb = 1;
        ioctlsocket(t, FIONBIO, &nb);
        if (connect(t, rp->ai_addr, (int)rp->ai_addrlen) == 0) {
            nb = 0; ioctlsocket(t, FIONBIO, &nb);
            s = t; break;
        }
        if (WSAGetLastError() != WSAEWOULDBLOCK) { closesocket(t); continue; }
        fd_set wset, eset;
        FD_ZERO(&wset); FD_ZERO(&eset);
        FD_SET(t, &wset); FD_SET(t, &eset);
        struct timeval tv = { (long)(timeout_ms / 1000), (long)((timeout_ms % 1000) * 1000) };
        if (select(0, NULL, &wset, &eset, &tv) > 0 && FD_ISSET(t, &wset)) {
            int err = 0, elen = sizeof(err);
            getsockopt(t, SOL_SOCKET, SO_ERROR, (char *)&err, &elen);
            if (err == 0) { nb = 0; ioctlsocket(t, FIONBIO, &nb); s = t; break; }
        }
        closesocket(t);
    }
    freeaddrinfo(res);
    if (s == INVALID_SOCKET) return INVALID_SOCKET;
    BOOL opt = TRUE;
    setsockopt(s, SOL_SOCKET, SO_EXCLUSIVEADDRUSE, (const char *)&opt, sizeof(opt));
    DWORD rto = timeout_ms;
    setsockopt(s, SOL_SOCKET, SO_RCVTIMEO, (const char *)&rto, sizeof(rto));
    setsockopt(s, SOL_SOCKET, SO_SNDTIMEO, (const char *)&rto, sizeof(rto));
    int buf_size = 65536;
    setsockopt(s, SOL_SOCKET, SO_SNDBUF, (const char *)&buf_size, sizeof(buf_size));
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

DWORD WINAPI one_probe(LPVOID arg) {
    char *h = (char *)arg;
    set_host(h, probe_host(h));
    HeapFree(GetProcessHeap(), 0, h);
    return 0;
}

DWORD WINAPI probe_loop(LPVOID arg) {
    (void)arg;
    while (1) {
        EnterCriticalSection(&g_lock);
        LONG cnt = g_count;
        char copy[MAX_HOSTS][128];
        for (LONG i = 0; i < cnt; i++) lstrcpynA(copy[i], g_hosts[i].host, sizeof(copy[i]));
        LeaveCriticalSection(&g_lock);
        HANDLE th[MAX_HOSTS];
        DWORD nth = 0;
        for (LONG i = 0; i < cnt; i++) {
            char *h = (char *)HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, 128);
            if (h) {
                lstrcpynA(h, copy[i], 128);
                HANDLE t = CreateThread(NULL, 0, one_probe, h, 0, NULL);
                if (t) { th[nth++] = t; continue; }
                HeapFree(GetProcessHeap(), 0, h);
            }
            set_host(copy[i], probe_host(copy[i]));
        }
        if (nth > 0) { WaitForMultipleObjects(nth, th, TRUE, 2000); for (DWORD i = 0; i < nth; i++) CloseHandle(th[i]); }
        Sleep(1500);
    }
    return 0;
}

static BYTE *decrypt_data(const char *b64, size_t b64_len, const char *job_id, DWORD *out_len) {
    DWORD raw_len = 0;
    if (!CryptStringToBinaryA(b64, (DWORD)b64_len, CRYPT_STRING_BASE64, NULL, &raw_len, NULL, NULL) || raw_len < 16) return NULL;
    BYTE *raw = (BYTE *)HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, raw_len);
    if (!raw) return NULL;
    if (!CryptStringToBinaryA(b64, (DWORD)b64_len, CRYPT_STRING_BASE64, raw, &raw_len, NULL, NULL)) {
        HeapFree(GetProcessHeap(), 0, raw);
        return NULL;
    }
    BYTE *enc = raw + 16;
    DWORD enc_len = raw_len - 16;
    DWORD id_len = (DWORD)lstrlenA(job_id);
    char seed_buf[1024];
    int seed_len = wnsprintfA(seed_buf, sizeof(seed_buf), "%s", g_key);
    if (seed_len <= 0 || (size_t)seed_len + 16 + id_len >= sizeof(seed_buf)) {
        SecureZeroMemory(seed_buf, sizeof(seed_buf));
        HeapFree(GetProcessHeap(), 0, raw);
        return NULL;
    }
    RtlCopyMemory(seed_buf + seed_len, raw, 16);
    RtlCopyMemory(seed_buf + seed_len + 16, job_id, id_len);
    seed_len += 16 + (int)id_len;

    BYTE p_hash[32];
    BCryptHash(BCRYPT_SHA256_ALG_HANDLE, NULL, 0, (PUCHAR)seed_buf, (ULONG)seed_len, p_hash, 32);
    SecureZeroMemory(seed_buf, sizeof(seed_buf));

    BYTE *dec = (BYTE *)HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, (size_t)enc_len + 1);
    if (!dec) {
        SecureZeroMemory(p_hash, sizeof(p_hash));
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
        SecureZeroMemory(ks_in, sizeof(ks_in));
        SecureZeroMemory(ks, sizeof(ks));
    }
    dec[enc_len] = '\0';
    SecureZeroMemory(p_hash, sizeof(p_hash));
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

static HINTERNET get_conn(HINTERNET *conn) {
    if (!*conn && g_session) {
        wchar_t target[64] = {0};
        EnterCriticalSection(&g_ip_lock);
        if (g_ip[0] != L'\0') lstrcpynW(target, g_ip, sizeof(target) / sizeof(wchar_t));
        LeaveCriticalSection(&g_ip_lock);
        *conn = WinHttpConnect(g_session, target[0] ? target : API_HOST, 443, 0);
    }
    return *conn;
}

static BOOL http_post(HINTERNET *conn, CRITICAL_SECTION *lock, const wchar_t *path, const char *body, char *resp, DWORD resp_max) {
    EnterCriticalSection(lock);
    HINTERNET c = get_conn(conn);
    if (!c) {
        LeaveCriticalSection(lock);
        return FALSE;
    }
    HINTERNET req = WinHttpOpenRequest(c, L"POST", path, NULL, WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES, WINHTTP_FLAG_SECURE);
    if (!req) {
        reset_conn(conn);
        LeaveCriticalSection(lock);
        return FALSE;
    }
    WinHttpSetTimeouts(req, 10000, 5000, 5000, 5000);
    add_auth(req, L"application/json");
    DWORD b_len = (DWORD)lstrlenA(body), code = 0, sz = sizeof(code);
    BOOL ok = FALSE;
    if (WinHttpSendRequest(req, WINHTTP_NO_ADDITIONAL_HEADERS, 0, (LPVOID)body, b_len, b_len, 0) && WinHttpReceiveResponse(req, NULL)) {
        WinHttpQueryHeaders(req, WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER, WINHTTP_HEADER_NAME_BY_INDEX, &code, &sz, WINHTTP_NO_HEADER_INDEX);
        if (resp && resp_max > 0) {
            DWORD total = 0;
            while (total + 1 < resp_max) {
                DWORD got = 0;
                if (!WinHttpReadData(req, resp + total, resp_max - total - 1, &got) || got == 0) break;
                total += got;
            }
            resp[total] = '\0';
        }
        ok = (code == 200);
    }
    if (!ok) reset_conn(conn);
    WinHttpCloseHandle(req);
    LeaveCriticalSection(lock);
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
        if (http_post(&g_claim_conn, &g_claim_lock, L"/print/claim", body, resp, sizeof(resp))) {
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
    char host[128] = DEF_HOST, id[128] = {0};
    json_str(json, "printerHost", host, sizeof(host));
    json_str(json, "id", id, sizeof(id));
    DWORD timeout_ms = json_timeout(json);
    Chunk chunks[5] = {0};
    if (!is_online(host) || (*id && !claim_job(id))) {
        log_msg("WARN", "Printer offline or claim skipped");
        goto done;
    }
    {
        const char *keys[5] = {"qCmd", "cfHdr", "ctl", "dfHdr", "payload"};
        for (int i = 0; i < 5; i++) {
            const char *slice = NULL;
            size_t len = 0;
            if (json_slice(json, keys[i], &slice, &len))
                chunks[i].data = decrypt_data(slice, len, id, &chunks[i].len);
        }
        if (!chunks[4].data || chunks[4].len == 0) {
            log_msg("ERR", "Empty payload");
            goto done;
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
    }
done:
    free_chunks(chunks);
    SetThreadExecutionState(ES_CONTINUOUS);
}

DWORD WINAPI job_thread(LPVOID arg) {
    char *curr = (char *)arg;
    while (curr) {
        run_job(curr);
        SecureZeroMemory(curr, lstrlenA(curr));
        HeapFree(GetProcessHeap(), 0, curr);
        EnterCriticalSection(&g_state_lock);
        if (g_q_len > 0) {
            curr = g_q_slots[g_q_head];
            g_q_slots[g_q_head] = NULL;
            g_q_head = (g_q_head + 1) % Q_MAX;
            g_q_len--;
            LeaveCriticalSection(&g_state_lock);
        } else {
            g_busy = 0;
            curr = NULL;
            LeaveCriticalSection(&g_state_lock);
        }
    }
    return 0;
}

BOOL queue_job(const char *json) {
    size_t len = lstrlenA(json);
    char *copy = (char *)HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, len + 1);
    if (!copy) return FALSE;
    RtlCopyMemory(copy, json, len + 1);
    char jid[128] = {0};
    json_str(copy, "id", jid, sizeof(jid));
    EnterCriticalSection(&g_state_lock);
    if (jid[0]) {
        for (LONG i = 0; i < g_q_len; i++) {
            LONG idx = (g_q_head + i) % Q_MAX;
            char eid[128] = {0};
            if (g_q_slots[idx]) json_str(g_q_slots[idx], "id", eid, sizeof(eid));
            if (lstrcmpA(jid, eid) == 0) {
                LeaveCriticalSection(&g_state_lock);
                SecureZeroMemory(copy, len);
                HeapFree(GetProcessHeap(), 0, copy);
                return TRUE;
            }
        }
    }

    if (!g_busy) {
        g_busy = 1;
        LeaveCriticalSection(&g_state_lock);
        HANDLE th = CreateThread(NULL, 0, job_thread, copy, 0, NULL);
        if (th) CloseHandle(th);
        else job_thread(copy);
        return TRUE;
    } else if (g_q_len < Q_MAX) {
        g_q_slots[g_q_tail] = copy;
        g_q_tail = (g_q_tail + 1) % Q_MAX;
        g_q_len++;
        LeaveCriticalSection(&g_state_lock);
        return TRUE;
    } else {
        LeaveCriticalSection(&g_state_lock);
        SecureZeroMemory(copy, len);
        HeapFree(GetProcessHeap(), 0, copy);
        return FALSE;
    }
}


DWORD WINAPI ping_loop(LPVOID arg) {
    (void)arg;
    while (1) {
        http_post(&g_ping_conn, &g_ping_lock, L"/print/ping", "{}", NULL, 0);
        Sleep(15000);
    }
    return 0;
}

BOOL parse_sse(const char *line) {
    if (line[0] == '\0') {
        BOOL ok = TRUE;
        if (!g_ev_invalid && g_ev_data && g_ev_len > 0) {
            if (g_ev_data[g_ev_len - 1] == '\n') g_ev_data[--g_ev_len] = '\0';
            else g_ev_data[g_ev_len] = '\0';
            log_msg("OK", "SSE event dispatch");
            if (queue_job(g_ev_data)) {
                if (g_ev_id[0]) lstrcpynA(g_last_id, g_ev_id, sizeof(g_last_id));
            } else {
                ok = FALSE;
            }
        }
        g_ev_id[0] = '\0';
        g_ev_len = 0;
        g_ev_invalid = FALSE;
        return ok;
    }
    if (line[0] == ':') return TRUE;
    if (StrCmpNIA(line, "id: ", 4) == 0) {
        lstrcpynA(g_ev_id, line + 4, sizeof(g_ev_id));
        size_t l = lstrlenA(g_ev_id);
        while (l > 0 && (g_ev_id[l - 1] == '\r' || g_ev_id[l - 1] == '\n' || g_ev_id[l - 1] == ' ')) g_ev_id[--l] = '\0';
    } else if (StrCmpNIA(line, "data: ", 6) == 0) {
        if (g_ev_invalid) return TRUE;
        const char *d = line + 6;
        size_t dlen = lstrlenA(d);
        size_t need = g_ev_len + dlen + 2;
        if (need > MAX_SSE_EVENT) {
            g_ev_invalid = TRUE;
            return TRUE;
        }
        if (need > g_ev_cap) {
            size_t nc = (g_ev_cap == 0) ? (dlen + 4096) : g_ev_cap;
            while (nc < need) nc *= 2;
            if (nc > MAX_SSE_EVENT) nc = MAX_SSE_EVENT;
            char *nb = g_ev_data ? (char *)HeapReAlloc(GetProcessHeap(), 0, g_ev_data, nc)
                                 : (char *)HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, nc);
            if (!nb) {
                g_ev_invalid = TRUE;
                return TRUE;
            }
            g_ev_data = nb;
            g_ev_cap = nc;
        }
        if (g_ev_len > 0) g_ev_data[g_ev_len++] = '\n';
        RtlCopyMemory(g_ev_data + g_ev_len, d, dlen);
        g_ev_len += dlen;
    }
    return TRUE;
}

BOOL sse_loop() {
    HINTERNET req = NULL;
    for (int attempt = 0; attempt < 2; attempt++) {
        HINTERNET conn = get_conn(&g_sse_conn);
        if (!conn) {
            if (!resolve_doh(L"1.1.1.1") && !resolve_doh(L"8.8.8.8")) return FALSE;
            conn = get_conn(&g_sse_conn);
            if (!conn) return FALSE;
        }
        req = WinHttpOpenRequest(conn, L"GET", L"/printer", NULL, WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES, WINHTTP_FLAG_SECURE);
        if (!req) {
            reset_conn(&g_sse_conn);
            resolve_doh(L"1.1.1.1");
            continue;
        }
        add_auth(req, NULL);
        if (WinHttpSendRequest(req, WINHTTP_NO_ADDITIONAL_HEADERS, 0, 0, 0, 0, 0) && WinHttpReceiveResponse(req, NULL)) break;
        WinHttpCloseHandle(req);
        req = NULL;
        reset_conn(&g_sse_conn);
        resolve_doh(L"1.1.1.1");
    }
    if (!req) return FALSE;
    g_ev_id[0] = '\0';
    g_ev_len = 0;
    g_ev_invalid = FALSE;
    DWORD code = 0, sz = sizeof(code);
    WinHttpQueryHeaders(req, WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER, WINHTTP_HEADER_NAME_BY_INDEX, &code, &sz, WINHTTP_NO_HEADER_INDEX);
    if (code == 401) {
        log_msg("ERR", "key invalid (401)");
        clean_state();
        ExitProcess(1);
    }
    size_t cap = 65536, pos = 0;
    BOOL discard = FALSE;
    char *line = (char *)HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, cap);
    if (!line) {
        WinHttpCloseHandle(req);
        return FALSE;
    }
    char chunk[8192];
    DWORD done = 0;
    BOOL stream_ok = TRUE;
    while (stream_ok && WinHttpReadData(req, chunk, sizeof(chunk), &done) && done > 0) {
        for (DWORD i = 0; i < done; i++) {
            char c = chunk[i];
            if (c == '\n') {
                if (!discard) {
                    line[pos] = '\0';
                    if (pos > 0 && line[pos - 1] == '\r') line[pos - 1] = '\0';
                    if (!parse_sse(line)) {
                        stream_ok = FALSE;
                        break;
                    }
                } else {
                    g_ev_invalid = TRUE;
                }
                pos = 0;
                discard = FALSE;
            } else if (!discard) {
                if (pos + 2 >= cap) {
                    if (cap >= MAX_SSE_LINE) {
                        discard = TRUE;
                        g_ev_invalid = TRUE;
                        pos = 0;
                    } else {
                        size_t new_cap = cap * 2;
                        if (new_cap > MAX_SSE_LINE) new_cap = MAX_SSE_LINE;
                        char *next = (char *)HeapReAlloc(GetProcessHeap(), 0, line, new_cap);
                        if (!next) { discard = TRUE; g_ev_invalid = TRUE; pos = 0; }
                        else { line = next; cap = new_cap; line[pos++] = c; }
                    }
                } else {
                    line[pos++] = c;
                }
            }
        }
    }
    HeapFree(GetProcessHeap(), 0, line);
    WinHttpCloseHandle(req);
    return stream_ok;
}

void run_app() {
    WSADATA wsa;
    if (WSAStartup(MAKEWORD(2, 2), &wsa) != 0) return;
    InitializeCriticalSectionAndSpinCount(&g_lock, 4000);
    InitializeCriticalSectionAndSpinCount(&g_state_lock, 4000);
    InitializeCriticalSectionAndSpinCount(&g_claim_lock, 4000);
    InitializeCriticalSectionAndSpinCount(&g_ping_lock, 4000);
    InitializeCriticalSectionAndSpinCount(&g_ip_lock, 4000);
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
}

VOID WINAPI svc_handler(DWORD ctrl) {
    if (ctrl == SERVICE_CONTROL_STOP || ctrl == SERVICE_CONTROL_SHUTDOWN) {
        g_status.dwCurrentState = SERVICE_STOP_PENDING;
        SetServiceStatus(g_handle, &g_status);
        shutdown_net();
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
