# AKBİM OBS API Entegrasyon Dokümantasyonu

Bu belge, GöktürkOBS uygulamasının `tedemkolejiobs.com` üzerindeki AKBİM OBS altyapısından veriyi nasıl aldığını, oturumu nasıl yönettiğini ve dönen verileri nasıl yorumladığını açıklar. Belge, mevcut Swift kaynak kodunun incelenmesiyle hazırlanmıştır.

> [!IMPORTANT]
> Burada anlatılan uçlar yayınlanmış ve sürümlenmiş resmî bir genel API sözleşmesi değildir. Kuruma özel web ve mobil istemci uçlarıdır; AKBİM tarafından haber verilmeden değiştirilebilir. Yalnızca yetkili kullanıcı hesabı ve kullanıcının erişmeye yetkili olduğu veriler için kullanılmalıdır.

## Kapsam

Belgelenen modüller:

- Web ve mobil giriş
- Oturum çerezi saklama ve otomatik yenileme
- Öğrenci profili ve profil fotoğrafı
- Ders programı
- Deneme sınavları (`SBS`)
- Tarama sınavları (`DBS`)
- Sınav raporu, cevap anahtarı ve öğrenci cevapları
- Kazanım/konu analizi
- Ödevler ve ödev dosyaları
- Yemek listesi PDF'si ve PDF'nin tablo olarak ayrıştırılması
- Mesajlar
- Devamsızlık
- Öğretmenler
- Duyurular ve etkinlikler

Yemek görselleri bu belgenin kapsamı dışındadır. Bunlar AKBİM'den gelmez; uygulamaya sonradan eklenen bağımsız görsel zenginleştirme katmanıdır.

## 1. Genel mimari

Temel adres:

```text
https://tedemkolejiobs.com
```

Ödev uçlarının mevcut uygulamadaki adresi `https://www.tedemkolejiobs.com` şeklindedir. Aynı kurulumun `www` alt alanıdır; istemci çerez alanı ve yönlendirmeleri dikkate almalıdır.

AKBİM tarafında iki ayrı oturum vardır:

| Oturum | Giriş ucu | Kullanıldığı yerler |
|---|---|---|
| Web/PHP | `/require/class/login.php` | Ana sayfa, program, sınav listesi/raporu, ödev, yemek, mesaj, devamsızlık, öğretmen |
| Mobil API | `/obsapi/auth/login` | DBS tarama detayı ve DBS konu analizi; profil verisinin birincil kaynağı |

Bu oturumlar birbirinin yerine geçmez. Tam işlev için aynı kullanıcı bilgileriyle ikisine de giriş yapılır. Mobil giriş başarısız olsa bile geçerli PHP oturumu kullanılmaya devam edebilir; yalnızca mobil uçlara bağımlı özellikler kullanılamaz.

### Ortak web isteği kuralları

- Kimlik doğrulama, web girişinden alınan çerezlerin `Cookie` başlığına eklenmesiyle yapılır.
- JSON beklenen AJAX uçlarında genellikle `Accept: application/json` ve `X-Requested-With: XMLHttpRequest` gönderilir.
- Form istekleri `application/x-www-form-urlencoded` veya uç özellikle gerektiriyorsa `multipart/form-data` kullanır.
- URL sorguları ve form alanları percent-encoding ile oluşturulmalıdır; değerler elle URL'ye eklenmemelidir.
- `Access denied.` düz metin yanıtı geçersiz PHP oturumu kabul edilir.
- `401` ve `403` geçersiz oturum kabul edilir.
- Mobil yanıtta `success=false` ile birlikte `session`, `oturum`, `login`, `giriş`, `unauthorized` veya `access denied` mesajı gelirse mobil oturum geçersiz kabul edilir.

## 2. Kimlik doğrulama

### 2.1 Web/PHP girişi

```http
POST /require/class/login.php
Content-Type: multipart/form-data; boundary=...
```

Form alanları:

| Alan | Değer |
|---|---|
| `request` | `login` |
| `loginAs` | `standard` |
| `isRegister` | `0` |
| `username` | Kullanıcı adı/TC kimlik numarası |
| `password` | Parola |
| `newUser` | `0` |

Beklenen yanıt biçimi:

```json
{
  "success": true,
  "msg": null
}
```

Başarılı yanıtta `Set-Cookie` başlığı bulunmalıdır. İstemci çerezleri ad-değer çiftleri olarak birleştirir ve sonraki web isteklerinde gönderir. `success=true` olup çerez gelmemesi geçerli giriş sayılmaz.

### 2.2 Mobil API girişi

```http
POST /obsapi/auth/login
Content-Type: application/json
Accept: application/json
```

```json
{
  "loginAs": "standard",
  "username": "<kullanıcı>",
  "password": "<parola>"
}
```

Yanıtın temel biçimi:

```json
{
  "success": true,
  "msg": null,
  "status": null,
  "userInfo": {
    "stuNo": "...",
    "classId": "...",
    "stuType": "...",
    "profilePhoto": "..."
  }
}
```

AKBİM kurulumları isim alanlarını farklı verebildiği için uygulama şu alanları esnek biçimde destekler: `name`, `surname`, `nameSurname`, `fullName`, `studentName`, `studentNameSurname`, `stuName`, `stuSurname`, `userName`, `userSurname`, `firstName`, `lastName`.

`success` alanı bazı yanıtlarda Boolean yerine `1`, `true`, `success` veya `ok` biçiminde gelebileceğinden esnek çözülür. Benzer şekilde sayısal kimlikler String veya sayı olabilir.

### 2.3 Çerez ve kimlik bilgisi saklama

Uygulamanın mevcut yaklaşımı:

- Web oturumu ephemeral `URLSession` içinde otomatik çerez yönetimi kapalı tutularak elle yönetilir.
- Mobil oturum ayrı bir ephemeral `URLSession` ve kendi çerez deposuyla yönetilir.
- Web çerezleri Netscape cookie-file biçiminde `Application Support/GokturkOBS/Session/obs-cookies.txt` dosyasına yazılır.
- Oturum klasörü `0700`, dosya `0600` POSIX izinleriyle korunur.
- Kullanıcı adı/parola yalnızca “Beni Hatırla” etkinse macOS Keychain'de generic password olarak saklanır.
- Keychain service adı: `com.gokturk.GokturkOBS.credentials`.
- Parola loglanmaz; çerez değerleri de loglanmamalıdır.

Cookie dosyası bir kimlik doğrulama sırrıdır. Kaynak denetimine eklenmemeli, başka kullanıcıya gönderilmemeli ve hata raporlarına konmamalıdır.

## 3. Oturum yenileme ve hata politikası

Her korumalı okuma işlemi şu akışla yapılır:

1. İstek bir kez çalıştırılır.
2. İptal hatasıysa doğrudan iptal edilir.
3. Başka bir hata oluşursa yalnız o anda internet erişimi kontrol edilir:
   `HEAD https://1.1.1.1/cdn-cgi/trace`.
4. İnternet erişilebiliyorsa Keychain'deki kimlik bilgileriyle ilgili oturum bir kez yenilenir.
5. Asıl istek yeniden çalıştırılır.
6. Sonraki hata geçiciyse en fazla üç ek deneme yapılır.

İnternet kontrolü periyodik veya beş saniyede bir yapılmaz; yalnız veri alma hatasından sonra tetiklenir.

Geçici kabul edilen HTTP kodları: `429`, `502`, `503`, `504`. `Retry-After` varsa 1–60 saniye aralığına sınırlandırılır. Yoksa veya desteklenen bir `URLError` oluşmuşsa 2, 4 ve 8 saniyelik üstel gecikme uygulanır.

Web ve mobil yenilemeler ayrı tutulur. Aynı anda birden fazla istek oturum hatası alırsa tek bir web veya mobil giriş görevi paylaşılır; her istek ayrı ayrı giriş yapmaz. Her okuma zincirinde otomatik yeniden giriş yalnız bir kez gerçekleştirilir.

## 4. Öğrenci profili

Birincil kaynak mobil giriş yanıtındaki `userInfo` nesnesidir. Uygulamanın ihtiyaç duyduğu temel alanlar:

| Alan | Amaç |
|---|---|
| `stuNo` | Sınav ve DBS isteklerindeki öğrenci numarası |
| `classId` | Sınav raporu/listesi sınıf kimliği |
| `stuType` | Öğrenci türü |
| İsim alanları | Arayüzde gösterilen ad |
| `profilePhoto` | Profil görseli adresi |

Mobil yanıtta profil eksikse web yedeği kullanılır:

```http
GET /pages/student/profile.php
Accept: text/html
Cookie: <web oturumu>
```

Bu uç JSON değil HTML döndürür. HTML ayrıştırıcısı öğrenci numarası, sınıf kimliği, ad, veli adı ve fotoğraf adresini sayfadan çıkarır. Profil bellekte önbelleğe alınır; eşzamanlı profil istekleri tek görevde birleştirilir.

Profil fotoğrafı `profilePhoto` veya HTML'den alınan URL'ye `GET` ile indirilir. URL göreliyse temel adrese göre mutlaklaştırılır. Gerekirse web cookie başlığı eklenir ve veri gerçekten çözülebilir bir görsel mi diye doğrulanır.

## 5. Ana veri ve ders programı

```http
POST /pages/student/require/indexAction.php
Content-Type: application/x-www-form-urlencoded
Cookie: <web oturumu>

request=loadIndex
```

İlgili yanıt parçası:

```json
{
  "success": true,
  "data": {
    "lessonSchedule": {
      "periodList": [{ "id": 1, "description": "..." }],
      "periodId": 1,
      "data": {
        "xInfo": [["..."]],
        "yInfo": [["..."]],
        "data": [
          {
            "x": 1,
            "y": 1,
            "id": "...",
            "text": ["Öğretmen", "Ders"],
            "data": {
              "headerTitle": "...",
              "headerContent": "..."
            }
          }
        ]
      }
    }
  }
}
```

Program koordinat sistemi:

- `x`: ders saati/sütun kimliği; API tarafında 1 tabanlıdır. `xInfo[x - 1]` ders saatine karşılık gelir.
- `y`: gün kimliği; `yInfo` içindeki günlerle eşleştirilir ve 1 tabanlı kullanılır.
- `text[0]`: öğretmen, `text[1]`: normal ders adı.
- `data.headerTitle`: varsa daha özel ders/alt başlık adıdır.
- `xInfo`: saat aralığı gibi metinleri içerir; saat yoksa istemci saat uydurmamalıdır.
- `yInfo`: haftanın gösterilen günlerini taşır. Hafta sonu satırı gerçekten varsa korunmalıdır.

Gün eşleştirmesi sabit olarak “ilk satır pazartesi” varsayımıyla yapılmamalı; `yInfo` başlıkları Türkçe gün adına dönüştürülmelidir. Dersler API'nin verdiği sırayla gösterilir. Tatil veya boş gün için başka günün dersleri “bugünün dersi” gibi sunulmamalıdır; sonraki ders ayrıca ve açıkça “sonraki ders” olarak seçilebilir.

Aynı `loadIndex` yanıtı ayrıca şu listeleri sağlar:

- `data.examList`
- `data.announcementList`
- `data.eventList`

## 6. Deneme sınavları (`SBS`)

### 6.1 Listeyi alma

Detaylı sınav özeti:

```http
POST /pages/student/require/examDashboard.php
Content-Type: multipart/form-data; boundary=...
X-Requested-With: XMLHttpRequest
Cookie: <web oturumu>
```

Form alanları:

| Alan | Değer |
|---|---|
| `request` | `getStudentExams` |
| `stuNo` | Profildeki öğrenci numarası |
| `classId` | Profildeki sınıf kimliği |
| `stuType` | `SBS` |

Yanıt `ExamDashboard` biçimindedir:

- `success`
- `exams[]`
- `kpi`
- `lessonSuccess[]`
- `trend`
- `lessons[]`

Bir sınav kaydında kullanılan alanlar: `examId`, `examName`, `examDate`, `point`, `net`, `dogru`, `yanlis`, `bos`, `questionCount`, `successRate`, `TD`, `GD`, `SD`, `examType`.

Gerçek görünür sınav listesi ayrıca `loadIndex` içindeki `data.examList` üzerinden doğrulanır. `examType == "SBS"` kayıtları seçilir; `DBS` kayıtları deneme listesine karıştırılmaz. Tekilleştirme anahtarı `examType|sinavKod` şeklindedir. Index kaydı ve dashboard kaydı `examId == sinavKod` ve sınav türü üzerinden birleştirilir.

`examList` kayıtlarında kullanılan alanlar:

```text
sinavKod, sinavAd, sinavTarih, examType,
point, net, dogru, yanlis, bos, questionCount, successRate
```

### 6.2 Tek sınav raporu

```http
POST /pages/student/require/examDashboard.php
Content-Type: multipart/form-data; boundary=...
Cookie: <web oturumu>
```

| Alan | Değer |
|---|---|
| `request` | `getSchoolReport` |
| `examType` | Listedeki sınav türü (`SBS` veya gerektiğinde `DBS`) |
| `examId` | Sınav kodu |
| `stuNo` | Öğrenci numarası |
| `classId` | Sınıf kimliği |

Yanıtta kullanılan üst alanlar:

```json
{
  "success": true,
  "data": {},
  "subanal": null,
  "graphs": null
}
```

`data`, AKBİM'in kısa alan adlarını içerir. Mevcut çözümleme:

| Alan kalıbı | Anlamı |
|---|---|
| `SR1`…`SR6` | Ders soru sayısı |
| `D1`…`D6` | Doğru sayısı |
| `Y1`…`Y6` | Yanlış sayısı |
| `B1`…`B6` | Boş sayısı |
| `N1`…`N6` | Net |
| `SC1`…`SC6` | Sınav cevap anahtarı dizisi |
| `OC1`…`OC6` | Öğrenci cevap dizisi |
| `SR7`, `D7`, `Y7`, `B7`, `N7` | Toplamlar |
| `Puan` | Sınav puanı |
| `SD` | Sınıf sırası |
| `GD` | Genel sıralama |

Mevcut altı ders sırası: Türkçe, Matematik, Sosyal Bilgiler, Fen ve Teknoloji, Din Kültürü, Yabancı Dil. Bu sıra AKBİM rapor formatına bağlıdır.

`B` alanı soru cevabı bağlamında “boş”tur. Kazanım/performans verisindeki `Bas` alanı ise başarı yüzdesidir; ikisi karıştırılmamalıdır.

### 6.3 Cevap durumu

`SCn` cevap anahtarını, `OCn` öğrencinin cevabını taşır. Mevcut AKBİM kodlamasında:

- boşluk veya eksik karakter: boş,
- büyük harfli öğrenci cevabı: doğru,
- küçük harfli öğrenci cevabı: yanlış,
- gösterilen cevap harfi arayüz için büyük harfe çevrilir.

Özet sayılar ile karakter dizilerinden hesaplanan doğru/yanlış/boş toplamları karşılaştırılabilir. Format değişirse büyük/küçük harf yorumuna körü körüne güvenilmemeli, özet alanlarıyla doğrulanmalıdır.

### 6.4 Konu/kazanım analizi

Web raporundaki `subanal` yapısı sabit olmayan iç içe dizi/nesne şeklinde gelebilir. Mevcut ayrıştırıcı alan adlarını büyük-küçük harf duyarsız arar:

- Ders: `lesson`, `ders`, `dersAd`, `lessonName`
- Konu: `konuAd`, `konu`, `kazanim`, `kazanım`, `topic`
- Soru: `SSay`, `soruSayisi`, `questionCount`
- Doğru: `Dog`, `dogru`, `correct`
- Yanlış: `Yan`, `yanlis`, `yanlış`, `wrong`
- Başarı yüzdesi: `Bas`, `basari`, `başarı`, `successRate`

Aynı ders ve konu birden çok satırda gelirse soru/doğru/yanlış sayıları toplanır. Başarı yüzdeleri soru sayısıyla ağırlıklı birleştirilir.

## 7. Tarama sınavları (`DBS`)

### 7.1 Tarama listesi

Liste ayrı bir mobil liste ucundan değil, `loadIndex` yanıtındaki `data.examList` içinden alınır. `examType == "DBS"` kayıtları seçilir.

Kullanılan alanlar:

```text
examType, sinavKod, sinavAd, sinavTarih, point
```

### 7.2 Mobil DBS detayı

Önce mobil giriş yapılmış olmalıdır.

```http
GET /obsapi/exam/dbs/getExamDetail?examcode=<sınav_kodu>&stuNo=<öğrenci_no>
Accept: application/json
```

Yanıtın `data` nesnesinde:

| Alan | Anlamı |
|---|---|
| `lessons` | Dersler; her kayıtta `lesson`, isteğe bağlı `group` |
| `ss` | Soru sayıları |
| `d` | Doğru sayıları |
| `y` | Yanlış sayıları |
| `n` | Netler |
| `p` | Etiketli puan değerleri |
| `derece` | Etiketli sıralama grupları |
| `sayi` | Katılım sayıları |
| `examKey` | Derslere göre cevap anahtarı dizileri |
| `answer` | Derslere göre öğrenci cevap dizileri |

Sayısal alanlar String veya sayı gelebileceği için esnek çözülür. Paralel diziler aynı ders indeksiyle eşleştirilir. `lessons[index]` için `ss[index]`, `d[index]`, `y[index]`, `n[index]`, `examKey[index]` ve `answer[index]` kullanılır; sınır kontrolü yapılmadan indislenmemelidir.

Tarama detayı açılırken web `getSchoolReport` isteği de `examType=DBS` ile çalıştırılabilir. Böylece mobil detay kullanılamazsa web raporu yedek görünüm sağlar; tüm raporların önceden indirilmesi gerekmez.

### 7.3 Mobil DBS konu analizi

```http
GET /obsapi/exam/dbs/getSubjectAnalyse?examcode=<sınav_kodu>&stuNo=<öğrenci_no>
Accept: application/json
```

Yanıtın `data` dizisindeki alanlar:

| Alan | Anlamı |
|---|---|
| `lesson` | Ders |
| `konuAd` | Konu/kazanım |
| `SSay` | Soru sayısı |
| `Dog` | Doğru |
| `Yan` | Yanlış |
| `Bas` | Başarı yüzdesi |

Gösterimde satırlar ders adına göre, API'deki ilk görülme sırası korunarak gruplanır.

## 8. Ödevler

### 8.1 Ödev listesi

```http
GET https://www.tedemkolejiobs.com/obsapi/homework/getHomeworkList
X-Requested-With: XMLHttpRequest
Cookie: <web oturumu>
```

Yanıt:

```json
{
  "success": true,
  "data": []
}
```

Ödev alanları:

```text
id, title, teaNameSurname, typeName, startDate, endDate,
iconClass, lesson, score, statusName, status, willBeScored,
isActive, hasAttachFile, hasAnswerFile, seen, stuCanAttachFile,
attachFileCount, answerFileCount
```

Aktif ödev hesabında yalnız listenin dolu olmasına bakılmaz. Sunucunun `isActive` ve durum alanları, bitiş tarihiyle birlikte değerlendirilir; tamamlanmış veya süresi geçmiş ödev aktif sayılmamalıdır.

### 8.2 Ödev detayı

```http
GET https://www.tedemkolejiobs.com/obsapi/homework/getHomeworkDetail?id=<ödev_id>
X-Requested-With: XMLHttpRequest
Cookie: <web oturumu>
```

Detay alanları listeye ek olarak `description`, `analysed`, `konuAd`, `teacherComment`, `studentAttachFiles`, `attachFiles` ve `answerFiles` içerir.

Dosya kaydı:

```text
fileId, fileHash, fileName, fileType
```

### 8.3 Ödev dosyası indirme

```http
GET https://www.tedemkolejiobs.com/download.php?file=<fileHash>
Cookie: <web oturumu>
```

`fileHash` boşsa istek yapılmaz. İndirilen dosya türü yalnız ada güvenilerek değil, gerektiğinde MIME/veri içeriğiyle doğrulanmalıdır.

## 9. Yemek listesi

### 9.1 PDF kimliğini alma

```http
POST /pages/student/require/foodListAction.php
Content-Type: application/x-www-form-urlencoded
X-Requested-With: XMLHttpRequest
Cookie: <web oturumu>

request=get-food-list
```

Yanıt:

```json
{ "hash": "<dosya_kimliğini_taşıyan_değer>" }
```

Boş `hash`, yayımlanmış yemek listesi olmadığı anlamına gelir.

### 9.2 PDF indirme

```http
GET /download.php?file=<hash>&view
Cookie: <web oturumu>
```

İndirilen veri boş olmamalı ve PDFKit tarafından geçerli PDF olarak açılabilmelidir. PDF, hash'in URL-güvenli Base64 karşılığıyla `Application Support/GokturkOBS/FoodList` altında önbelleğe alınır. Yeni PDF kaydedilince önceki PDF önbellekleri temizlenir. Ağ isteği başarısız olursa geçerli en son PDF yedek olarak kullanılabilir.

### 9.3 PDF tablo ayrıştırma

AKBİM yemek verisini JSON satırları halinde değil, görsel yerleşimli PDF tablosu halinde verir. Ayrıştırma sırası:

1. Her PDF sayfasının metin satırları ve koordinatları PDFKit ile alınır.
2. İçinde Türkçe hafta günü geçen satırlar tarih başlığı kabul edilir.
3. Komşu tarih başlıklarının yatay orta noktaları sütun sınırı yapılır.
4. Başlığın altında ve ilgili sütunda kalan metin parçaları seçilir.
5. Dikey aralıkları çakışan parçalar aynı Excel hücresi gibi birleştirilir.
6. Parçalar sayfadaki konumlarına göre sıralanarak tam yemek adları oluşturulur.

Üretilen model:

```swift
struct FoodMenuDay {
    let heading: String
    let items: [String]
    let pageIndex: Int
}
```

`items[0]` her koşulda ana yemek değildir. PDF düzeni doğrulanmadan bu varsayım yapılmamalıdır. Çorba önce, ana yemek sonra biçimi ilgili belgenin tutarlı şablonuyla doğrulanmışsa yalnız o format için kullanılabilir. Görsel arama/eşleştirme bu AKBİM veri akışının parçası değildir.

## 10. Mesajlar

Tüm mesaj uçları web cookie oturumunu kullanır.

| İşlem | Yöntem ve uç | Alanlar / veri yolu |
|---|---|---|
| Gelen kutusu | `GET /obsapi/mail/getInbox` | `data.mail` |
| Gönderilenler | `GET /obsapi/mail/getSentMail` | `data.mail` |
| Mesaj içeriği | `POST /obsapi/mail/getMailContent` | `mailId`; yanıt `data.mailContent` |
| Alıcı arama | `GET /obsapi/mail/getReceiverList?q=...` | yanıt `data` |
| Mesaj gönderme | `POST /obsapi/mail/sendMail` | aşağıdaki form alanları |

Gönderme alanları:

```text
title=<başlık>
content=<içerik>
receivers=[{"type":"<userType>","id":"<userId>"}]
canReply=true
shouldReply=false veya true
replyId=<yanıtlanan mesaj kimliği veya boş>
```

Alıcı kaydında tür için `userType` veya `type`, kimlik için `userId` veya `id` kullanılabilir. `receivers` normal JSON dizesidir fakat form alanı olarak gönderilir.

## 11. Devamsızlık

Önce dönemler alınır:

```http
POST /pages/student/require/attendanceDashboard.php
Content-Type: application/x-www-form-urlencoded

request=load-attendance-initial-data
```

Yanıttaki `periods` dizisinden aktif/ilk dönem kimliği alınır. Ardından:

```http
POST /pages/student/require/attendanceDashboard.php
Content-Type: application/x-www-form-urlencoded

request=get-attendance-graph-7&periodId=<dönem_id>
```

Kayıtlar yanıtın `list` alanındadır. Arayüzün kullandığı yaygın alanlar: `lesson`, `lessonNo`, `absenceDate`, `teaNameSurname`, `description`, `note`.

## 12. Öğretmenler

```http
POST /pages/student/require/teacherAction.php
Content-Type: application/x-www-form-urlencoded

request=loadMyOwnTeachers
```

Kayıtlar `data` dizisindedir. Kurulum farkları nedeniyle ad için `teaNameSurname`, `nameSurname`, `teacherName` veya `name`; ders için `lesson` veya `subject` okunur.

## 13. Duyurular ve etkinlikler

Her ikisi de ana index isteğinden gelir:

```http
POST /pages/student/require/indexAction.php

request=loadIndex
```

- Duyurular: `data.announcementList`
- Etkinlikler: `data.eventList`

Bu listelerde alan yapısı sürümler arasında değişebildiğinden uygulama sabit Codable modeller yerine esnek `JSONValue`/kayıt yapısı kullanır.

## 14. Esnek JSON çözümleme

AKBİM yanıtlarında aynı alan farklı zamanlarda String, sayı veya Boolean gelebilir. Sağlam istemci şunları desteklemelidir:

- Kimlik ve sayıların hem JSON String hem JSON number olması.
- Başarı değerlerinin `true`, `false`, `1`, `0`, `success`, `ok` biçimleri.
- Ondalık ayırıcı olarak nokta veya bazı metin alanlarında virgül.
- Eksik opsiyonel dizilerin boş dizi kabul edilmesi.
- Dinamik rapor nesnelerinin recursive JSON değeri olarak korunması.

Ancak zorunlu kimlik alanları eksikse sahte `0` kimliği üretmek yerine yanıt geçersiz sayılmalıdır. Puan gibi gerçekten gelmeyen değerler arayüzde `0` diye gösterilmemelidir.

## 15. Örnek Swift istek yardımcısı

Aşağıdaki iskelet, web form uçları için temel yaklaşımı gösterir. Üretim kodunda otomatik oturum yenileme, iptal ve hata tipleri ayrıca uygulanmalıdır.

```swift
func postForm(
    baseURL: URL,
    path: String,
    fields: [(String, String)],
    cookieHeader: String,
    session: URLSession
) async throws -> Data {
    var request = URLRequest(url: baseURL.appendingPathComponent(path))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")

    var components = URLComponents()
    components.queryItems = fields.map { URLQueryItem(name: $0.0, value: $0.1) }
    request.httpBody = components.percentEncodedQuery?.data(using: .utf8)

    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else {
        throw URLError(.badServerResponse)
    }
    guard 200..<300 ~= http.statusCode else {
        throw URLError(.badServerResponse)
    }
    if String(data: data, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines) == "Access denied." {
        throw URLError(.userAuthenticationRequired)
    }
    return data
}
```

## 16. Güvenlik ve bakım notları

- Gerçek kullanıcı adı, parola, cookie, öğrenci numarası, sınıf kimliği, dosya hash'i veya profil fotoğrafı URL'si dokümana ve loglara yazılmamalıdır.
- TLS doğrulaması devre dışı bırakılmamalıdır.
- Giriş ve mesaj gönderme gibi durum değiştiren işlemler yalnız kullanıcı eylemi veya açık uygulama akışıyla yapılmalıdır.
- Aynı veriyi her ekran çiziminde yeniden indirmeyin; profil, menü PDF'si ve sınav detaylarını uygun kapsamda önbelleğe alın.
- Liste ekranında bütün sınav raporlarını indirmeyin. Yalnız açılan veya ana sayfada gereken son sınav için rapor isteyin.
- API yanıtlarında `success=false` görülmesi HTTP 200 olsa bile hata kabul edilmelidir.
- Uç değişikliklerini tespit etmek için ham hassas veriyi değil; HTTP kodu, MIME türü, byte sayısı, alan adları ve cookie adları gibi redakte edilmiş tanı bilgilerini loglayın.

## 17. Hızlı uç özeti

| Modül | Yöntem | Uç |
|---|---|---|
| Web giriş | POST multipart | `/require/class/login.php` |
| Mobil giriş | POST JSON | `/obsapi/auth/login` |
| Profil yedeği | GET HTML | `/pages/student/profile.php` |
| Ana veri/program/listeler | POST form | `/pages/student/require/indexAction.php` |
| Deneme listesi özeti | POST multipart | `/pages/student/require/examDashboard.php` (`getStudentExams`) |
| Sınav raporu | POST multipart | `/pages/student/require/examDashboard.php` (`getSchoolReport`) |
| DBS detay | GET mobil | `/obsapi/exam/dbs/getExamDetail` |
| DBS konu analizi | GET mobil | `/obsapi/exam/dbs/getSubjectAnalyse` |
| Ödev listesi | GET | `/obsapi/homework/getHomeworkList` |
| Ödev detayı | GET | `/obsapi/homework/getHomeworkDetail?id=...` |
| Dosya indirme | GET | `/download.php?file=...` |
| Yemek hash'i | POST form | `/pages/student/require/foodListAction.php` |
| Gelen mesaj | GET | `/obsapi/mail/getInbox` |
| Gönderilen mesaj | GET | `/obsapi/mail/getSentMail` |
| Mesaj içeriği | POST form | `/obsapi/mail/getMailContent` |
| Alıcı arama | GET | `/obsapi/mail/getReceiverList?q=...` |
| Mesaj gönderme | POST form | `/obsapi/mail/sendMail` |
| Devamsızlık | POST form | `/pages/student/require/attendanceDashboard.php` |
| Öğretmenler | POST form | `/pages/student/require/teacherAction.php` |

---

Kaynak doğrulama kapsamı: GöktürkOBS projesindeki `OBSClient`, sınav/tarama modelleri, ödev istemcisi, portal özellikleri, yemek PDF istemcisi ve PDF ayrıştırıcısı. Canlı AKBİM sunucusuna örnek kullanıcıyla istek gönderilmemiştir; bu nedenle bu belge kodda uygulanmış ve daha önce gözlemlenmiş sözleşmeyi anlatır, canlı servis garantisi vermez.
