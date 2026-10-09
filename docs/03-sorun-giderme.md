# Sorun giderme

İlk adım her zaman sunucuda şu komutu çalıştırmak:

```bash
selfsteal-check
```

| Satır | ✗ ise ne yapmalı |
|---|---|
| BBR | `sysctl -p /etc/sysctl.d/99-remnanode-bbr.conf` |
| nginx 127.0.0.1:9443 | `systemctl restart nginx` ve `nginx -t`. Hata devam ederse: `journalctl -u nginx -n 50` |
| Xray 443 → site | Config Profile node'a atanmamış, `target` yanlış ya da node konteyneri host ağında değil |
| Node konteyneri | `docker logs remnanode --tail 50` ve `cd /opt/remnanode && docker compose up -d` |

## Sertifika alınamadı

Sırasıyla kontrol et:
1. `dig +short A alan-adı` sunucunun IP'sini veriyor mu?
2. Cloudflare kullanıyorsan proxy kapalı mı (gri bulut)?
3. Bulut firewall'unda 80 portu açık mı?

Yenileme testi için: `certbot renew --dry-run`

## VPN bağlanıyor ama internet yok

- Host'taki **SNI**, profildeki `serverNames` ile aynı olmalı.
- Happ'te aboneliği güncelle. Profildeki `privateKey` veya `shortIds` değiştiyse eski config çalışmaz.
- Sunucu ve cihaz saati doğru olmalı. Reality, saat farkına duyarlıdır.

## Happ'te ping N/A

Node profilinde gstatic istisnası olmalı:

```json
{ "domain": ["domain:gstatic.com", "domain:google.com", "domain:googleapis.cn", "domain:cloudflare.com"], "outboundTag": "DIRECT" }
```

Bu kural `geoip:cn` ve `geosite:cn` engel kurallarından **önce** gelmeli. Gecikmeyi daha düşük ve gerçekçi görmek için Happ → Ayarlar → Ping → **TCP** seçebilirsin.

## WeChat / Alipay yavaş veya açılmıyor

1. İstemcide Çin template'i ([`xray-json-china.json`](../templates/xray-json-china.json)) kullanılmalı.
2. Happ'te aboneliği güncelle ve **bağlantıyı kesip yeniden bağlan**. Değişiklikler ancak yeniden bağlanınca uygulanır.
3. VPN açıkken iki adresi kontrol et:
   - `myip.ipip.net` → Çin IP'n görünmeli.
   - `ip.sb` → sunucunun IP'si görünmeli.

## Akşamları yavaşlama

1. `selfsteal-check` ile BBR'ın açık olduğunu kontrol et.
2. Aynı saatte farklı node'ları karşılaştır. Sadece bir node yavaşsa sorun o sunucunun IP'si veya hattıdır.
3. Yavaş node için çözüm yolları:
   - Sağlayıcıdan yeni IP alıp DNS'i güncelle.
   - Node'u bir grup sunucuya ekle; çalışmayan sunucular otomatik olarak devre dışı kalır.

## Loglar

| Ne | Komut |
|---|---|
| Kurulum logu | `/var/log/remnawave-selfsteal-install.log` |
| Node | `docker logs remnanode --tail 100` |
| nginx | `journalctl -u nginx -n 50` |
| Sertifika | `/var/log/letsencrypt/letsencrypt.log` |
