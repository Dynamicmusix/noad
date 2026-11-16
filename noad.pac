// NOAD Local ConnectProxyServer + Automatic Failover PAC
// Routes traffic through NØAD's local ConnectProxyServer (127.0.0.1:9090) when NØAD is running,
// and automatically falls back to DIRECT if NØAD is closed (and always sends Apple verification DIRECT)!
function FindProxyForURL(url, host) {
  if (!host) return "DIRECT";
  host = host.toLowerCase();
  if (
    host === "localhost" ||
    host === "127.0.0.1" ||
    host.indexOf("192.168.") === 0 ||
    host.endsWith(".apple.com") ||
    host.endsWith(".icloud.com") ||
    host.endsWith(".mzstatic.com")
  ) {
    return "DIRECT";
  }
  return "PROXY 127.0.0.1:9090; DIRECT";
}
