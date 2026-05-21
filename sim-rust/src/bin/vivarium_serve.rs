// Headless launcher for Vivarium.
//
// Serves the Godot HTML5 export so the simulation runs entirely in the
// browser, and collects per-client telemetry (UA, per-session UUID,
// ecosystem stats, sim + render FPS) via POST /telemetry.
//
// Two optional sinks:
//   --log-stdout            pretty-prints each payload as it arrives
//   --prometheus            exposes /metrics in Prometheus exposition format
//                           summarising every client seen within the
//                           --client-timeout window
//
// The Godot Web build needs cross-origin isolation for SharedArrayBuffer +
// threads, so every response carries COEP/COOP headers. We also inject a
// <script> into index.html that wires up the telemetry loop. This keeps
// the telemetry concern server-side and survives Godot re-exports without
// hand-edits.

use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use clap::Parser;
use serde_json::Value;
use tiny_http::{Header, Method, Request, Response, Server};

#[derive(Parser, Debug)]
#[command(
    name = "vivarium-serve",
    about = "Headless web host for the Vivarium simulation.",
    version
)]
struct Args {
    /// TCP port to listen on.
    #[arg(short, long, default_value_t = 8080)]
    port: u16,

    /// Address to bind. Use 0.0.0.0 to expose on the LAN.
    #[arg(long, default_value = "127.0.0.1")]
    host: String,

    /// Root directory containing index.html + the Godot web export. If
    /// omitted, the server walks up from the binary location looking for
    /// `shaders-godot/godot-project/web/build`.
    #[arg(long)]
    web_root: Option<PathBuf>,

    /// Print each incoming telemetry payload to stdout (pretty JSON).
    #[arg(long)]
    log_stdout: bool,

    /// Expose Prometheus metrics at /metrics.
    #[arg(long)]
    prometheus: bool,

    /// How long (seconds) since the last telemetry POST before a client is
    /// dropped from the Prometheus metrics. Also bounds memory usage.
    #[arg(long, default_value_t = 30)]
    client_timeout: u64,
}

// ---- Per-client telemetry snapshot ------------------------------------------------

#[derive(Debug, Clone)]
struct ClientSnapshot {
    uuid: String,
    user_agent: String,
    remote_addr: String,
    last_seen: Instant,
    // Free-form metrics from the simulation. Numeric leaves become Prometheus gauges.
    metrics: HashMap<String, f64>,
    sim_fps: Option<f64>,
    render_fps: Option<f64>,
}

type ClientStore = Arc<Mutex<HashMap<String, ClientSnapshot>>>;

// ---- main --------------------------------------------------------------------------

fn main() {
    let args = Args::parse();

    let web_root = resolve_web_root(args.web_root.clone())
        .unwrap_or_else(|| {
            eprintln!(
                "error: could not locate the Godot web build.\n\
                 Pass --web-root <dir> pointing at the directory that contains \
                 index.html (e.g. shaders-godot/godot-project/web/build)."
            );
            std::process::exit(2);
        });

    if !web_root.join("index.html").is_file() {
        eprintln!(
            "error: --web-root={} has no index.html",
            web_root.display()
        );
        std::process::exit(2);
    }

    let bind = format!("{}:{}", args.host, args.port);
    let server = match Server::http(&bind) {
        Ok(s) => s,
        Err(e) => {
            eprintln!("error: could not bind {bind}: {e}");
            std::process::exit(1);
        }
    };

    let clients: ClientStore = Arc::new(Mutex::new(HashMap::new()));
    let timeout = Duration::from_secs(args.client_timeout);

    // Avoid coupling to tiny_http's ListenAddr type. Just echo the bind
    // string the user gave us.
    println!("vivarium-serve listening on http://{bind}");
    println!("  web-root        : {}", web_root.display());
    println!("  log-stdout      : {}", args.log_stdout);
    println!("  prometheus      : {}", args.prometheus);
    println!("  client-timeout  : {}s", args.client_timeout);

    for request in server.incoming_requests() {
        let clients = Arc::clone(&clients);
        let web_root = web_root.clone();
        let log_stdout = args.log_stdout;
        let prometheus = args.prometheus;
        // Each request runs on its own thread so a slow telemetry POST never
        // stalls the static-file path. tiny_http is sync, so this is the
        // standard pattern.
        std::thread::spawn(move || {
            if let Err(e) = handle(request, &web_root, &clients, log_stdout, prometheus, timeout) {
                eprintln!("request error: {e}");
            }
        });
    }
}

// ---- routing -----------------------------------------------------------------------

fn handle(
    mut req: Request,
    web_root: &Path,
    clients: &ClientStore,
    log_stdout: bool,
    prometheus_enabled: bool,
    client_timeout: Duration,
) -> std::io::Result<()> {
    let method = req.method().clone();
    let url = req.url().to_string();
    let path = url.split('?').next().unwrap_or("/").to_string();

    match (&method, path.as_str()) {
        (Method::Post, "/telemetry") => {
            let mut body = String::new();
            req.as_reader().read_to_string(&mut body)?;
            let remote = req
                .remote_addr()
                .map(|a| a.to_string())
                .unwrap_or_else(|| "?".to_string());
            let resp = match handle_telemetry(&body, &remote, clients, log_stdout) {
                Ok(()) => Response::from_string("ok").with_status_code(204),
                Err(e) => {
                    eprintln!("telemetry rejected: {e}");
                    Response::from_string(format!("bad telemetry: {e}")).with_status_code(400)
                }
            };
            req.respond(with_common_headers(resp))
        }
        (Method::Get, "/metrics") if prometheus_enabled => {
            let body = render_prometheus(clients, client_timeout);
            let resp = Response::from_string(body).with_header(
                Header::from_bytes(
                    &b"Content-Type"[..],
                    &b"text/plain; version=0.0.4; charset=utf-8"[..],
                )
                .unwrap(),
            );
            req.respond(with_common_headers(resp))
        }
        (Method::Get, _) | (Method::Head, _) => serve_static(req, web_root, &path),
        _ => {
            let resp = Response::from_string("method not allowed").with_status_code(405);
            req.respond(with_common_headers(resp))
        }
    }
}

// ---- static file serving -----------------------------------------------------------

fn serve_static(req: Request, web_root: &Path, path: &str) -> std::io::Result<()> {
    let rel = if path == "/" { "/index.html" } else { path };
    // Strip leading '/', reject any traversal. Components::ParentDir would
    // escape the web_root.
    let trimmed = rel.trim_start_matches('/');
    let candidate = web_root.join(trimmed);
    let safe = candidate
        .components()
        .all(|c| !matches!(c, std::path::Component::ParentDir));
    if !safe {
        let resp = Response::from_string("forbidden").with_status_code(403);
        return req.respond(with_common_headers(resp));
    }
    if !candidate.is_file() {
        let resp = Response::from_string("not found").with_status_code(404);
        return req.respond(with_common_headers(resp));
    }

    let mime = mime_for(&candidate);
    let bytes = fs::read(&candidate)?;

    // Special-case index.html: inject the telemetry shim so the page knows
    // its own origin and how to POST stats up.
    let (bytes, mime) = if candidate.file_name().map(|n| n == "index.html").unwrap_or(false) {
        let html = String::from_utf8_lossy(&bytes).to_string();
        (inject_telemetry_shim(&html).into_bytes(), "text/html; charset=utf-8".to_string())
    } else {
        (bytes, mime)
    };

    let resp = Response::from_data(bytes).with_header(
        Header::from_bytes(&b"Content-Type"[..], mime.as_bytes()).unwrap(),
    );
    req.respond(with_common_headers(resp))
}

fn mime_for(path: &Path) -> String {
    let ext = path
        .extension()
        .and_then(|s| s.to_str())
        .unwrap_or("")
        .to_ascii_lowercase();
    match ext.as_str() {
        "html" | "htm" => "text/html; charset=utf-8",
        "js" => "application/javascript; charset=utf-8",
        "wasm" => "application/wasm",
        "json" => "application/json",
        "png" => "image/png",
        "jpg" | "jpeg" => "image/jpeg",
        "svg" => "image/svg+xml",
        "css" => "text/css; charset=utf-8",
        "ico" => "image/x-icon",
        "pck" => "application/octet-stream",
        _ => "application/octet-stream",
    }
    .to_string()
}

// Godot's web export uses SharedArrayBuffer + pthreads. Browsers require the
// page to be cross-origin isolated for that. Every response therefore
// carries COOP (same-origin) + COEP (require-corp). CORP on this server's
// own assets makes them loadable under that policy. CORS-allow-any keeps
// the /telemetry path reachable from arbitrary local pages during testing.
fn with_common_headers<R: std::io::Read>(resp: Response<R>) -> Response<R> {
    resp.with_header(
        Header::from_bytes(
            &b"Cross-Origin-Opener-Policy"[..],
            &b"same-origin"[..],
        )
        .unwrap(),
    )
    .with_header(
        Header::from_bytes(
            &b"Cross-Origin-Embedder-Policy"[..],
            &b"require-corp"[..],
        )
        .unwrap(),
    )
    .with_header(
        Header::from_bytes(
            &b"Cross-Origin-Resource-Policy"[..],
            &b"cross-origin"[..],
        )
        .unwrap(),
    )
    .with_header(Header::from_bytes(&b"Access-Control-Allow-Origin"[..], &b"*"[..]).unwrap())
    .with_header(Header::from_bytes(&b"Access-Control-Allow-Methods"[..], &b"GET, POST, HEAD"[..]).unwrap())
    .with_header(Header::from_bytes(&b"Access-Control-Allow-Headers"[..], &b"Content-Type"[..]).unwrap())
}

// ---- HTML shim injected into index.html --------------------------------------------

const TELEMETRY_SHIM: &str = r#"<script>
(function () {
  // Per-session UUID. Generated once when the page loads and reused for
  // every POST until the tab is reloaded.
  function makeUUID() {
    if (window.crypto && crypto.randomUUID) return crypto.randomUUID();
    // RFC4122 v4 fallback for older browsers.
    return ('xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx').replace(/[xy]/g, function (c) {
      var r = Math.random() * 16 | 0;
      var v = c === 'x' ? r : (r & 0x3 | 0x8);
      return v.toString(16);
    });
  }
  var sessionId = makeUUID();
  var sessionStart = Date.now();

  // Display FPS, measured by counting requestAnimationFrame callbacks.
  // This is the *browser's* rendering rate, which may differ from the
  // sim's internal render FPS (the canvas can be vsync-throttled).
  var displayFrames = 0;
  var displayFpsEMA = 0;
  var lastFpsSample = performance.now();
  function fpsTick() {
    displayFrames++;
    var now = performance.now();
    var dt = now - lastFpsSample;
    if (dt >= 1000) {
      var instant = (displayFrames * 1000) / dt;
      displayFpsEMA = displayFpsEMA === 0 ? instant : (displayFpsEMA * 0.7 + instant * 0.3);
      displayFrames = 0;
      lastFpsSample = now;
    }
    requestAnimationFrame(fpsTick);
  }
  requestAnimationFrame(fpsTick);

  // Latest stats pushed from GDScript via JavaScriptBridge.eval(...). The
  // GDScript side calls window.__vivariumPushStats(obj) on every 1Hz
  // stats_changed signal.
  var latestStats = null;
  window.__vivariumPushStats = function (obj) {
    latestStats = obj;
  };

  function post() {
    if (document.hidden) return; // skip when tab is backgrounded
    var payload = {
      uuid: sessionId,
      user_agent: navigator.userAgent,
      session_started_at: sessionStart,
      timestamp: Date.now(),
      display_fps: Math.round(displayFpsEMA * 100) / 100,
      stats: latestStats || {}
    };
    try {
      fetch('/telemetry', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload),
        keepalive: true
      }).catch(function () { /* swallow. Telemetry is best-effort. */ });
    } catch (e) { /* swallow */ }
  }

  // Post every 5 seconds. The first post is delayed a bit so GDScript has
  // time to push its first stats snapshot.
  setTimeout(post, 2000);
  setInterval(post, 5000);
})();
</script>
"#;

fn inject_telemetry_shim(html: &str) -> String {
    // Inject just before </body>; if missing (shouldn't happen for Godot's
    // template, but be defensive), append at the end.
    if let Some(idx) = html.rfind("</body>") {
        let mut out = String::with_capacity(html.len() + TELEMETRY_SHIM.len());
        out.push_str(&html[..idx]);
        out.push_str(TELEMETRY_SHIM);
        out.push_str(&html[idx..]);
        out
    } else {
        format!("{}{}", html, TELEMETRY_SHIM)
    }
}

// ---- telemetry ingestion -----------------------------------------------------------

fn handle_telemetry(
    body: &str,
    remote: &str,
    clients: &ClientStore,
    log_stdout: bool,
) -> Result<(), String> {
    let v: Value = serde_json::from_str(body).map_err(|e| e.to_string())?;
    let uuid = v
        .get("uuid")
        .and_then(|x| x.as_str())
        .ok_or("missing uuid")?
        .to_string();
    let ua = v
        .get("user_agent")
        .and_then(|x| x.as_str())
        .unwrap_or("")
        .to_string();
    let display_fps = v.get("display_fps").and_then(|x| x.as_f64());
    let stats = v.get("stats").cloned().unwrap_or(Value::Null);

    let (metrics, sim_fps, render_fps_from_stats) = extract_stats(&stats);
    let render_fps = render_fps_from_stats.or(display_fps);

    if log_stdout {
        // Re-pretty so the operator sees a clean snapshot per client.
        let pretty = serde_json::to_string_pretty(&v).unwrap_or(body.to_string());
        println!("[telemetry {remote} {uuid}] {pretty}");
    }

    let mut guard = clients.lock().unwrap();
    guard.insert(
        uuid.clone(),
        ClientSnapshot {
            uuid,
            user_agent: ua,
            remote_addr: remote.to_string(),
            last_seen: Instant::now(),
            metrics,
            sim_fps,
            render_fps,
        },
    );
    Ok(())
}

// Walk the stats object pulling out numeric leaves as gauges. sim_fps /
// render_fps break out into their own dedicated fields so /metrics emits
// stable HELP/TYPE blocks for them.
fn extract_stats(stats: &Value) -> (HashMap<String, f64>, Option<f64>, Option<f64>) {
    let mut metrics: HashMap<String, f64> = HashMap::new();
    let mut sim_fps: Option<f64> = None;
    let mut render_fps: Option<f64> = None;
    if let Value::Object(map) = stats {
        for (k, v) in map {
            match v {
                Value::Number(n) => {
                    if let Some(f) = n.as_f64() {
                        match k.as_str() {
                            "sim_fps" => sim_fps = Some(f),
                            "render_fps" => render_fps = Some(f),
                            _ => {
                                metrics.insert(k.clone(), f);
                            }
                        }
                    }
                }
                Value::Bool(b) => {
                    metrics.insert(k.clone(), if *b { 1.0 } else { 0.0 });
                }
                _ => {}
            }
        }
    }
    (metrics, sim_fps, render_fps)
}

// ---- Prometheus exposition ----------------------------------------------------------

fn render_prometheus(clients: &ClientStore, timeout: Duration) -> String {
    let mut guard = clients.lock().unwrap();
    let now = Instant::now();
    guard.retain(|_, c| now.duration_since(c.last_seen) <= timeout);

    // Collect the union of metric names across all live clients so we can
    // emit one HELP/TYPE block per metric.
    let mut metric_names: std::collections::BTreeSet<String> = std::collections::BTreeSet::new();
    for c in guard.values() {
        for k in c.metrics.keys() {
            metric_names.insert(k.clone());
        }
    }

    let mut out = String::new();
    let scrape_unix = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    out.push_str(&format!("# scrape_time_unix {scrape_unix}\n"));
    out.push_str("# HELP vivarium_clients_active Number of clients with recent telemetry.\n");
    out.push_str("# TYPE vivarium_clients_active gauge\n");
    out.push_str(&format!("vivarium_clients_active {}\n", guard.len()));

    // Per-client gauges. We label each series by uuid + a sanitized
    // user-agent fragment so the operator can tell sessions apart.
    // Prometheus wants label values escaped.
    for name in &metric_names {
        out.push_str(&format!("# HELP vivarium_{} {} reported by clients.\n", name, name));
        out.push_str(&format!("# TYPE vivarium_{} gauge\n", name));
        for c in guard.values() {
            if let Some(v) = c.metrics.get(name) {
                out.push_str(&format!(
                    "vivarium_{}{{uuid=\"{}\",ua=\"{}\"}} {}\n",
                    name,
                    escape_label(&c.uuid),
                    escape_label(&truncate_ua(&c.user_agent)),
                    format_float(*v),
                ));
            }
        }
    }

    // FPS gauges live outside the dynamic metric set since they're known a
    // priori and we want consistent HELP/TYPE blocks even with zero clients.
    out.push_str("# HELP vivarium_render_fps Browser render FPS (rAF-measured) or sim render FPS if reported.\n");
    out.push_str("# TYPE vivarium_render_fps gauge\n");
    for c in guard.values() {
        if let Some(v) = c.render_fps {
            out.push_str(&format!(
                "vivarium_render_fps{{uuid=\"{}\",ua=\"{}\"}} {}\n",
                escape_label(&c.uuid),
                escape_label(&truncate_ua(&c.user_agent)),
                format_float(v),
            ));
        }
    }
    out.push_str("# HELP vivarium_sim_fps Effective sim tick rate (sim_hz * time_scale).\n");
    out.push_str("# TYPE vivarium_sim_fps gauge\n");
    for c in guard.values() {
        if let Some(v) = c.sim_fps {
            out.push_str(&format!(
                "vivarium_sim_fps{{uuid=\"{}\",ua=\"{}\"}} {}\n",
                escape_label(&c.uuid),
                escape_label(&truncate_ua(&c.user_agent)),
                format_float(v),
            ));
        }
    }

    // Seconds-since-last-seen so alerts can fire on stalled clients.
    out.push_str("# HELP vivarium_client_age_seconds Seconds since last telemetry POST from this client.\n");
    out.push_str("# TYPE vivarium_client_age_seconds gauge\n");
    for c in guard.values() {
        let age = now.duration_since(c.last_seen).as_secs_f64();
        out.push_str(&format!(
            "vivarium_client_age_seconds{{uuid=\"{}\",ua=\"{}\",remote=\"{}\"}} {}\n",
            escape_label(&c.uuid),
            escape_label(&truncate_ua(&c.user_agent)),
            escape_label(&c.remote_addr),
            format_float(age),
        ));
    }

    out
}

fn escape_label(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for ch in s.chars() {
        match ch {
            '\\' => out.push_str(r"\\"),
            '"' => out.push_str(r#"\""#),
            '\n' => out.push_str(r"\n"),
            _ => out.push(ch),
        }
    }
    out
}

// User-agent strings are verbose; cap length so Prometheus label cardinality
// doesn't balloon and legends stay readable.
fn truncate_ua(ua: &str) -> String {
    if ua.len() <= 64 {
        ua.to_string()
    } else {
        format!("{}…", &ua[..63])
    }
}

fn format_float(v: f64) -> String {
    if v.fract() == 0.0 && v.abs() < 1e15 {
        format!("{}", v as i64)
    } else {
        format!("{v}")
    }
}

// ---- locating the web build --------------------------------------------------------

fn resolve_web_root(explicit: Option<PathBuf>) -> Option<PathBuf> {
    if let Some(p) = explicit {
        return Some(p);
    }
    // Try cwd first, then walk up from the executable.
    let candidates = [
        Path::new("shaders-godot/godot-project/web/build").to_path_buf(),
        Path::new("../shaders-godot/godot-project/web/build").to_path_buf(),
        Path::new("../../shaders-godot/godot-project/web/build").to_path_buf(),
    ];
    for c in &candidates {
        if c.join("index.html").is_file() {
            return Some(c.canonicalize().unwrap_or_else(|_| c.clone()));
        }
    }
    // Last resort: walk up from the executable.
    if let Ok(exe) = std::env::current_exe() {
        let mut p = exe.as_path();
        while let Some(parent) = p.parent() {
            let candidate = parent.join("shaders-godot/godot-project/web/build");
            if candidate.join("index.html").is_file() {
                return Some(candidate);
            }
            p = parent;
        }
    }
    None
}
