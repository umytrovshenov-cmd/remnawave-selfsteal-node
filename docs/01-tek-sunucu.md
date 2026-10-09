# Tek sunucu kurulumu

Bu rehber yeni bir node'u self-steal ile kurup Remnawave'e bağlamayı adım adım anlatır.
Akış: **Panelde node ekle → sunucuda script → panelde Config Profile, Squad ve Host.**

## 0. Hazırlık

**Alan adı**
- Her node için ayrı bir alt alan adı kullan (örn. `learning.ornek.com`, `docs.ornek.com`).
- A kaydı o node'un IP'sine yönlü olsun.
- Cloudflare kullanıyorsan proxy kapalı olsun (gri bulut).

**Firewall**
Bulut sağlayıcının firewall'unda şu portları aç:
- `80` (sertifika doğrulaması ve yönlendirme)
- `443` (VPN)
- `2222` veya panelde belirlediğin NODE_PORT. Mümkünse sadece panel IP'sine açık olsun.

**Xray JSON template (bir kez yapılır)**
1. Subscription → Templates → Xray JSON bölümüne git.
2. Varsayılan template'in içeriğini [`templates/xray-json-china.json`](../templates/xray-json-china.json) ile değiştir.

Bu template'te Çin siteleri ve uygulamaları VPN'siz (direct), geri kalan her şey VPN üzerinden gider. `proxy` outbound'unu Remnawave otomatik ekler; template'e yazmana gerek yok.

## 1. Panelde node ekle

1. Nodes → Management → **+** butonuna bas.
2. Country, Internal name, Address (sunucu IP'si) ve Port (`2222`) alanlarını doldur.
3. **Next**'e bas ve Config Profile olarak şimdilik mevcut herhangi bir profili seç. 4. adımda değiştireceğiz.
4. Panelin gösterdiği **docker-compose.yml** içeriğinin tamamını kopyala.
5. **Create**'e bas.

## 2. Sunucuda scripti çalıştır

```bash
sudo -i
bash <(curl -fsSL https://raw.githubusercontent.com/umytrovshenov-cmd/remnawave-selfsteal-node/main/install.sh)
```

Sorulanlar:

| Soru | Cevap |
|---|---|
| Alan adı | `learning.ornek.com` |
| E-posta | İsteğe bağlı |
| docker-compose | Kopyaladığın içeriği yapıştır, sonra yeni satıra `END` yaz |
| Reality private key | Boş bırak (yenisi üretilir) veya mevcut anahtarını yapıştır |
| Inbound etiketi | Varsayılan (`SS-learning-ornek-com`) |

Kurulum sonunda **Config Profile JSON'u** ekrana basılır. Ayrıca şu dosyaya kaydedilir:
`/root/remnawave-node/<alan-adı>/config-profile.json`

## 3. Config Profile oluştur

1. Config Profiles → **+** butonuna bas.
2. İsim olarak alan adını yazabilirsin.
3. Scriptin verdiği JSON'u yapıştır ve **Save**'e bas.

Profilin içinde neler var:

| Ayar | Açıklama |
|---|---|
| `target: 127.0.0.1:9443` | Doğrulanmamış bağlantılar sunucudaki sahte siteye gider |
| `serverNames` | Bu node'un alan adı |
| gstatic / google istisnası | Happ ping'i ve grup sunucu testleri çalışsın diye |
| `geoip:cn` / `geosite:cn` → BLOCK | Çin trafiğinin yurtdışı sunucudan geri dönmesini engeller. Bu yüzden istemcide Çin template'i kullanılmalı |

## 4. Profili node'a ata

1. Nodes → node'u aç.
2. Config Profile olarak yeni profili seç ve inbound'u işaretle.
3. **Save**'e bas.

## 5. Internal Squad

Internal Squads → kullanıcıların squad'ı → yeni inbound'u aç.

## 6. Host oluştur

Hosts → **+** butonuna bas ve şunları doldur:

| Alan | Değer |
|---|---|
| Remark | Örn. `🇯🇵 Japan 2` |
| Inbound | Yeni inbound |
| Address | `learning.ornek.com` |
| Port | `443` |
| Advanced → SNI | `learning.ornek.com` |
| Advanced → Fingerprint | `firefox` (veya `chrome`) |

## 7. Kontrol

1. Sunucuda `selfsteal-check` çalıştır. Satırların hepsinin başında ✓ görmelisin.
2. VPN kapalıyken tarayıcıda `https://learning.ornek.com` adresini aç. Sahte site görünmeli.
3. Happ'te aboneliği güncelle, yeni sunucuya bağlan ve şu iki adresi kontrol et:
   - `myip.ipip.net` → kendi Çin IP'n görünmeli (Çin trafiği direct gidiyor).
   - `ip.sb` → sunucunun IP'si görünmeli (geri kalan trafik VPN'den gidiyor).

## Notlar

- **Her node için:** farklı alt alan adı, farklı inbound etiketi ve ayrı bir Config Profile kullan.
- **Happ'te ping çok yüksek görünüyorsa:** Ayarlar → Ping → **TCP** seç. "Via Proxy" modu birkaç el sıkışmayı birlikte ölçtüğü için yüksek değer gösterir; bu normaldir.
- **IP engellenirse:**
  1. Sağlayıcıdan yeni IP al.
  2. A kaydını güncelle.
  3. Scripti tekrar çalıştır.

  Host'ta alan adı kullandığın için kullanıcıların bir şey değiştirmesi gerekmez.
