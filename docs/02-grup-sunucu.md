# Grup sunucu (balancer + otomatik yedek)

Birden fazla sunucu müşteriye **tek sunucu** olarak görünür. Müşteri bağlandığında aralarından çalışan ve hızlı olanları kullanır.

Remnawave'in Xray JSON `injectHosts` özelliği kullanılır. Kaynak: [docs.rw/learn/xray-json-advanced](https://docs.rw/learn/xray-json-advanced)

## Nasıl çalışır?

- Müşteri Happ'te tek bir sunucu görür (örn. `🇯🇵 Japan`), ama config'in içinde gruptaki bütün sunucular vardır.
- `burstObservatory` her sunucuyu **30 saniyede bir** test eder.
- Balancer yeni bağlantıları sadece testi geçen sunuculara dağıtır.
- Bir sunucu engellenir veya kapanırsa en geç ~30 saniye içinde devre dışı kalır:
  - O sunucudaki açık bağlantılar bir kez kopar.
  - Yeni bağlantılar diğer sunuculardan açılır.
  - Yeni bağlanan müşteriler o sunucuya hiç yönlenmez.
- Bütün sunucular aynı anda düşerse trafik gruptaki ilk sunucuya (`proxy`) gider.

Bu yapı mevcut ayarlara dokunmaz. Template sadece "sanal host"a atanır; diğer host'lar varsayılan template'i kullanmaya devam eder.

## Ön koşul

Gruptaki her node, [tek sunucu rehberinin](01-tek-sunucu.md) **1–5. adımlarıyla** kurulmuş olmalı: script, Config Profile, node'a atama ve Internal Squad.

## 1. Gizli host'lar

Her node için Hosts → **+** butonuna bas:

| Alan | Değer |
|---|---|
| Remark | `JP-1`, `JP-2`, `JP-3` ... (**`JP-` ön eki önemli**) |
| Inbound | O node'un inbound'u |
| Address ve SNI | O node'un alan adı |
| Fingerprint | `firefox` |
| Advanced → **Hide host** | **açık** |

Gizli host'lar abonelikte ayrı ayrı görünmez; sadece gruba eklenir.

> İpucu: Bir node'u hem tek başına hem de grupta göstermek istiyorsan, normal (görünür) host'unu silme. Aynı inbound için ek olarak gizli bir `JP-x` host'u oluştur.

## 2. Grup template'i

1. Subscription → Templates → Xray JSON → **+** butonuna bas.
2. İsim olarak `JP-Balancer` yaz.
3. [`templates/xray-json-balancer.json`](../templates/xray-json-balancer.json) içeriğini yapıştır.
4. **Bu template'i varsayılan (default) yapma.** Sadece sanal host kullanacak.

## 3. Sanal host

Hosts → **+** butonuna bas:

| Alan | Değer |
|---|---|
| Remark | `🇯🇵 Japan` (müşterinin göreceği isim) |
| Inbound | Gruptaki inbound'lardan herhangi biri |
| Address | Gruptaki node'lardan birinin alan adı (Happ'in TCP ping'i bu adresi ölçer) |
| Port | `443` |
| Advanced → **Xray JSON template** | `JP-Balancer` |
| Advanced → Hide host | **kapalı** |

Kullanıcının squad'ında gruptaki **bütün** inbound'lar açık olmalı. Aksi halde o host'lar config'e eklenmez.

## 4. Kontrol

1. Happ'te aboneliği güncelle. Japonya için tek bir `🇯🇵 Japan` görünmeli.
2. YouTube açıkken panelde Nodes → `JP-2`'nin node'unu **Disable** yap. Görüntü birkaç saniye takılıp 30 saniye içinde devam etmeli.
3. Testten sonra node'u tekrar **Enable** yap.

## Yeni sunucu eklemek

1. Node'u tek sunucu rehberiyle kur.
2. Remark'ı `JP-4` olan gizli bir host oluştur.

Template'i değiştirmen gerekmez; `^JP-` ile başlayan bütün gizli host'lar otomatik olarak gruba girer.

## Başka bir ülke grubu

1. `JP-Balancer` template'ini kopyala ve şunları değiştir:
   - `"pattern": "^JP-"` → `"^DE-"`
   - `"JP-Balancer"` (iki yerde) → `"DE-Balancer"`
2. Gizli host'ları `DE-1`, `DE-2` ... adıyla oluştur.
3. Sanal host `🇩🇪 Germany` olsun ve yeni template'i kullansın.

## Parametreler

| Ayar | Değer | Anlamı |
|---|---|---|
| `interval` | `30s` | Sunucular ne sıklıkla test edilir |
| `timeout` | `5s` | Bu sürede cevap gelmezse test başarısız sayılır |
| `destination` | gstatic `generate_204` | Test adresi. Node profillerindeki gstatic istisnası bu yüzden gerekli |
| `maxRTT` | `3s` | Bundan yavaş sunucular seçilmez |
| `expected` | `2` | Trafik en iyi 2 sunucu arasında dağıtılır |
| `fallbackTag` | `proxy` | Hepsi düşerse ilk sunucu kullanılır. Çin'de `direct` yapma; engelli siteler açılmaz |

## Happ ping'i hakkında

Happ'teki ping türü (TCP veya Via Proxy) **sadece ekranda görünen değeri** etkiler. Balancer kendi testini (`burstObservatory`) config'in içinde yapar. Bu yüzden ping'i **TCP** yapmak grubun çalışmasını etkilemez.
