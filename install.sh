#!/usr/bin/env bash
#
# remnawave-selfsteal-node — install.sh
#
# Remnawave Node + Xray Reality "self-steal" kurulumu.
# Desteklenen sistemler: Ubuntu 22.04 / 24.04
#
# Tek satırla çalıştırma:
#   bash <(curl -fsSL https://raw.githubusercontent.com/umytrovshenov-cmd/remnawave-selfsteal-node/main/install.sh)
#
# Ne yapar?
#   1. BBR'ı açar
#   2. nginx + Let's Encrypt ile alan adın için gerçek bir HTTPS sitesi kurar (127.0.0.1:9443)
#   3. Docker'ı kurar, Remnawave panelinden yapıştırdığın docker-compose.yml ile node'u başlatır
#   4. Reality anahtarı + shortId üretir ve panele yapıştırılacak hazır Config Profile JSON'unu verir
#
# Parametreler (hepsi opsiyonel; verilmezse sorulur):
#   -d, --domain DOMAIN       Bu sunucunun alan adı (A kaydı bu sunucunun IP'sine yönlü olmalı)
#   -e, --email EMAIL         Let's Encrypt e-postası
#   -c, --compose FILE        Remnawave panelinden alınmış docker-compose.yml dosyası
#   -k, --private-key KEY     Mevcut Reality private key (verilmezse yenisi üretilir)
#   -t, --tag TAG             Config Profile içindeki inbound etiketi
#   -p, --panel-ip IP         UFW aktifse NODE_PORT sadece bu IP'ye açılır
#   -y, --yes                 Onay sorularını atla
#       --skip-dns-check      Alan adı -> IP kontrolünü atla
#   -h, --help                Yardım
#
set -Eeuo pipefail

SCRIPT_VERSION="1.0.0"

# ---------------------------------------------------------------- ayarlar ---
INSTALL_DIR="${INSTALL_DIR:-/opt/remnanode}"
SITE_ROOT_BASE="${SITE_ROOT_BASE:-/var/www/selfsteal}"
ACME_ROOT="${ACME_ROOT:-/var/www/letsencrypt}"
NGINX_CONF="${NGINX_CONF:-/etc/nginx/conf.d/selfsteal.conf}"
LE_LIVE_DIR="${LE_LIVE_DIR:-/etc/letsencrypt/live}"
OUT_BASE="${OUT_BASE:-/root/remnawave-node}"
LOG_FILE="${LOG_FILE:-/var/log/remnawave-selfsteal-install.log}"
TARGET_PORT="9443"

DOMAIN="${DOMAIN:-}"
EMAIL="${EMAIL:-}"
COMPOSE_FILE=""
PRIVATE_KEY="${PRIVATE_KEY:-}"
INBOUND_TAG=""
PANEL_IP="${PANEL_IP:-}"
ASSUME_YES=0
SKIP_DNS_CHECK=0

COMPOSE_MODE="new"          # new | keep
COMPOSE_TMP=""
NODE_PORT=""
NODE_CONTAINER="remnanode"
PUBLIC_KEY=""
SHORT_ID=""
PUBLIC_IP=""
UFW_ACTIVE=0

# ------------------------------------------------------------- yardımcılar ---
if [[ -t 1 ]]; then
  R=$'\e[31m'; G=$'\e[32m'; Y=$'\e[33m'; B=$'\e[34m'; C=$'\e[36m'; W=$'\e[1m'; N=$'\e[0m'
else
  R=""; G=""; Y=""; B=""; C=""; W=""; N=""
fi

info() { printf '%s[*]%s %s\n' "$B" "$N" "$*"; }
ok()   { printf '%s[✓]%s %s\n' "$G" "$N" "$*"; }
warn() { printf '%s[!]%s %s\n' "$Y" "$N" "$*"; }
die()  { printf '%s[✗]%s %s\n' "$R" "$N" "$*" >&2; exit 1; }
step() { printf '\n%s==> %s%s\n' "$W$C" "$*" "$N"; }

trap 'die "Beklenmeyen hata (satır $LINENO): $BASH_COMMAND — ayrıntı: $LOG_FILE"' ERR

# Komutu çalıştırır, çıktısını log dosyasına yazar; hata olursa son satırları gösterir.
run() {
  if ! "$@" >>"$LOG_FILE" 2>&1; then
    printf '%s--- %s (son 20 satır) ---%s\n' "$Y" "$LOG_FILE" "$N" >&2
    tail -n 20 "$LOG_FILE" >&2 || true
    die "Komut başarısız: $*"
  fi
}

ask() {
  local prompt="$1" default="${2:-}" answer
  if [[ -n "$default" ]]; then
    read -r -p "$prompt [$default]: " answer </dev/tty
    printf '%s' "${answer:-$default}"
  else
    read -r -p "$prompt: " answer </dev/tty
    printf '%s' "$answer"
  fi
}

confirm() {
  [[ $ASSUME_YES -eq 1 ]] && return 0
  local answer
  read -r -p "$1 [e/H]: " answer </dev/tty
  [[ "$answer" =~ ^([eEyY]|evet|Evet|yes|Yes)$ ]]
}

usage() {
  cat <<'EOF'
Kullanım:
  bash <(curl -fsSL https://raw.githubusercontent.com/umytrovshenov-cmd/remnawave-selfsteal-node/main/install.sh) [parametreler]

Parametreler (hepsi opsiyonel; verilmezse sorulur):
  -d, --domain DOMAIN       Bu sunucunun alan adı (A kaydı bu sunucunun IP'sine yönlü olmalı)
  -e, --email EMAIL         Let's Encrypt e-postası
  -c, --compose FILE        Remnawave panelinden alınmış docker-compose.yml dosyası
  -k, --private-key KEY     Mevcut Reality private key (verilmezse yenisi üretilir)
  -t, --tag TAG             Config Profile içindeki inbound etiketi
  -p, --panel-ip IP         UFW aktifse NODE_PORT sadece bu IP'ye açılır
  -y, --yes                 Onay sorularını atla
      --skip-dns-check      Alan adı -> IP kontrolünü atla
  -h, --help                Bu yardım
EOF
}

b64url() { base64 -w0 | tr '+/' '-_' | tr -d '='; }

# ------------------------------------------------------------- argümanlar ---
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -d|--domain)       DOMAIN="${2:-}"; shift 2 ;;
      -e|--email)        EMAIL="${2:-}"; shift 2 ;;
      -c|--compose)      COMPOSE_FILE="${2:-}"; shift 2 ;;
      -k|--private-key)  PRIVATE_KEY="${2:-}"; shift 2 ;;
      -t|--tag)          INBOUND_TAG="${2:-}"; shift 2 ;;
      -p|--panel-ip)     PANEL_IP="${2:-}"; shift 2 ;;
      -y|--yes)          ASSUME_YES=1; shift ;;
      --skip-dns-check)  SKIP_DNS_CHECK=1; shift ;;
      -h|--help)         usage; exit 0 ;;
      *) die "Bilinmeyen parametre: $1 (yardım için -h)" ;;
    esac
  done
}

# ---------------------------------------------------------- ön kontroller ---
preflight() {
  [[ $EUID -eq 0 ]] || die "Bu script root olarak çalıştırılmalı (önce: sudo -i)."
  touch "$LOG_FILE" && chmod 600 "$LOG_FILE"
  echo "===== $(date -Is) install.sh v$SCRIPT_VERSION =====" >>"$LOG_FILE"

  local os_id os_ver
  os_id="$(. /etc/os-release && echo "${ID:-}")"
  os_ver="$(. /etc/os-release && echo "${VERSION_ID:-}")"
  [[ "$os_id" == "ubuntu" ]] || die "Sadece Ubuntu destekleniyor (bulunan: $os_id)."
  case "$os_ver" in
    22.04|24.04) ok "Sistem: Ubuntu $os_ver" ;;
    *) warn "Ubuntu $os_ver test edilmedi (22.04 / 24.04 önerilir)."
       confirm "Yine de devam edilsin mi?" || exit 1 ;;
  esac

  [[ -r /dev/tty ]] || [[ $ASSUME_YES -eq 1 ]] || die "Etkileşimli terminal bulunamadı. Şöyle çalıştır: bash <(curl -fsSL URL)"

  # 80 portu: Let's Encrypt için gerekli. nginx dışında bir program kullanıyorsa dur.
  local port80
  port80="$(ss -Htlnp 'sport = :80' 2>/dev/null | grep -v nginx || true)"
  [[ -z "$port80" ]] || die "80 portu başka bir program tarafından kullanılıyor:
$port80
Önce onu durdur (Let's Encrypt sertifikası için 80 portu gerekli)."

  # 443 portu: sadece Xray (rw-core / xray) kullanabilir.
  local port443
  port443="$(ss -Htlnp 'sport = :443' 2>/dev/null | grep -Ev 'rw-core|xray' || true)"
  if [[ -n "$port443" ]]; then
    warn "443 portu başka bir program tarafından kullanılıyor:"
    echo "$port443"
    confirm "Node 443'ü kullanacak. Devam edilsin mi?" || exit 1
  fi

  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
    UFW_ACTIVE=1
  fi
}

# ------------------------------------------------------------ girdi topla ---
valid_domain() {
  [[ "$1" =~ ^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$ ]]
}

read_compose_paste() {
  COMPOSE_TMP="$(mktemp)"
  printf '\n%sRemnawave panelinde node eklerken gösterilen docker-compose.yml içeriğini kopyalayıp buraya yapıştır.%s\n' "$W" "$N"
  printf "Yapıştırdıktan sonra yeni bir satıra %sEND%s yaz ve Enter'a bas:\n\n" "$W" "$N"
  local line
  while IFS= read -r line </dev/tty; do
    line="${line%$'\r'}"
    [[ "$line" == "END" ]] && break
    printf '%s\n' "$line" >>"$COMPOSE_TMP"
  done
}

validate_compose() {
  local f="$1"
  [[ -s "$f" ]] || die "docker-compose içeriği boş."
  grep -q 'remnawave/node' "$f" || die "Bu bir Remnawave node docker-compose dosyasına benzemiyor (remnawave/node imajı yok)."
  grep -q 'SECRET_KEY' "$f" || die "docker-compose içinde SECRET_KEY bulunamadı. Paneldeki içeriğin tamamını kopyala."
  if ! grep -Eq 'network_mode:[[:space:]]*"?host"?' "$f"; then
    warn "docker-compose içinde 'network_mode: host' yok. Self-steal hedefi (127.0.0.1:$TARGET_PORT) için host ağı gerekli."
    confirm "Yine de devam edilsin mi?" || exit 1
  fi
  NODE_PORT="$(grep -Eo '(NODE_PORT|APP_PORT)[=:][[:space:]]*"?[0-9]+' "$f" | grep -Eo '[0-9]+$' | head -n1 || true)"
  NODE_PORT="${NODE_PORT:-2222}"
  local cname
  cname="$(grep -E '^[[:space:]]*container_name:' "$f" | head -n1 | awk '{print $2}' | tr -d "\"'" || true)"
  NODE_CONTAINER="${cname:-remnanode}"
}

collect_inputs() {
  step "Bilgiler"

  while true; do
    [[ -n "$DOMAIN" ]] || DOMAIN="$(ask "Bu sunucunun alan adı (örn. learning.ornek.com)")"
    DOMAIN="$(printf '%s' "$DOMAIN" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
    valid_domain "$DOMAIN" && break
    warn "Geçersiz alan adı: '$DOMAIN'"
    DOMAIN=""
    [[ $ASSUME_YES -eq 1 ]] && die "Geçerli bir alan adı ver (-d)."
  done
  if [[ "$DOMAIN" =~ (vpn|proxy|xray|v2ray|vless|reality|node|tunnel) ]]; then
    warn "Alan adında dikkat çekici bir kelime var ($DOMAIN). SNI açık metin olarak görünür; sıradan bir ad önerilir."
    confirm "Bu alan adıyla devam edilsin mi?" || exit 1
  fi

  if [[ -z "$EMAIL" && $ASSUME_YES -eq 0 ]]; then
    EMAIL="$(ask "Let's Encrypt e-postası (boş bırakılabilir)" "")"
  fi

  if [[ -n "$COMPOSE_FILE" ]]; then
    [[ -f "$COMPOSE_FILE" ]] || die "Dosya bulunamadı: $COMPOSE_FILE"
    COMPOSE_TMP="$(mktemp)"; cp "$COMPOSE_FILE" "$COMPOSE_TMP"
  elif [[ -f "$INSTALL_DIR/docker-compose.yml" ]] && grep -q 'remnawave/node' "$INSTALL_DIR/docker-compose.yml" \
       && confirm "Mevcut $INSTALL_DIR/docker-compose.yml bulundu. Aynen kullanılsın mı?"; then
    COMPOSE_MODE="keep"
  else
    read_compose_paste
  fi
  if [[ "$COMPOSE_MODE" == "keep" ]]; then
    validate_compose "$INSTALL_DIR/docker-compose.yml"
  else
    validate_compose "$COMPOSE_TMP"
  fi

  if [[ -z "$PRIVATE_KEY" && $ASSUME_YES -eq 0 ]]; then
    PRIVATE_KEY="$(ask "Mevcut Reality private key (boş bırak = yenisi üretilsin)" "")"
  fi
  if [[ -n "$PRIVATE_KEY" ]]; then
    [[ "$PRIVATE_KEY" =~ ^[A-Za-z0-9_-]{43}$ ]] || die "Private key formatı hatalı (43 karakterlik base64url olmalı)."
  fi

  local default_tag
  default_tag="SS-$(printf '%s' "$DOMAIN" | tr '.' '-')"
  if [[ -z "$INBOUND_TAG" ]]; then
    if [[ $ASSUME_YES -eq 1 ]]; then INBOUND_TAG="$default_tag"
    else INBOUND_TAG="$(ask "Inbound etiketi (panelde her node için farklı olmalı)" "$default_tag")"; fi
  fi
  [[ "$INBOUND_TAG" =~ ^[A-Za-z0-9_-]+$ ]] || die "Inbound etiketi sadece harf, rakam, - ve _ içerebilir."

  if [[ $UFW_ACTIVE -eq 1 && -z "$PANEL_IP" && $ASSUME_YES -eq 0 ]]; then
    PANEL_IP="$(ask "UFW aktif. NODE_PORT ($NODE_PORT) sadece panel IP'sine açılsın — panel IP (boş = herkese açık)" "")"
  fi

  step "Özet"
  printf '  Alan adı        : %s\n' "$DOMAIN"
  printf '  E-posta         : %s\n' "${EMAIL:-(yok)}"
  printf '  docker-compose  : %s (NODE_PORT=%s, konteyner=%s)\n' "$([[ $COMPOSE_MODE == keep ]] && echo mevcut || echo yeni)" "$NODE_PORT" "$NODE_CONTAINER"
  printf '  Reality anahtarı: %s\n' "$([[ -n $PRIVATE_KEY ]] && echo 'verilen anahtar' || echo 'yeni üretilecek')"
  printf '  Inbound etiketi : %s\n' "$INBOUND_TAG"
  [[ $UFW_ACTIVE -eq 1 ]] && printf '  UFW             : aktif (panel IP: %s)\n' "${PANEL_IP:-herkes}"
  echo
  confirm "Kurulum başlasın mı?" || exit 1
}

# ------------------------------------------------------------- kurulum -------
install_packages() {
  step "Paketler"
  export DEBIAN_FRONTEND=noninteractive
  info "apt güncelleniyor..."
  run apt-get update -y
  info "curl, openssl, nginx, certbot, dnsutils kuruluyor..."
  run apt-get install -y curl ca-certificates openssl nginx certbot dnsutils iproute2 python3
  ok "Paketler hazır"
}

get_public_ip() {
  local url ip
  for url in https://api.ipify.org https://ipv4.icanhazip.com https://ifconfig.me/ip; do
    ip="$(curl -4 -fsS --max-time 6 "$url" 2>/dev/null | tr -d '[:space:]' || true)"
    if [[ "$ip" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; then printf '%s' "$ip"; return 0; fi
  done
  return 1
}

check_dns() {
  step "DNS kontrolü"
  PUBLIC_IP="$(get_public_ip || true)"
  [[ -n "$PUBLIC_IP" ]] && info "Sunucunun genel IP'si: $PUBLIC_IP" || warn "Genel IP tespit edilemedi."
  [[ $SKIP_DNS_CHECK -eq 1 ]] && { warn "DNS kontrolü atlandı."; return 0; }

  local resolved
  resolved="$(dig +short A "$DOMAIN" @1.1.1.1 2>/dev/null | grep -E '^[0-9.]+$' || true)"
  [[ -n "$resolved" ]] || resolved="$(getent ahostsv4 "$DOMAIN" 2>/dev/null | awk '{print $1}' | sort -u || true)"
  [[ -n "$resolved" ]] || die "$DOMAIN çözülemedi. DNS panelinde A kaydını ekle (Cloudflare kullanıyorsan gri bulut / DNS only) ve birkaç dakika sonra tekrar dene."

  info "$DOMAIN -> $(echo "$resolved" | tr '\n' ' ')"
  if [[ -n "$PUBLIC_IP" ]] && ! grep -qx "$PUBLIC_IP" <<<"$resolved"; then
    warn "$DOMAIN bu sunucunun IP'sine ($PUBLIC_IP) çıkmıyor!"
    warn "Self-steal'in amacı SNI ile IP'nin tutarlı olması. A kaydını düzelt; Cloudflare'de proxy (turuncu bulut) kapalı olmalı."
    confirm "Yine de devam edilsin mi?" || exit 1
  else
    ok "Alan adı bu sunucuya yönlü"
  fi
}

enable_bbr() {
  step "BBR"
  modprobe tcp_bbr 2>/dev/null || true
  cat >/etc/sysctl.d/99-remnanode-bbr.conf <<'EOF'
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
  sysctl -p /etc/sysctl.d/99-remnanode-bbr.conf >>"$LOG_FILE" 2>&1 || true
  if [[ "$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)" == "bbr" ]]; then
    ok "BBR aktif"
  else
    warn "BBR etkinleştirilemedi (çekirdek desteklemiyor olabilir)."
  fi
}

# -------------------------------------------------------------- sahte site ---
brand_from_domain() {
  local -a l
  IFS=. read -r -a l <<<"$DOMAIN"
  local n=${#l[@]} raw out="" w
  raw="${l[n-2]}"
  if [[ $n -ge 3 && "$raw" =~ ^(co|com|net|org|gov|edu|ac|or|ne|go)$ ]]; then raw="${l[n-3]}"; fi
  raw="${raw//-/ }"
  for w in $raw; do out+="${w^} "; done
  printf '%s' "${out% }"
}

site_css() {
  local accent="$1"
  cat <<EOF
:root{--accent:${accent};--text:#1f2328;--muted:#656d76;--bg:#ffffff;--soft:#f6f8fa;--line:#e5e7eb}
@media (prefers-color-scheme:dark){:root{--text:#e6edf3;--muted:#9198a1;--bg:#0d1117;--soft:#161b22;--line:#30363d}}
*{box-sizing:border-box}html,body{margin:0}
body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;color:var(--text);background:var(--bg);line-height:1.65}
a{color:var(--accent);text-decoration:none}a:hover{text-decoration:underline}
.wrap{max-width:860px;margin:0 auto;padding:0 20px}
header{border-bottom:1px solid var(--line)}header .wrap{display:flex;justify-content:space-between;align-items:center;height:64px}
.logo{font-weight:700;font-size:1.1rem;color:var(--text)}nav a{margin-left:18px;color:var(--muted)}
main{padding:40px 0 60px}h1{font-size:2rem;line-height:1.25;margin:0 0 12px}h2{margin-top:36px}
.muted{color:var(--muted)}.card{background:var(--soft);border:1px solid var(--line);border-radius:10px;padding:18px 20px;margin:14px 0}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:16px}
.btn{display:inline-block;background:var(--accent);color:#fff;padding:10px 18px;border-radius:8px;margin-top:10px}
footer{border-top:1px solid var(--line);padding:24px 0;color:var(--muted);font-size:.9rem}
.layout{display:grid;grid-template-columns:200px 1fr;gap:32px}.side a{display:block;padding:4px 0;color:var(--muted)}
@media (max-width:700px){.layout{grid-template-columns:1fr}}
EOF
}

page() { # page FILE TITLE BODY
  local file="$1" title="$2" body="$3"
  cat >"$file" <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${title}</title>
<meta name="description" content="${SITE_TITLE}">
<link rel="stylesheet" href="/assets/style.css">
</head>
<body>
<header><div class="wrap"><a class="logo" href="/">${SITE_TITLE}</a><nav>${NAV}</nav></div></header>
<main><div class="wrap">
${body}
</div></main>
<footer><div class="wrap">&copy; ${YEAR} ${SITE_TITLE}</div></footer>
</body>
</html>
EOF
}

site_notes() {
  SITE_TITLE="${BRAND} Notes"
  NAV='<a href="/">Posts</a><a href="/about.html">About</a>'
  mkdir -p "$SITE_ROOT/posts"
  local d1 d2 d3
  d1="$(date -d '-9 days' +%Y-%m-%d)"; d2="$(date -d '-23 days' +%Y-%m-%d)"; d3="$(date -d '-47 days' +%Y-%m-%d)"
  page "$SITE_ROOT/index.html" "$SITE_TITLE" "<h1>Notes on learning things slowly</h1>
<p class=\"muted\">Short write-ups about machine learning, programming and study habits.</p>
<div class=\"card\"><a href=\"/posts/gradient-descent.html\"><strong>A gentle look at gradient descent</strong></a><div class=\"muted\">${d1}</div></div>
<div class=\"card\"><a href=\"/posts/reading-list.html\"><strong>Keeping a reading list that actually works</strong></a><div class=\"muted\">${d2}</div></div>
<div class=\"card\"><a href=\"/posts/small-cli-tools.html\"><strong>Writing small command-line tools</strong></a><div class=\"muted\">${d3}</div></div>"
  page "$SITE_ROOT/posts/gradient-descent.html" "A gentle look at gradient descent — $SITE_TITLE" "<h1>A gentle look at gradient descent</h1><p class=\"muted\">${d1}</p>
<p>Gradient descent is the workhorse behind most of modern machine learning. The idea is simple: compute how the loss changes when each parameter changes, then take a small step in the opposite direction.</p>
<p>The learning rate decides the size of that step. Too large and the loss jumps around; too small and training takes forever. In practice a schedule that starts larger and slowly decays works well.</p>
<p>Variants such as momentum and Adam keep a running memory of previous gradients, which smooths the path and usually converges faster on noisy problems.</p>"
  page "$SITE_ROOT/posts/reading-list.html" "Keeping a reading list that actually works — $SITE_TITLE" "<h1>Keeping a reading list that actually works</h1><p class=\"muted\">${d2}</p>
<p>Most reading lists grow faster than they shrink. What helped me was splitting the list into three parts: now, next and maybe.</p>
<p>Only three items are allowed in <em>now</em>. Everything else waits. Once a month the <em>maybe</em> list gets cleaned up without guilt.</p>"
  page "$SITE_ROOT/posts/small-cli-tools.html" "Writing small command-line tools — $SITE_TITLE" "<h1>Writing small command-line tools</h1><p class=\"muted\">${d3}</p>
<p>Small tools that do one thing are easy to test and easy to throw away. Start with a clear input and output, print helpful errors, and keep configuration in one place.</p>
<p>A short README with two or three examples is often more useful than long documentation.</p>"
  page "$SITE_ROOT/about.html" "About — $SITE_TITLE" "<h1>About</h1><p>This is a personal notebook. Posts are written mainly as a way to understand things better.</p>"
}

site_studio() {
  SITE_TITLE="${BRAND} Studio"
  NAV='<a href="/#work">Work</a><a href="/#contact">Contact</a>'
  page "$SITE_ROOT/index.html" "$SITE_TITLE — small web projects" "<h1>We build small, fast web projects.</h1>
<p class=\"muted\">Websites, simple internal tools and prototypes for small teams.</p>
<a class=\"btn\" href=\"#contact\">Get in touch</a>
<h2 id=\"services\">What we do</h2>
<div class=\"grid\">
<div class=\"card\"><strong>Websites</strong><p class=\"muted\">Clean, lightweight sites that load quickly on any device.</p></div>
<div class=\"card\"><strong>Internal tools</strong><p class=\"muted\">Dashboards and small apps that remove repetitive work.</p></div>
<div class=\"card\"><strong>Prototypes</strong><p class=\"muted\">Quick experiments to test an idea before investing more.</p></div>
</div>
<h2 id=\"work\">Recent work</h2>
<div class=\"grid\">
<div class=\"card\"><strong>Booking page</strong><p class=\"muted\">A simple scheduling page for a local studio.</p></div>
<div class=\"card\"><strong>Inventory sheet</strong><p class=\"muted\">A lightweight stock tracker for a small shop.</p></div>
</div>
<h2 id=\"contact\">Contact</h2>
<p>New projects are currently by referral only. Please check back later.</p>"
}

site_docs() {
  SITE_TITLE="${BRAND} Docs"
  NAV='<a href="/">Docs</a><a href="/faq.html">FAQ</a>'
  local side='<div class="side"><a href="/">Overview</a><a href="/getting-started.html">Getting started</a><a href="/faq.html">FAQ</a></div>'
  page "$SITE_ROOT/index.html" "$SITE_TITLE" "<div class=\"layout\">${side}<div><h1>Overview</h1>
<p>This documentation describes an internal project that is still in early development.</p>
<p>Start with <a href=\"/getting-started.html\">Getting started</a> to set up a local environment.</p></div></div>"
  page "$SITE_ROOT/getting-started.html" "Getting started — $SITE_TITLE" "<div class=\"layout\">${side}<div><h1>Getting started</h1>
<p>Clone the repository, install the dependencies and run the development server.</p>
<div class=\"card\"><code>make setup &amp;&amp; make dev</code></div>
<p>The server starts on port 8080 by default.</p></div></div>"
  page "$SITE_ROOT/faq.html" "FAQ — $SITE_TITLE" "<div class=\"layout\">${side}<div><h1>FAQ</h1>
<p><strong>Is this project public?</strong><br>Not yet. A public release is planned later.</p>
<p><strong>Where can I report issues?</strong><br>Please use the internal tracker.</p></div></div>"
}

setup_site() {
  step "Web sitesi"
  SITE_ROOT="$SITE_ROOT_BASE/$DOMAIN"
  if [[ -f "$SITE_ROOT/index.html" ]]; then
    ok "Mevcut site korunuyor: $SITE_ROOT"
    return 0
  fi
  mkdir -p "$SITE_ROOT/assets"
  BRAND="$(brand_from_domain)"; YEAR="$(date +%Y)"
  local accents=("#2563eb" "#0f766e" "#7c3aed" "#c2410c" "#0369a1" "#be123c" "#4d7c0f")
  site_css "${accents[RANDOM % ${#accents[@]}]}" >"$SITE_ROOT/assets/style.css"
  case $((RANDOM % 3)) in
    0) site_notes ;;
    1) site_studio ;;
    2) site_docs ;;
  esac
  page "$SITE_ROOT/404.html" "Not found — $SITE_TITLE" "<h1>Page not found</h1><p><a href=\"/\">Back to home</a></p>"
  printf 'User-agent: *\nAllow: /\n' >"$SITE_ROOT/robots.txt"
  chmod -R a+rX "$SITE_ROOT_BASE"
  ok "Site oluşturuldu: $SITE_TITLE ($SITE_ROOT)"
  info "İstersen $SITE_ROOT içindeki dosyaları kendi içeriğinle değiştirebilirsin."
}

# ---------------------------------------------------------------- nginx -----
ipv6_listen() { [[ -f /proc/net/if_inet6 ]] && printf '    listen [::]:80 default_server;\n' || true; }

write_nginx_http_only() {
  cat >"$NGINX_CONF" <<EOF
# remnawave-selfsteal-node — $DOMAIN (geçici: sadece HTTP / ACME)
server {
    listen 80 default_server;
$(ipv6_listen)
    server_name _;
    server_tokens off;
    location /.well-known/acme-challenge/ { root ${ACME_ROOT}; }
    location / { return 301 https://\$host\$request_uri; }
}
EOF
}

write_nginx_full() {
  cat >"$NGINX_CONF" <<EOF
# remnawave-selfsteal-node — $DOMAIN
# Reality hedefi: Xray, doğrulanmamış bağlantıları buraya (127.0.0.1:${TARGET_PORT}) yönlendirir.
server {
    listen 127.0.0.1:${TARGET_PORT} ssl http2;
    server_name ${DOMAIN};
    server_tokens off;

    ssl_certificate     ${LE_LIVE_DIR}/${DOMAIN}/fullchain.pem;
    ssl_certificate_key ${LE_LIVE_DIR}/${DOMAIN}/privkey.pem;
    ssl_protocols TLSv1.3;
    ssl_session_cache shared:SelfSteal:10m;
    ssl_session_timeout 1d;

    root ${SITE_ROOT_BASE}/${DOMAIN};
    index index.html;
    error_page 404 /404.html;
    location / { try_files \$uri \$uri/ =404; }
}

server {
    listen 80 default_server;
$(ipv6_listen)
    server_name _;
    server_tokens off;
    location /.well-known/acme-challenge/ { root ${ACME_ROOT}; }
    location / { return 301 https://\$host\$request_uri; }
}
EOF
}

setup_nginx_http() {
  step "nginx (HTTP)"
  rm -f /etc/nginx/sites-enabled/default
  mkdir -p "$ACME_ROOT"
  write_nginx_http_only
  run nginx -t
  run systemctl enable nginx
  run systemctl restart nginx
  ok "nginx 80 portunda çalışıyor"
}

issue_certificate() {
  step "Let's Encrypt sertifikası"
  local email_args=(--register-unsafely-without-email)
  [[ -n "$EMAIL" ]] && email_args=(-m "$EMAIL")
  if ! certbot certonly --webroot -w "$ACME_ROOT" -d "$DOMAIN" --cert-name "$DOMAIN" \
        "${email_args[@]}" --agree-tos --non-interactive --keep-until-expiring \
        --deploy-hook "systemctl reload nginx" >>"$LOG_FILE" 2>&1; then
    tail -n 15 "$LOG_FILE" >&2 || true
    die "Sertifika alınamadı. Kontrol et: (1) A kaydı bu sunucuya yönlü mü, (2) bulut firewall'unda 80 portu açık mı. Ayrıntı: $LOG_FILE"
  fi
  [[ -f "$LE_LIVE_DIR/$DOMAIN/fullchain.pem" ]] || die "Sertifika dosyası bulunamadı: $LE_LIVE_DIR/$DOMAIN/fullchain.pem"
  ok "Sertifika hazır (otomatik yenileme açık)"
}

setup_nginx_tls() {
  step "nginx (HTTPS hedef, 127.0.0.1:$TARGET_PORT)"
  write_nginx_full
  run nginx -t
  run systemctl restart nginx
  local code
  code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 \
          --resolve "$DOMAIN:$TARGET_PORT:127.0.0.1" "https://$DOMAIN:$TARGET_PORT/" 2>>"$LOG_FILE" || true)"
  [[ "$code" == "200" ]] || die "nginx testi başarısız (HTTP $code). Ayrıntı: $LOG_FILE"
  ok "Sahte site 127.0.0.1:$TARGET_PORT üzerinde çalışıyor (HTTP 200)"
}

# --------------------------------------------------------------- docker -----
install_docker() {
  step "Docker"
  if ! command -v docker >/dev/null 2>&1; then
    info "Docker kuruluyor (get.docker.com)..."
    local tmp; tmp="$(mktemp)"
    run curl -fsSL https://get.docker.com -o "$tmp"
    run sh "$tmp"
    rm -f "$tmp"
  fi
  run systemctl enable --now docker
  if ! docker compose version >/dev/null 2>&1; then
    apt-get install -y docker-compose-plugin >>"$LOG_FILE" 2>&1 || run apt-get install -y docker-compose-v2
  fi
  ok "Docker hazır ($(docker --version | awk '{print $3}' | tr -d ','))"
}

deploy_node() {
  step "Remnawave Node"
  mkdir -p "$INSTALL_DIR"
  if [[ "$COMPOSE_MODE" == "new" ]]; then
    if [[ -f "$INSTALL_DIR/docker-compose.yml" ]]; then
      cp "$INSTALL_DIR/docker-compose.yml" "$INSTALL_DIR/docker-compose.yml.bak.$(date +%s)"
    fi
    install -m 600 "$COMPOSE_TMP" "$INSTALL_DIR/docker-compose.yml"
    rm -f "$COMPOSE_TMP"
  fi
  info "İmaj indiriliyor ve node başlatılıyor..."
  run docker compose -f "$INSTALL_DIR/docker-compose.yml" pull
  run docker compose -f "$INSTALL_DIR/docker-compose.yml" up -d --remove-orphans
  sleep 3
  docker ps --format '{{.Names}}' | grep -qx "$NODE_CONTAINER" \
    || die "Node konteyneri ($NODE_CONTAINER) çalışmıyor. Kontrol: docker logs $NODE_CONTAINER"
  local mode
  mode="$(docker inspect -f '{{.HostConfig.NetworkMode}}' "$NODE_CONTAINER" 2>/dev/null || true)"
  [[ "$mode" == "host" ]] || warn "Node konteyneri host ağında değil ($mode). Reality hedefi 127.0.0.1:$TARGET_PORT'a ulaşamayabilir."
  ok "Node çalışıyor (konteyner: $NODE_CONTAINER, NODE_PORT: $NODE_PORT)"
}

setup_firewall() {
  step "Firewall"
  if [[ $UFW_ACTIVE -eq 1 ]]; then
    run ufw allow 80/tcp
    run ufw allow 443/tcp
    if [[ -n "$PANEL_IP" ]]; then
      run ufw allow from "$PANEL_IP" to any port "$NODE_PORT" proto tcp
      ok "UFW: 80, 443 herkese; $NODE_PORT sadece $PANEL_IP'ye açık"
    else
      run ufw allow "$NODE_PORT"/tcp
      ok "UFW: 80, 443, $NODE_PORT açık"
    fi
  else
    info "UFW aktif değil; dokunulmadı."
  fi
  warn "Bulut sağlayıcının firewall'unda (örn. Lightsail → Networking) şu portlar açık olmalı: 80, 443, $NODE_PORT"
  warn "Güvenlik için $NODE_PORT portunu sadece panel sunucusunun IP'sine açman önerilir."
}

# ---------------------------------------------------------------- reality ---
x25519_pub_from_priv() { # base64url private -> base64url public
  local p="$1" std
  std="$(printf '%s' "$p" | tr '_-' '/+')"
  case $(( ${#std} % 4 )) in 2) std+="==" ;; 3) std+="=" ;; esac
  { printf '\x30\x2e\x02\x01\x00\x30\x05\x06\x03\x2b\x65\x6e\x04\x22\x04\x20'
    printf '%s' "$std" | base64 -d; } \
    | openssl pkey -inform DER -pubout -outform DER 2>/dev/null | tail -c 32 | b64url
}

generate_reality_material() {
  step "Reality anahtarları"
  local prev="$OUT_BASE/$DOMAIN/config-profile.json" prev_key="" prev_sid=""
  if [[ -z "$PRIVATE_KEY" && -f "$prev" ]]; then
    prev_key="$(python3 -c 'import json,sys;r=json.load(open(sys.argv[1]))["inbounds"][0]["streamSettings"]["realitySettings"];print(r["privateKey"])' "$prev" 2>/dev/null || true)"
    prev_sid="$(python3 -c 'import json,sys;r=json.load(open(sys.argv[1]))["inbounds"][0]["streamSettings"]["realitySettings"];print(r["shortIds"][0])' "$prev" 2>/dev/null || true)"
    if [[ -n "$prev_key" && -n "$prev_sid" ]] && confirm "Bu alan adı için önceki kurulumun anahtarı ve shortId'si bulundu. Aynen kullanılsın mı? (Panelde değişiklik gerekmez)"; then
      PRIVATE_KEY="$prev_key"; SHORT_ID="$prev_sid"
    fi
  fi
  if [[ -z "$PRIVATE_KEY" ]]; then
    local pem; pem="$(mktemp)"
    openssl genpkey -algorithm X25519 -out "$pem" 2>/dev/null
    PRIVATE_KEY="$(openssl pkey -in "$pem" -outform DER | tail -c 32 | b64url)"
    rm -f "$pem"
    ok "Yeni X25519 anahtar çifti üretildi"
  else
    ok "Mevcut private key kullanılıyor"
  fi
  PUBLIC_KEY="$(x25519_pub_from_priv "$PRIVATE_KEY")"
  [[ ${#PUBLIC_KEY} -eq 43 ]] || die "Public key hesaplanamadı; private key hatalı olabilir."
  if [[ -z "$SHORT_ID" ]]; then
    SHORT_ID="$(openssl rand -hex 8)"
    ok "shortId üretildi"
  else
    ok "Önceki shortId kullanılıyor"
  fi
}

write_profile() {
  step "Config Profile"
  local out="$OUT_BASE/$DOMAIN"
  mkdir -p "$out"; chmod 700 "$OUT_BASE" "$out"
  PROFILE_FILE="$out/config-profile.json"
  cat >"$PROFILE_FILE" <<EOF
{
  "log": { "loglevel": "none" },
  "inbounds": [
    {
      "tag": "${INBOUND_TAG}",
      "port": 443,
      "listen": "0.0.0.0",
      "protocol": "vless",
      "settings": { "clients": [], "decryption": "none" },
      "sniffing": { "enabled": true, "routeOnly": true, "destOverride": ["http", "tls", "quic"] },
      "streamSettings": {
        "network": "raw",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "xver": 0,
          "target": "127.0.0.1:${TARGET_PORT}",
          "serverNames": ["${DOMAIN}"],
          "privateKey": "${PRIVATE_KEY}",
          "shortIds": ["${SHORT_ID}"]
        }
      }
    }
  ],
  "outbounds": [
    { "tag": "DIRECT", "protocol": "freedom" },
    { "tag": "BLOCK", "protocol": "blackhole" }
  ],
  "routing": {
    "rules": [
      { "ip": ["geoip:private"], "outboundTag": "BLOCK" },
      { "domain": ["geosite:private"], "outboundTag": "BLOCK" },
      { "protocol": ["bittorrent"], "outboundTag": "BLOCK" },
      { "domain": ["domain:gstatic.com", "domain:google.com", "domain:googleapis.cn", "domain:cloudflare.com"], "outboundTag": "DIRECT" },
      { "ip": ["geoip:cn"], "outboundTag": "BLOCK" },
      { "domain": ["geosite:cn"], "outboundTag": "BLOCK" }
    ]
  }
}
EOF
  python3 -m json.tool "$PROFILE_FILE" >/dev/null 2>&1 || die "Üretilen JSON geçersiz: $PROFILE_FILE"
  chmod 600 "$PROFILE_FILE"

  cat >"$out/node-info.txt" <<EOF
Alan adı (Address + SNI) : ${DOMAIN}
Port                      : 443
Inbound etiketi           : ${INBOUND_TAG}
Reality public key        : ${PUBLIC_KEY}
shortId                   : ${SHORT_ID}
Fingerprint (Host)        : firefox (veya chrome)
NODE_PORT                 : ${NODE_PORT}
Sunucu IP                 : ${PUBLIC_IP:-bilinmiyor}
Oluşturulma               : $(date -Is)
EOF
  chmod 600 "$out/node-info.txt"
  ok "Kaydedildi: $PROFILE_FILE"
}

install_check_tool() {
  cat >/usr/local/bin/selfsteal-check <<'EOF'
#!/usr/bin/env bash
# selfsteal-check [ALAN_ADI] — node + self-steal durum kontrolü
D="${1:-__DOMAIN__}"
G=$'\e[32m'; R=$'\e[31m'; N=$'\e[0m'
chk() { if [[ "$2" == "$3" ]]; then printf '%s[✓]%s %s: %s\n' "$G" "$N" "$1" "$2"; else printf '%s[✗]%s %s: %s (%s)\n' "$R" "$N" "$1" "${2:-hata}" "$4"; fi; }
chk "BBR" "$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)" "bbr" "BBR kapalı"
chk "nginx 127.0.0.1:9443" "$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 --resolve "$D:9443:127.0.0.1" "https://$D:9443/")" "200" "nginx çalışmıyor: systemctl restart nginx"
chk "Xray 443 -> site" "$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 --resolve "$D:443:127.0.0.1" "https://$D/")" "200" "Config Profile node'a atanmamış olabilir"
C="$(docker ps --format '{{.Names}}' 2>/dev/null | grep -m1 -i remna)"
chk "Node konteyneri" "${C:-yok}" "${C:-x}" "docker logs remnanode"
certbot certificates --cert-name "$D" 2>/dev/null | grep -E 'Expiry Date' | sed 's/^ */    sertifika: /'
EOF
  sed -i "s/__DOMAIN__/${DOMAIN}/" /usr/local/bin/selfsteal-check
  chmod 755 /usr/local/bin/selfsteal-check
}

summary() {
  step "Kurulum tamamlandı"
  printf "\n%s1) Remnawave → Config Profiles → yeni profil → bu JSON'u yapıştır:%s\n\n" "$W" "$N"
  cat "$PROFILE_FILE"
  printf "\n%s2) Nodes →%s bu node'a yeni profili ata ve inbound'u (%s) seç.\n" "$W" "$N" "$INBOUND_TAG"
  printf "%s3) Internal Squads →%s %s inbound'unu aç.\n" "$W" "$N" "$INBOUND_TAG"
  printf '%s4) Hosts →%s Address: %s  Port: 443  |  Advanced: SNI: %s  Fingerprint: firefox\n' "$W" "$N" "$DOMAIN" "$DOMAIN"
  printf '%s5) Kontrol:%s profil atandıktan sonra sunucuda %sselfsteal-check%s çalıştır (hepsi ✓ olmalı).\n\n' "$W" "$N" "$W" "$N"
  printf 'Bilgiler: %s\n' "$OUT_BASE/$DOMAIN/node-info.txt"
  printf 'Public key (kontrol için): %s   shortId: %s\n' "$PUBLIC_KEY" "$SHORT_ID"
  printf 'Log: %s\n\n' "$LOG_FILE"
}

main() {
  parse_args "$@"
  printf '%sremnawave-selfsteal-node v%s%s\n' "$W" "$SCRIPT_VERSION" "$N"
  preflight
  collect_inputs
  install_packages
  check_dns
  enable_bbr
  setup_site
  setup_nginx_http
  issue_certificate
  setup_nginx_tls
  install_docker
  deploy_node
  setup_firewall
  generate_reality_material
  write_profile
  install_check_tool
  summary
}

[[ "${INSTALLER_SOURCED:-0}" == "1" ]] || main "$@"
