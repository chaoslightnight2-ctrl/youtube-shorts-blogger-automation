# youtube-shorts-blogger-automation

“1 Dakikada Tech Çözüm” için YouTube Shorts + Blogger otomasyon MVP’si. Sistem trend adaylarını toplar, güvenlik filtresinden geçirir, Groq ile veya API yoksa lokal heuristikle puanlar, duplicate guard ile daha önce işlenen sorunları engeller, Türkçe çözüm rehberi üretir, HTML render eder, Blogger’a varsayılan olarak draft gönderir ve Shorts script/metadata çıktısı oluşturur.

## Para kazanma mantığı

Akış: YouTube Shorts trafik sağlar, Blogger yazısı detaylı çözüm verir. Blogger tarafında ileride AdSense, affiliate alanları ve dijital ürün yönlendirmeleri kullanılabilir. İlk sürümde link kısaltıcı, otomatik YouTube upload, otomatik public publish ve AdSense kodu yoktur.

## Kurulum

```bash
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
```

`.env.example` dosyasını `.env` olarak kopyalayın ve değerleri doldurun.

## Groq API

`.env` içine şunları ekleyin:

```env
GROQ_API_KEY=your_groq_api_key_here
GROQ_MODEL=llama-3.1-8b-instant
GROQ_BASE_URL=https://api.groq.com/openai/v1
```

Test:

```bash
python main.py test-groq
```

## Blogger API kurulumu

1. Google Cloud Console’da proje oluşturun.
2. Blogger API v3 etkinleştirin.
3. OAuth Client ID oluşturun.
4. Application type olarak Desktop app seçin.
5. `client_secret.json` dosyasını indirin ve repo köküne koyun.
6. Blogger panelinden blog ID değerini alın ve `.env` içine `BLOGGER_BLOG_ID` olarak yazın.
7. Refresh token kullanacaksanız `.env` içine `GOOGLE_REFRESH_TOKEN` ekleyin. Bu modda sistem `client_secret.json` içindeki `client_id` ve `client_secret` ile access token yeniler; tarayıcı açıp `token.json` üretmesi gerekmez.

```env
BLOGGER_BLOG_ID=your_blogger_blog_id_here
GOOGLE_CLIENT_SECRET_FILE=client_secret.json
GOOGLE_TOKEN_FILE=token.json
GOOGLE_REFRESH_TOKEN=your_google_refresh_token_here
BLOGGER_PUBLISH_MODE=draft
```

`GOOGLE_REFRESH_TOKEN` boş bırakılırsa eski lokal OAuth akışı çalışır ve gerekirse `token.json` üretir. `client_secret.json`, `token.json` ve `.env` git’e eklenmez.

## Komutlar

```bash
python main.py seed-demo
python main.py run --no-blogger
python main.py run
python main.py list-produced
python main.py check-duplicate "Instagram DM gitmiyor"
python main.py test-blogger-auth
python main.py test-groq
```

`python main.py run` Blogger’da draft post oluşturur. Public yayın varsayılan değildir.

## Output dosyaları

Çıktılar `outputs/` altında yazılır:

- `outputs/guides/YYYYMMDD_HHMM_slug.md`
- `outputs/guides/YYYYMMDD_HHMM_slug.html`
- `outputs/scripts/YYYYMMDD_HHMM_slug_script.txt`
- `outputs/metadata/YYYYMMDD_HHMM_slug_metadata.json`
- `outputs/blogger/YYYYMMDD_HHMM_slug_blogger_response.json`

## Duplicate guard

Sistem aynı kullanıcı ihtiyacını tekrar üretmemek için dört katman kullanır: normalize edilmiş metin, canonical slug, RapidFuzz benzerlik ve borderline durumlarda Groq tabanlı AI duplicate kontrolü. Örneğin “Instagram DM gitmiyor” ile “Instagram mesaj gönderilmiyor” duplicate sayılır.

## Güvenlik ve kalite

Riskli konular otomatik elenir: hack, crack, APK, bahis, +18, sağlık, hukuk, siyaset, felaket, kişisel veri ve benzeri alanlar. Ödeme/kart konuları tamamen engellenmez ama `safe_but_sensitive` sayılır; rehberlerde resmi uygulama, limit/internet alışveriş ayarları, şüpheli işlem uyarısı ve resmi destek dili kullanılır.

YouTube kullanımı güvenli olmalıdır: video çözümün çoğunu vermeli, Blogger linki ekstra detay için kullanılmalı, yanıltıcı dış link veya “devamı linkte” spam dili kullanılmamalıdır.

## Blogger draft kontrol akışı

İlk MVP’de tüm postlar draft olarak oluşturulur. Blogger panelinden içeriği okuyup gerekirse düzenledikten sonra manuel yayınlayın. Draft URL dönmezse sistem post ID’yi ve lokal HTML dosyasını kaydeder.

## AdSense notu

AdSense onayı gelmeden reklam kodu eklenmez. Template içinde sadece placeholder yorumları vardır. Kendi reklamınıza tıklamayın, başkalarından tıklama istemeyin ve sahte trafik üretmeyin.

## Gelecek geliştirmeler

- Otomatik YouTube upload
- `--publish-now` seçeneği
- Google Search Console entegrasyonu
- Affiliate link alanları
- Web dashboard

## Test

```bash
pytest -q
```
