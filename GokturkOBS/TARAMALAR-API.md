# Taramalar (DBS) API

Bu belge, Akbim Android istemcisinde doğrulanan DBS davranışını ve GokturkOBS entegrasyonunu özetler. Canlı, kimliği doğrulanmış sunucu yanıtı bu geliştirme ortamında kaydedilmemiştir; bu nedenle tüm isteğe bağlı alanlar toleranslı çözümlenir.

## Kimlik doğrulama

- API tabanı: yapılandırılmış OBS kökü + `/obsapi`
- Giriş: `POST /obsapi/auth/login`
- GokturkOBS mevcut `mobileSession` çerezlerini kullanır.
- DBS çağrıları `performRead(for: .mobile)` içinden yapılır; oturum süresi dolduğunda mevcut Keychain tabanlı, tekil ve sınırlı recovery akışı kullanılır.
- Parola, çerez veya öğrenci kaydı loglanmaz.

## Sınav listesi

`GET /obsapi/exam/getExamList`

Sorgu:

- `stuNo`: mobil profildeki öğrenci numarası
- `stuType`: mobil giriş yanıtındaki öğrenci türü; eksikse istek yapılmaz

Yanıt:

- Uygulama başarısı: `success`
- Kayıtlar: `result`
- Alanlar: `examType`, `sinavKod`, `sinavAd`, `sinavTarih`, `point`

Yalnızca `examType` değeri büyük/küçük harf duyarsız olarak `DBS` olan kayıtlar gösterilir. Başlıktan kategori çıkarımı yapılmaz.

## Tarama detayı

`GET /obsapi/exam/dbs/getExamDetail`

Sorgu:

- `examcode`: listedeki `sinavKod`
- `stuNo`: mevcut öğrenci numarası

Yanıt verisi `data` alanındadır. Kullanılan alanlar:

- Dersler ve netler: `lessons`, `ss`, `d`, `y`, `n`
- Puan/derece: `p`, `derece`
- Katılım: `sayi`
- Cevaplar: `examKey`, `answer`

Paralel diziler eşit uzunlukta kabul edilmez; her indeks sınır kontrollüdür. Sayılar JSON number veya string olabilir.

## Kazanım analizi

`GET /obsapi/exam/dbs/getSubjectAnalyse`

Sorgu, detay isteğiyle aynıdır: `examcode` ve `stuNo`.

Yanıt verisi `data` alanındadır. Alanlar:

- `lesson`
- `konuAd`
- `SSay`
- `Dog`
- `Yan`
- `Bas`

`Bas` değeri sunucunun döndürdüğü ölçekte gösterilir; otomatik yüzde dönüşümü yapılmaz. Bu endpoint yalnızca kullanıcı Kazanım sekmesini açtığında çağrılır.

## Doğrulanmamış canlı davranış

Bu ortamda gerçek kullanıcı hesabıyla canlı istek yapılmadı. Özellikle tarih biçimleri, boş-cevap işaretleri, isteğe bağlı puanlar ve bazı sıralama etiketleri sunucuya göre değişebilir. Uygulama değer üretmez; eksik değerleri “—” olarak gösterir ve boş sonuçları uygun empty-state ile sunar.
