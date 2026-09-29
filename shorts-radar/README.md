# Shorts Radar

Flutter ile hazırlanmış kişisel Android kanal takip uygulaması. Android 7.0 ve üzeri.

| Repo | YouTube kanalı |
|---|---|
| denede | ilginçgerçekler · @ilgiçekici15 |
| Haberdenede | türkiyedenhaber · @türkiyedenhaber-v9e |
| Globalhaberdenede | globalhaber · @globalhaber-g7k |
| Quizdenede | zekanıtestet · @zekanıtestet |

Dört kanalın her biri için son 10 yayınlanmış video, ayrı ayrı tam izlenme sayıları, başlık, yayın tarihi ve YouTube bağlantısı gösterilir. Kanal ayrıntısında toplam kanal izlenmesi, abone ve video sayısı da bulunur. Eksik sayaçlar `—` olarak gösterilir. Genel bakıştaki toplam, listelenen son videoların toplamıdır.

Veri doğrudan YouTube'un herkese açık Atom/RSS video akışından alınır. Kanal toplamları herkese açık kanal sayfasından okunur; bu sayfa değişirse ilgili toplamlar geçici olarak kullanılamayabilir. API anahtarı, GitHub token'ı veya YouTube hesabına giriş gerekmez. OAuth sırları APK içinde bulunmaz.

Uygulama açıkken 5 dakikada bir yeniler; elle yenileme de vardır. YouTube önbelleği nedeniyle sayaçlar YouTube Studio'dan gecikebilir. Son kontrol zamanı gösterilir. İnternet kesilirse cihazdaki son veri korunur. `+` değişimi cihazdaki önceki gözleme göredir; saatlik/günlük analytics iddiası değildir. İlk açılış için zaman damgalı gerçek bir kayıt paketlenir. RSS son yüklemeleri döndürür; bu dört kanal Shorts otomasyonuna ait olsa da uzun video eklenirse son video listesinde görünür.

## Derleme

Flutter 3.47.5, Dart 3.13.4, JDK 17, Android SDK 36 kullanıldı.

```sh
flutter create --platforms=android --org com.chaoslightnight --project-name shorts_radar .
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

Çıktı: `build/app/outputs/flutter-apk/app-release.apk`.

Bu kişisel APK, Flutter'ın geliştirme imzasıyla release modunda derlenir. Play Store dağıtımı için ayrı, kalıcı bir release signing key yapılandırılmalıdır. CI yeniden derlemeleri farklı imza oluşturabileceğinden ileride APK güncellemesi önceki kurulumu kaldırmayı gerektirebilir; bu işlem cihazdaki yerel karşılaştırma kaydını siler.

## Veri gizliliği

Uygulama yalnızca YouTube'dan herkese açık kanal/video bilgileri ve küçük resimler alır. Ölçümler ve ayarlar cihazda saklanır. Reklam, üçüncü taraf analytics veya kullanıcı hesabı bulunmaz. Videoya/kanala dokunmak YouTube'u; repo bağlantısı GitHub'ı harici olarak açar.
