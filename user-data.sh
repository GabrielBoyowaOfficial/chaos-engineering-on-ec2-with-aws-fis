#!/bin/bash
# =============================================================================
# EC2 user data: a branded "opening soon" page for the two-AZ web tier behind an ALB.
#
# Image   Amazon Linux 2023
# Serves  nginx on port 80: /  the page, /healthz  ALB health check (200),
#         /api/whoami  JSON about the request, used by the page footer
# Needs   Security group: TCP 80 from the ALB's security group
#         Target group:   health check path /healthz, success code 200
# Limit   EC2 caps user data at 16384 bytes. Check: wc -c user-data.sh
# Logs    /var/log/cloud-init-output.log
# Tip     Save with LF line endings (CRLF breaks the first line).
# =============================================================================
set -euo pipefail

SITE_NAME="GabrielBoyowaOfficial"
CONTACT_EMAIL="hello@example.com"   # leave empty to hide the Email us button

log() { echo "[user-data] $*"; }
trap 'log "failed near line $LINENO"' ERR

# 1. Install nginx -------------------------------------------------------------
log "installing nginx"
dnf install -y -q nginx

# 2. Ask the instance who it is (IMDSv2) ---------------------------------------
log "reading instance metadata"
TOKEN=$(curl -sf --retry 5 --retry-connrefused -X PUT \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 120" http://169.254.169.254/latest/api/token)
# Keep only characters that are safe to paste into HTML and JSON.
imds() {
  curl -sf -H "X-aws-ec2-metadata-token: $TOKEN" \
    "http://169.254.169.254/latest/meta-data/$1" | tr -cd 'A-Za-z0-9._:/-' || true
}
IID=$(imds instance-id)
AZ=$(imds placement/availability-zone)
ITYPE=$(imds instance-type)
AMI=$(imds ami-id)
IP=$(imds local-ipv4)
UP=$(cut -d. -f1 /proc/uptime)
BOOTED=$(( $(date +%s) - UP ))

# 3. Write the site ------------------------------------------------------------
WEB=/usr/share/nginx/html
T=$(mktemp -d)
export SITE_NAME CONTACT_EMAIL IID AZ ITYPE AMI IP UP BOOTED WEB T

cat > "$WEB/site.css" <<'CSS'
/* Two-AZ demo. The extra suffix colours are harmless fallbacks in case the Region's
   first two available zones are not literally named ...a and ...b for this account. */
:root{--blue:#2331d8;--ink:#0e1c6b;--mute:#4a58a6;--hair:#dde1fa;--line:#ff8a1f;--gut:clamp(20px,6vw,88px);--bar:64px;
--sans:Bahnschrift,"Segoe UI",system-ui,sans-serif;--disp:Bahnschrift,"DIN Alternate","Segoe UI",system-ui,sans-serif}
.z-a{--line:#ff8a1f}.z-b{--line:#ff6fb1}.z-c{--line:#19e3b1}.z-d{--line:#ffd426}.z-e{--line:#b69cff}.z-f{--line:#6fd6ff}
*{box-sizing:border-box;margin:0;padding:0}
html{background:var(--blue)}
body{min-height:100svh;padding-bottom:calc(var(--bar) + 3px);display:flex;flex-direction:column;color:#fff;font:400 clamp(17px,1.5vw,20px)/1.5 var(--sans);font-variant-numeric:tabular-nums}
h1,h2,b,.btn,.brand{font-family:var(--disp)}
header{padding:clamp(20px,4vh,40px) var(--gut) 0}
.brand{display:inline-flex;align-items:center;gap:.6em;color:#fff;font-size:1.3rem;font-weight:700;text-decoration:none;overflow-wrap:anywhere}
.brand i,.bullet{display:inline-grid;place-items:center;flex:none;width:1.9em;height:1.9em;border:2px solid var(--ink);border-radius:50%;background:var(--line);color:var(--ink);font:700 .85rem/1 var(--disp)}
.brand i{border-color:#fff;background:#fff;font-size:1.05rem}
main{display:flex;flex:1;flex-direction:column;padding-top:clamp(16px,5vh,72px)}
h1{padding:0 var(--gut);font-size:clamp(54px,min(11vw,19svh),170px);line-height:.92;letter-spacing:-.025em;font-variation-settings:"wdth" 86;text-wrap:balance}
.lede{max-width:calc(40ch + 2 * var(--gut));padding:0 var(--gut);margin-top:clamp(16px,3vh,32px);font-size:clamp(18px,1.7vw,23px);line-height:1.45;overflow-wrap:anywhere;text-wrap:balance}
.btn{align-self:flex-start;margin:clamp(18px,3vh,28px) 0 0 var(--gut);padding:.7em 1.3em;border-radius:12px;background:#fff;color:var(--ink);font-weight:700;text-decoration:none}
.btn:hover{background:var(--ink);color:#fff}
/* The route: you are here, and the line carries on to a station that is not open yet. */
.route{--cut:inset(0 100% 0 0);display:flex;align-items:center;margin-top:auto;padding:clamp(16px,4vh,56px) var(--gut) clamp(84px,13vh,112px) 0}
.seg{flex:24 1 0;height:14px;border-radius:0 7px 7px 0;background:var(--line)}
.seg.soon{flex:60 1 0;border-radius:7px;background:repeating-linear-gradient(90deg,var(--line) 0 22px,transparent 22px 38px)}
.stop{position:relative;z-index:1;flex:none;width:46px;height:46px;margin:0 -10px}
.stop::before{content:"";position:absolute;inset:0;border:9px solid var(--line);border-radius:50%;background:#fff}
.end::before{border-color:#fff;background:var(--blue)}
.stop>span{position:absolute;top:calc(100% + 14px);left:50%;transform:translateX(-50%);white-space:nowrap;text-align:center;line-height:1.25}
.stop b{display:block;font-size:clamp(18px,1.8vw,24px)}
.stop small{font-size:.85rem}
.end>span{right:0;left:auto;width:max-content;max-width:min(60vw,560px);transform:none;text-align:right}
.end b{padding:.15em .55em;border-radius:8px;background:#fff;color:var(--ink);white-space:normal;overflow-wrap:anywhere}
.end small{display:block;margin-top:.4em}
@keyframes draw{from{clip-path:var(--cut)}to{clip-path:inset(0)}}
@keyframes pop{from{transform:scale(0)}}
@keyframes show{from{opacity:0}}
.seg:first-child{animation:draw .7s cubic-bezier(.2,.8,.2,1) both}
.seg.soon{animation:draw .9s .85s cubic-bezier(.4,0,.2,1) both}
.stop::before{animation:pop .35s .55s cubic-bezier(.3,1.5,.5,1) both}
.stop>span{animation:show .4s .7s both}
.end::before{animation-delay:1.7s}
.end>span{animation-delay:1.85s}
/* The footer: which server answered. It opens into the request details. */
footer{position:fixed;z-index:2;inset:auto 0 0;color:var(--ink)}
footer:has([open])::before{content:"";position:fixed;inset:0;z-index:-1;background:rgba(10,18,70,.55)}
details{border-top:3px solid var(--line);background:#fff}
summary{display:flex;align-items:center;gap:.8em;height:var(--bar);padding:0 var(--gut);font-size:.95rem;white-space:nowrap;list-style:none;cursor:pointer}
summary::-webkit-details-marker{display:none}
.who{min-width:0;overflow:hidden;text-overflow:ellipsis}
.more{display:inline-flex;align-items:center;gap:.6em;margin-left:auto;font-weight:700}
.more::after{content:"";width:.5em;height:.5em;margin-top:-.25em;border:solid currentColor;border-width:0 3px 3px 0;transform:rotate(45deg);transition:transform .25s,margin .25s}
[open] .more::after{margin-top:.25em;transform:rotate(-135deg)}
.panel{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:clamp(24px,4vw,64px);max-height:min(72svh,620px);padding:4px var(--gut) 36px;border-top:1px solid var(--hair);overflow:auto;overscroll-behavior:contain}
h2{margin:20px 0 12px;font-size:1.2rem}
.path{list-style:none}
.path li{position:relative;margin-left:11px;padding:0 0 20px 34px;border-left:3px solid var(--ink);line-height:1.25}
.path li:last-child{padding-bottom:0;border-color:transparent}
.path li::before{content:"";position:absolute;left:-15px;top:0;width:27px;height:27px;border:6px solid var(--line);border-radius:50%;outline:2px solid var(--ink);background:#fff}
.path b{display:block}
.path span{color:var(--mute);font-size:.92rem;overflow-wrap:anywhere}
dl{display:grid;grid-template-columns:auto 1fr;gap:8px 18px;font-size:.95rem}
dt{color:var(--mute)}
dd{font-weight:600;overflow-wrap:anywhere}
:focus-visible{outline:3px solid #fff;outline-offset:3px}
footer :focus-visible{outline-color:var(--ink)}
@media(max-width:860px){.panel{grid-template-columns:1fr;gap:0}}
@media(max-width:640px){
:root{--bar:60px}
.route{--cut:inset(0 0 100% 0);flex-direction:column;align-items:flex-start;padding:24px 0 36px var(--gut)}
.seg{flex:none;width:14px;height:clamp(28px,6svh,64px);border-radius:0 0 7px 7px}
.seg.soon{flex:none;height:clamp(56px,11svh,120px);border-radius:7px;background:repeating-linear-gradient(180deg,var(--line) 0 22px,transparent 22px 38px)}
.stop{margin:-10px 0 -10px -16px}
.stop>span,.end>span{top:50%;right:auto;left:calc(100% + 16px);max-width:calc(100vw - var(--gut) - 70px);transform:translateY(-50%);text-align:left}
.in,.more span{display:none}
.panel{max-height:70svh}
}
@media(prefers-reduced-motion:reduce){*,::before,::after{animation:none!important;transition:none!important}}
CSS

cat > "$WEB/site.js" <<'JS'
(() => {
  const det = document.querySelector('details'), up = document.getElementById('up');
  let loaded = false;

  // Opening the details asks the server what the load balancer passed on.
  det.addEventListener('toggle', async () => {
    if (!det.open) return;
    const s = Math.max(0, Date.now() / 1000 - up.dataset.s | 0);
    const d = s / 86400 | 0, h = s % 86400 / 3600 | 0, m = s % 3600 / 60 | 0;
    up.textContent = d ? `${d} d ${h} h` : h ? `${h} h ${m} min` : `${m} min`;
    if (loaded) return;
    loaded = true;
    const put = f => document.querySelectorAll('[data-k]').forEach(e => e.textContent = f(e.dataset.k));
    try {
      const t = performance.now();
      const r = await fetch('/api/whoami', { cache: 'no-store' });
      const j = await r.json();
      j.ms = Math.round(performance.now() - t) + ' ms';
      j.link = `${j.proto} on port ${j.port}`;
      put(k => j[k]);
    } catch {
      loaded = false;
      put(() => 'Unavailable');
    }
  });
  addEventListener('keydown', e => { if (e.key === 'Escape') det.open = false; });
  document.querySelector('footer').addEventListener('click', e => { if (e.target === e.currentTarget) det.open = false; });
})();
JS

cat > "$T/index.tpl" <<'HTML'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="theme-color" content="#2331d8">
<title>@SITE_NAME@ opens soon</title>
<link rel="icon" href="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 9 9'%3E%3Ccircle cx='4.5' cy='4.5' r='4.5' fill='%232331d8'/%3E%3Ccircle cx='4.5' cy='4.5' r='2' fill='none' stroke='%23fff'/%3E%3C/svg%3E">
<link rel="stylesheet" href="/site.css">
</head>
<body class="@ZCLASS@">
<header><a class="brand" href="/"><i>@INITIAL@</i>@SITE_WBR@</a></header>
<main>
<h1>Opening soon.</h1>
<p class="lede">@SITE_WBR@ is getting ready for its first visitors. This demo web tier runs across two Availability Zones behind one load balancer.</p>
@MAIL_BUTTON@
<div class="route" role="img" aria-label="A transit line. You are here. The line carries on, dashed, to @SITE_NAME@, which opens soon.">
<span class="seg"></span>
<span class="stop"><span><b>You are here</b><small>This page</small></span></span>
<span class="seg soon"></span>
<span class="stop end"><span><b>@SITE_WBR@</b><small>Opens soon</small></span></span>
</div>
</main>
<footer>
<details>
<summary><span class="bullet">@LETTER@</span><span class="who">Served by <b>@IID@</b><span class="in"> in @AZ@</span></span><span class="more"><span>Request details</span></span></summary>
<div class="panel">
<section>
<h2>Route</h2>
<ol class="path">
<li><b>You</b><span data-k="client">…</span></li>
<li><b>Load balancer</b><span data-k="hop">…</span></li>
<li><b>This server</b><span>@IID@</span></li>
</ol>
</section>
<section>
<h2>Your request</h2>
<dl>
<dt>Protocol</dt><dd data-k="link">…</dd>
<dt>Trace ID</dt><dd data-k="trace">…</dd>
<dt>Request ID</dt><dd data-k="rid">…</dd>
<dt>Response time</dt><dd data-k="ms">…</dd>
</dl>
</section>
<section>
<h2>This server</h2>
<dl>
<dt>Zone</dt><dd>@AZ@</dd>
<dt>Instance type</dt><dd>@ITYPE@</dd>
<dt>Image</dt><dd>@AMI@</dd>
<dt>Private address</dt><dd>@IP@</dd>
<dt>Running for</dt><dd><time id="up" data-s="@BOOTED@"></time></dd>
<dt>Ready after</dt><dd>@UP@ seconds</dd>
</dl>
</section>
</div>
</details>
</footer>
<script src="/site.js"></script>
</body>
</html>
HTML

cat > "$T/nginx.tpl" <<'NGINX'
user nginx;
worker_processes auto;
pid /run/nginx.pid;
error_log /var/log/nginx/error.log warn;
events { worker_connections 1024; }

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    access_log /var/log/nginx/access.log;
    server_tokens off;
    sendfile on;
    # Stay above the ALB idle timeout (60 s), or the ALB can reuse a connection
    # nginx just closed, which shows up as random 502s.
    keepalive_timeout 75s;
    gzip on;
    gzip_types text/css application/javascript application/json;

    # What the ALB says about the visitor. Every value is whitelisted by regex so a
    # forged header cannot break the JSON below. The ALB appends the real client
    # address to X-Forwarded-For, so the last entry is the one to trust.
    map $http_x_forwarded_for   $viewer { default $remote_addr; "~(?<ip>[0-9a-fA-F:.]{2,45})$" $ip; }
    map $http_x_forwarded_proto $proto  { default $scheme;      "~^(?<pr>https?)$" $pr; }
    map $http_x_forwarded_port  $port   { default 80;           "~^(?<pt>[0-9]{1,5})$" $pt; }
    map $http_x_amzn_trace_id   $trace  { default "-";          "~^(?<tr>[A-Za-z0-9=;-]{1,200})$" $tr; }

    server {
        listen 80 default_server;
        server_name _;
        root /usr/share/nginx/html;
        charset utf-8;
        log_not_found off;
        error_page 404 /index.html;
        expires -1;

        add_header X-Served-By "@IID@ (@AZ@)" always;
        add_header X-Content-Type-Options nosniff always;
        add_header Content-Security-Policy "default-src 'self'; img-src 'self' data:; frame-ancestors 'none'; base-uri 'none'; form-action 'none'" always;

        location = /healthz {
            access_log off;
            default_type text/plain;
            return 200 "ok\n";
        }

        location = /api/whoami {
            default_type application/json;
            return 200 '{"instance":"@IID@","az":"@AZ@","client":"$viewer","hop":"$remote_addr","proto":"$proto","port":"$port","trace":"$trace","rid":"$request_id","http":"$server_protocol"}';
        }
    }
}
NGINX

# Fill the @NAME@ markers. Text that goes into HTML is escaped; nginx gets the raw
# values, which were already filtered in step 2.
cp -n /etc/nginx/nginx.conf /etc/nginx/nginx.conf.orig
python3 - <<'PY'
import html, os, re
e = os.environ
z = e['AZ'][-1:]
h = {k: html.escape(v) for k, v in e.items()}
h.update(
    LETTER=z.upper() if z.isalpha() else '•',
    ZCLASS='z-' + z.lower(),
    INITIAL=html.escape(e['SITE_NAME'][:1].upper()),
    SITE_WBR=re.sub(r'(?<=[a-z])(?=[A-Z])', '<wbr>', h['SITE_NAME']),  # lets long CamelCase names wrap
    MAIL_BUTTON=f'<a class="btn" href="mailto:{h["CONTACT_EMAIL"]}">Email us</a>' if e['CONTACT_EMAIL'] else '',
)
for src, dst, vals in (('index.tpl', e['WEB'] + '/index.html', h), ('nginx.tpl', '/etc/nginx/nginx.conf', e)):
    with open(e['T'] + '/' + src, encoding='utf-8') as f:
        text = re.sub(r'@([A-Z_]+)@', lambda m: vals[m[1]], f.read())
    with open(dst, 'w', encoding='utf-8') as f:
        f.write(text)
PY
rm -rf "$T"

# 4. Start nginx and check it answers --------------------------------------------
nginx -t
systemctl enable nginx
systemctl restart nginx
curl -fsS --retry 5 --retry-connrefused http://127.0.0.1/healthz > /dev/null
log "ready: $IID in $AZ"
