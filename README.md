# youtube-shorts-blogger-automation

“1 Dakikada Tech Çözüm” için YouTube Shorts + Blogger otomasyon MVP’si. Sistem trend adaylarını toplar, güvenlik filtresinden geçirir, Groq ile veya API yoksa lokal heuristikle puanlar, duplicate guard ile daha önce işlenen sorunları engeller, Türkçe çözüm rehberi üretir, HTML render eder, Blogger’a varsayılan olarak draft gönderir, Shorts script/metadata çıktısı oluşturur, Pexels arka plan + TTS + caption ile MP4 render eder ve hazır videoyu YouTube’a yükleyebilir.

## Kurulum

```bash
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
```

`.env.example` dosyasını `.env` olarak kopyalayın ve değerleri doldurun.

## Gerekli API değerleri

```env
GROQ_API_KEY=your_groq_api_key_here
GROQ_MODEL=llama-3.1-8b-instant
GROQ_BASE_URL=https://api.groq.com/openai/v1
PEXELS_API_KEY=your_pexels_api_key_here

BLOGGER_BLOG_ID=your_blogger_blog_id_here
GOOGLE_CLIENT_SECRET_FILE=client_secret.json
GOOGLE_TOKEN_FILE=token.json
GOOGLE_REFRESH_TOKEN=your_google_refresh_token_here
YOUTUBE_REFRESH_TOKEN=your_youtube_refresh_token_here
YOUTUBE_CATEGORY_ID=28
VOICE=tr-TR-AhmetNeural
VOICE_RATE=+8%
VOICE_PITCH=-3Hz
BLOGGER_PUBLISH_MODE=draft
```

Blogger için scope: `https://www.googleapis.com/auth/blogger`

YouTube upload için scope: `https://www.googleapis.com/auth/youtube.upload`

`YOUTUBE_REFRESH_TOKEN` boşsa sistem YouTube için `GOOGLE_REFRESH_TOKEN` değerini kullanmayı dener. Bu durumda refresh token’ın YouTube upload scope’unu da içermesi gerekir.

## Blogger API kurulumu

1. Google Cloud Console’da proje oluşturun.
2. Blogger API v3 etkinleştirin.
3. OAuth Client ID oluşturun.
4. Application type olarak Desktop app seçin.
5. `client_secret.json` dosyasını indirin ve repo köküne koyun.
6. Blogger panelinden blog ID değerini alın ve `.env` içine `BLOGGER_BLOG_ID` olarak yazın.
7. Refresh token kullanacaksanız `.env` içine `GOOGLE_REFRESH_TOKEN` ekleyin. Bu modda sistem `client_secret.json` içindeki `client_id` ve `client_secret` ile access token yeniler; tarayıcı açıp `token.json` üretmesi gerekmez.

`client_secret.json`, `token.json` ve `.env` git’e eklenmez.

## Komutlar

```bash
python main.py seed-demo
python main.py run --no-blogger
python main.py run
python main.py run --publish-now
python main.py render-short --metadata outputs/metadata/YYYYMMDD_HHMM_slug_metadata.json
python main.py upload-short outputs/videos/slug.mp4 --metadata outputs/metadata/YYYYMMDD_HHMM_slug_metadata.json
python main.py upload-short outputs/videos/slug.mp4 --metadata outputs/metadata/YYYYMMDD_HHMM_slug_metadata.json --privacy private --publish-at 2026-05-12T09:00:00+03:00
python main.py list-produced
python main.py check-duplicate "Instagram DM gitmiyor"
python main.py test-blogger-auth
python main.py test-groq
```

`render-short` metadata JSON içindeki script’i Edge TTS ile seslendirir, Pexels’ten dikey arka plan videosu indirir, ortada kısa caption parçaları üretir ve MP4 çıktısını `outputs/videos/` altına yazar.

`upload-short` hazır MP4 dosyasını YouTube Data API ile yükler. `--publish-at` verilirse YouTube kuralı gereği video private olarak zamanlanır.

## Output dosyaları

Çıktılar `outputs/` altında yazılır:

- `outputs/guides/YYYYMMDD_HHMM_slug.md`
- `outputs/guides/YYYYMMDD_HHMM_slug.html`
- `outputs/scripts/YYYYMMDD_HHMM_slug_script.txt`
- `outputs/metadata/YYYYMMDD_HHMM_slug_metadata.json`
- `outputs/videos/slug.mp4`
- `outputs/blogger/YYYYMMDD_HHMM_slug_blogger_response.json`

## Duplicate guard

Sistem aynı kullanıcı ihtiyacını tekrar üretmemek için dört katman kullanır: normalize edilmiş metin, canonical slug, RapidFuzz benzerlik ve borderline durumlarda Groq tabanlı AI duplicate kontrolü. Örneğin “Instagram DM gitmiyor” ile “Instagram mesaj gönderilmiyor” duplicate sayılır.

## Güvenlik ve kalite

Riskli konular otomatik elenir: hack, crack, APK, bahis, +18, sağlık, hukuk, siyaset, felaket, kişisel veri ve benzeri alanlar. Ödeme/kart konuları tamamen engellenmez ama `safe_but_sensitive` sayılır; rehberlerde resmi uygulama, limit/internet alışveriş ayarları, şüpheli işlem uyarısı ve resmi destek dili kullanılır.

YouTube kullanımı güvenli olmalıdır: video çözümün çoğunu vermeli, Blogger linki ekstra detay için kullanılmalı, yanıltıcı dış link veya “devamı linkte” spam dili kullanılmamalıdır.

## AdSense notu

AdSense onayı gelmeden reklam kodu eklenmez. Template içinde sadece placeholder yorumları vardır. Kendi reklamınıza tıklamayın, başkalarından tıklama istemeyin ve sahte trafik üretmeyin.

## Test

```bash
pytest -q
```
