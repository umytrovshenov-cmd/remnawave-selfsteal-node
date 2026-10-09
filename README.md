# remnawave-selfsteal-node

Remnawave node'larını **Xray Reality "self-steal"** yöntemiyle tek komutla kurmak için script.
Desteklenen sistemler: **Ubuntu 22.04 / 24.04**

Self-steal'de SNI'daki alan adı sunucunun kendi IP'sine çıkar ve sunucuda o alan adına ait gerçek bir HTTPS sitesi çalışır. Dışarıdan bakan biri SNI, IP ve sertifikayı birbiriyle tutarlı görür; sıradan bir web sitesiyle karşılaşır.

## Hızlı kurulum

Sunucuda root olarak çalıştır:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/umytrovshenov-cmd/remnawave-selfsteal-node/main/install.sh)
```

Script sırayla şunları sorar:

1. **Alan adı:** Örneğin `learning.ornek.com`. A kaydı bu sunucunun IP'sine yönlü olmalı.
2. **E-posta:** Let's Encrypt için, boş bırakılabilir.
3. **docker-compose.yml:** Remnawave panelinde node eklerken gösterilen içeriği yapıştır, ardından yeni bir satıra `END` yaz.
4. **Reality private key:** Boş bırakırsan yenisi üretilir.
5. **Inbound etiketi:** Varsayılanı kabul edebilirsin.

Kurulum sonunda panele yapıştıracağın **hazır Config Profile JSON'u** ekrana basılır.

## Ne yapar?

1. **BBR**'ı açar.
2. Rastgele seçilen üç şablondan biriyle **sahte bir web sitesi** oluşturur (blog, stüdyo veya doküman sitesi).
3. **nginx**'i kurar:
   - `127.0.0.1:9443` üzerinde TLS 1.3 + HTTP/2 ile siteyi sunar. Bu adres Reality'nin hedefidir.
   - 80 portundan HTTPS'e yönlendirir; Let's Encrypt doğrulaması da bu port üzerinden yapılır.
4. **Let's Encrypt** sertifikası alır. Sertifika otomatik yenilenir ve yenilenince nginx yeniden yüklenir.
5. **Docker**'ı kurar ve **Remnawave Node**'u yapıştırdığın docker-compose ile başlatır.
6. UFW aktifse 80, 443 ve NODE_PORT portlarını açar.
7. **Reality anahtarı ve shortId** üretir, hazır Config Profile JSON'unu oluşturur.
8. Durum kontrolü için `selfsteal-check` komutunu kurar.

## Gereksinimler

- Ubuntu 22.04 veya 24.04, root erişimi.
- Alan adının **A kaydı sunucunun IP'sine** yönlü olmalı. Cloudflare kullanıyorsan proxy kapalı olmalı (gri bulut, "DNS only").
- Bulut sağlayıcının firewall'unda (örn. Lightsail → Networking) şu portlar açık olmalı:
  - `80`
  - `443`
  - `NODE_PORT` (varsayılan 2222). Bu portu sadece panel sunucusunun IP'sine açman önerilir.
- Alan adında `vpn`, `proxy`, `node` gibi dikkat çekici kelimeler olmamalı. SNI açık metin olarak görünür.

## Parametreler

Hepsi opsiyoneldir; verilmeyenler sorulur.

| Parametre | Açıklama |
|---|---|
| `-d, --domain` | Bu sunucunun alan adı |
| `-e, --email` | Let's Encrypt e-postası |
| `-c, --compose` | docker-compose.yml dosya yolu (yapıştırmak yerine) |
| `-k, --private-key` | Mevcut Reality private key |
| `-t, --tag` | Inbound etiketi (her node için farklı olmalı) |
| `-p, --panel-ip` | UFW aktifse NODE_PORT'u sadece bu IP'ye aç |
| `-y, --yes` | Onay sorularını atla |
| `--skip-dns-check` | Alan adı → IP kontrolünü atla |

Etkileşimsiz örnek:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/umytrovshenov-cmd/remnawave-selfsteal-node/main/install.sh) \
  -d learning.ornek.com -e mail@ornek.com -c /root/compose.yml -y
```

## Kurulumdan sonra

```bash
selfsteal-check          # BBR, nginx, Xray → site ve node konteynerini kontrol eder
cat /root/remnawave-node/<alan-adı>/config-profile.json
cat /root/remnawave-node/<alan-adı>/node-info.txt
```

| Dosya | Açıklama |
|---|---|
| `/opt/remnanode/docker-compose.yml` | Node docker-compose dosyası |
| `/etc/nginx/conf.d/selfsteal.conf` | nginx ayarı |
| `/var/www/selfsteal/<alan-adı>/` | Sahte site; kendi içeriğinle değiştirebilirsin |
| `/root/remnawave-node/<alan-adı>/` | Config Profile JSON ve node bilgileri |
| `/var/log/remnawave-selfsteal-install.log` | Kurulum logu |

**Tekrar çalıştırmak güvenlidir:**
- Mevcut site korunur.
- Sertifika süresi dolmadıysa yeniden alınmaz.
- Önceki anahtar ve shortId tekrar kullanılabilir; panelde değişiklik gerekmez.

## Dokümanlar

- [Tek sunucu kurulumu](docs/01-tek-sunucu.md): panelde node ekleme → script → Config Profile → Host
- [Grup sunucu (balancer + otomatik yedek)](docs/02-grup-sunucu.md): birden fazla sunucuyu müşteriye tek sunucu olarak gösterme
- [Sorun giderme](docs/03-sorun-giderme.md)

## Şablonlar

| Dosya | Nerede kullanılır |
|---|---|
| `templates/xray-json-china.json` | Subscription → Templates → Xray JSON (varsayılan template) |
| `templates/xray-json-balancer.json` | Grup sunucu için ayrı template |
| `templates/config-profile-selfsteal.example.json` | Config Profile örneği (script bunu otomatik doldurur) |

## Lisans

MIT
