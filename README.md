# 💰 Bakiye — Grup Harcama Takip Uygulaması

> Seyahatlerde ortak harcamaları yönet, kim kime ne kadar borçlu hemen gör.
---

## 📖 Hakkında

**Bakiye**, grup seyahatlerinde ortak masrafları takip etmek için geliştirilmiş hafif ve kullanışlı bir Flutter uygulamasıdır. Tunus seyahatlerini göz önünde bulundurarak **EUR** ve **TND (Tunus Dinarı)** olmak üzere iki para birimini aynı anda destekler.

Karmaşık muhasebe uygulamalarına gerek yok — kim ödedi, kim katıldı, kim ne kadar borçlu; hepsi tek ekranda.

---

## Özellikler

| Özellik | Açıklama |
|---|---|
| **Üye Yönetimi** | Grup üyesi ekle, isim değiştir veya sil |
| **Harcama Takibi** | Açıklama, tutar, para birimi, ödeyen ve katılımcı seç |
| **Çoklu Para Birimi** | EUR ve TND için ayrı ayrı hesaplama |
| **Grup Bütçesi** | EUR ve TND için bütçe gir, kalan miktarı anlık takip et |
| **Net Bakiye** | Her üyenin ödediği ile payı arasındaki farkı görüntüle |
| **Uzlaştırma Önerileri** | Minimum transfer sayısıyla borçları kapatmak için akıllı öneriler |
| **Kalıcı Kayıt** | Tüm veriler cihazda saklanır, internet bağlantısı gerekmez |
| **Kaydır & Sil** | Harcamaları sola kaydırarak hızlıca sil |

---

### Gereksinimler

- [Flutter SDK](https://docs.flutter.dev/get-started/install) ≥ 3.x
- Dart SDK ≥ 3.8.1
- Android Studio / VS Code
- Bağlı Android cihaz veya emülatör

### Adımlar

```bash
# 1. Repoyu klonla
git clone https://github.com/kullanici-adin/bakiye.git
cd bakiye

# 2. Bağımlılıkları yükle
flutter pub get

# 3. Uygulamayı çalıştır
flutter run
```

### APK Derleme (Android)

```bash
flutter build apk --release
# Çıktı: build/app/outputs/flutter-apk/app-release.apk
```

---

## 🏗️ Proje Yapısı

```
bakiye/
├── lib/
│   └── main.dart          # Tüm uygulama (tek dosya mimarisi)
├── android/               # Android platform kodu
├── test/                  # Widget testleri
├── pubspec.yaml           # Bağımlılıklar ve yapılandırma
└── analysis_options.yaml  # Lint kuralları
```

### Kullanılan Mimari & Paketler

| Paket | Amaç |
|---|---|
| [`flutter_bloc`](https://pub.dev/packages/flutter_bloc) | State management (Cubit pattern) |
| [`shared_preferences`](https://pub.dev/packages/shared_preferences) | Yerel veri kalıcılığı |

---

## 🧮 Algoritma

Borç uzlaştırma için **greedy (açgözlü) algoritma** kullanılmaktadır:

1. Her üyenin net bakiyesi hesaplanır: `ödediği - payı`
2. Alacaklılar ve borçlular ayrılır
3. En yüksek borçlu → en yüksek alacaklıya ödeme yaparak minimum transfer sayısına ulaşılır
4. EUR ve TND için hesaplamalar birbirinden tamamen bağımsızdır

---

## 📄 Lisans

Bu proje [MIT Lisansı](LICENSE) ile lisanslanmıştır.

---

