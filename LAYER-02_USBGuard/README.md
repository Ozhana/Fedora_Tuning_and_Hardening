cat > ~/Desktop/LOG_FILES/USBGuard_README.md << 'README_EOF'
# 🛡️ AEGIS USBGuard Zero-Trust Donanım Kalkanı
## Fedora 44 • Surface Pro 9 • Kurumsal Seviye Fiziksel Güvenlik

<p align="center">
  <img src="https://img.shields.io/badge/Architecture-Zero--Trust-blue?style=for-the-badge" alt="Zero-Trust">
  <img src="https://img.shields.io/badge/Red_Team-Audited_5_Iterations-red?style=for-the-badge" alt="Red Team Audited">
  <img src="https://img.shields.io/badge/SELinux-Aware-green?style=for-the-badge" alt="SELinux Aware">
  <img src="https://img.shields.io/badge/TOCTOU-Hardened-black?style=for-the-badge" alt="TOCTOU Hardened">
  <img src="https://img.shields.io/badge/Platform-Fedora_44-blue?style=for-the-badge" alt="Fedora 44">
  <img src="https://img.shields.io/badge/Hardware-Surface_Pro_9-silver?style=for-the-badge" alt="Surface Pro 9">
</p>

---

| 🇬🇧 ENGLISH | 🇹🇷 TÜRKÇE |
|:---|:---|
| # 🛡️ USBGuard Zero-Trust Hardware Shield<br><br>Can a simple USB flash drive, mouse, or keyboard compromise your system? **Absolutely.** Physical intrusion methods like **BadUSB** and **Rubber Ducky** disguise malicious payloads within seemingly innocent hardware to gain direct kernel-level access to your machine.<br><br>**USBGuard** is the ultimate shield against physical intrusions on Linux systems. However, its standard usage is complex, and "auto-allow" processes can lead to severe cybersecurity vulnerabilities known as **TOCTOU (Time-of-Check to Time-of-Use) Race Conditions**.<br><br>This enterprise-grade framework consists of two components:<br><br>\| Component \| Purpose \|<br>\|:---\|:---\|<br>\| `02a_usbguard_policy.sh` \| One-time setup wizard — Installs, hardens, and creates your hardware baseline \|<br>\| `usb-authorize.sh` \| Event-driven tool — Run whenever you plug in a new USB device \|<br><br>## ✨ Why This Framework? (Technical Differentiators)<br><br>Why should you use this instead of the standard `usbguard allow-device` command?<br><br>### 🔐 Hardware 2FA (Triple-Factor Verification)<br>The script never trusts a temporary Device ID blindly. It verifies:<br>1. **Cryptographic Hash** — The device's unique hardware fingerprint<br>2. **Topological Via-Port** — The physical connection point on the motherboard<br>3. **Temporal Persistence** — The device must survive 3 independent TOCTOU checks<br><br>### 🧪 Isolated Testing (Temporary-First Authorization)<br>Permanent permission is **never** granted immediately. Workflow:<br>1. **Blocked** → Device is denied by default<br>2. **Temporary Allow** → You test if your device works normally<br>3. **PERMANENT** → Only after successful testing, the device is sealed into the baseline<br><br>### 🛡️ Race Condition Protection (Kernel-Level Atomic Locks)<br>The script uses `flock()` file descriptor locks. Even if executed multiple times accidentally, it prevents:<br>- System file corruption<br>- Inode split-brain issues<br>- Concurrent baseline poisoning<br><br>### 📊 Deterministic Data Parsing (ANSI-Cleaned Matrix Analysis)<br>It doesn't rely on fragile text-scraping. It strips ANSI escape codes, validates output with fixed-string matching (`grep -F`), and implements timeout-bounded command execution — ensuring **100% immunity** against output format changes.<br><br>### 🏗️ SELinux Context Preservation<br>Every file operation respects SELinux contexts via `restorecon` and `chcon --reference`, ensuring zero AVC denials in enforcing mode.<br><br>### ⚡ Surface Pro 9 Thermal-Aware<br>Monitors `/sys/class/thermal/thermal_zone*/temp` and pauses execution if the passively-cooled Surface Pro 9 exceeds safe thermal limits (75°C warning, 80°C critical halt).<br><br>### 📝 Idempotent Design<br>Run it **1000 times** — you get the exact same result. Configuration state is tracked via checksum files and completion markers. No duplicate rules, no configuration drift.| # 🛡️ USBGuard Sıfır-Güven Donanım Kalkanı<br><br>Sıradan bir USB flash bellek, fareniz veya klavyeniz bilgisayarınızı ele geçirebilir mi? **Kesinlikle evet.** BadUSB ve Rubber Ducky gibi fiziksel saldırılar, zararlı yazılımları masum donanımların içine gizleyerek sisteminize çekirdek seviyesinde erişim sağlar.<br><br>Linux sistemlerde bu fiziksel sızmalara karşı en güçlü kalkan **USBGuard**'dır. Ancak USBGuard'ın standart kullanımı karmaşıktır ve "otomatik izin verme" süreçleri siber güvenlikte **TOCTOU (Zamanlama Odaklı Durum Değişimi)** dediğimiz kritik açıklara yol açabilir.<br><br>Bu kurumsal seviye çerçeve iki bileşenden oluşur:<br><br>\| Bileşen \| Amacı \|<br>\|:---\|:---\|<br>\| `02a_usbguard_policy.sh` \| Tek seferlik kurulum sihirbazı — Kurar, sertleştirir, donanım temel çizgisini oluşturur \|<br>\| `usb-authorize.sh` \| Olay güdümlü araç — Sadece yeni USB cihaz taktığınızda çalıştırın \|<br><br>## ✨ Neden Bu Çerçeve? (Teknik Farkımız)<br><br>Standart `usbguard allow-device` komutu yerine neden bunu kullanmalısınız?<br><br>### 🔐 Donanımsal 2FA (Üç Aşamalı Doğrulama)<br>Betik geçici cihaz ID'sine körü körüne güvenmez. Şunları doğrular:<br>1. **Kriptografik Hash** — Cihazın benzersiz donanım parmak izi<br>2. **Topolojik Via-Port** — Anakart üzerindeki fiziksel bağlantı noktası<br>3. **Zamansal Kalıcılık** — Cihaz 3 bağımsız TOCTOU kontrolünden geçmelidir<br><br>### 🧪 Korumalı Test Alanı (Geçici İzin Öncelikli)<br>Kalıcı izin **asla** anında verilmez. İş akışı:<br>1. **Engellendi** → Cihaz varsayılan olarak reddedilir<br>2. **Geçici İzin** → Cihazınızın düzgün çalıştığını test edersiniz<br>3. **PERMANENT** → Sadece başarılı test sonrası temel çizgiye mühürlenir<br><br>### 🛡️ Yarış Durumu Koruması (Çekirdek Seviyesi Atomik Kilitler)<br>Betik `flock()` dosya tanımlayıcı kilitleri kullanır. Yanlışlıkla birden fazla kez çalıştırılsa bile şunları engeller:<br>- Sistem dosyası bozulması<br>- Inode parçalanması (split-brain)<br>- Eşzamanlı temel çizgi zehirlenmesi<br><br>### 📊 Deterministik Veri Ayrıştırma (ANSI-Temizlenmiş Matris Analizi)<br>Kırılgan metin kazımaya bel bağlamaz. ANSI kaçış kodlarını temizler, çıktıyı sabit-dizgi eşleştirme (`grep -F`) ile doğrular, zaman aşımı-sınırlı komut çalıştırma uygular — çıktı formatı değişikliklerine karşı **%100 bağışıklık** sağlar.<br><br>### 🏗️ SELinux Bağlam Koruması<br>Her dosya işlemi SELinux bağlamlarını `restorecon` ve `chcon --reference` ile korur, zorlayıcı modda sıfır AVC reddi sağlar.<br><br>### ⚡ Surface Pro 9 Termal Farkındalığı<br>`/sys/class/thermal/thermal_zone*/temp` dizinini izler ve pasif soğutmalı Surface Pro 9 güvenli termal sınırları aşarsa (75°C uyarı, 80°C kritik duruş) çalışmayı duraklatır.<br><br>### 📝 Idempotent Tasarım<br>**1000 kere** çalıştırın — her seferinde aynı sonucu alırsınız. Yapılandırma durumu checksum dosyaları ve tamamlanma işaretçileriyle takip edilir. Mükerrer kural yok, yapılandırma kayması yok. |

---

## 📋 İÇİNDEKİLER | TABLE OF CONTENTS

- [🚀 Hızlı Kurulum | Quick Start](#-hızlı-kurulum--quick-start)
- [📖 Kullanım | Usage](#-kullanım--usage)
- [🏗️ Mimari | Architecture](#️-mimari--architecture)
- [🔒 Güvenlik Katmanları | Security Layers](#-güvenlik-katmanları--security-layers)
- [📁 Log Dosyaları | Log Files](#-log-dosyaları--log-files)
- [⚠️ Gereksinimler | Requirements](#️-gereksinimler--requirements)
- [🛠️ Sorun Giderme | Troubleshooting](#️-sorun-giderme--troubleshooting)
- [🧪 Red Team Denetim Geçmişi | Audit Trail](#-red-team-denetim-geçmişi--red-team-audit-trail)
- [📄 Lisans | License](#-lisans--license)

---

## 🚀 Hızlı Kurulum | Quick Start

### 🇬🇧 One-Time Setup (After Fresh Fedora Install)

```bash
# 1. Download the setup script
sudo curl -o /usr/local/bin/02a_usbguard_policy.sh \
  https://raw.githubusercontent.com/Ozhana/Fedora_Hardening/main/Layer-02_USBGuard/02a_usbguard_policy.sh

# 2. Secure the permissions
sudo chmod 700 /usr/local/bin/02a_usbguard_policy.sh

# 3. Run the setup wizard (ONLY ONCE after format)
sudo bash /usr/local/bin/02a_usbguard_policy.sh
```

### 🇹🇷 Tek Seferlik Kurulum (Yeni Fedora Kurulumu Sonrası)
```bash
# 1. Kurulum betiğini indirin
sudo curl -o /usr/local/bin/02a_usbguard_policy.sh \
  https://raw.githubusercontent.com/Ozhana/Fedora_Hardening/main/Layer-02_USBGuard/02a_usbguard_policy.sh

# 2. İzinleri kilitleyin
sudo chmod 700 /usr/local/bin/02a_usbguard_policy.sh

# 3. Kurulum sihirbazını çalıştırın (FORMAT SONRASI SADECE 1 KERE)
sudo bash /usr/local/bin/02a_usbguard_policy.sh
```

⚠️ ÖNEMLİ | IMPORTANT: Bu betik sadece format sonrası 1 kere çalıştırılır. Mevcut sisteme zarar vermez — idempotent'tır (tekrar çalıştırılsa da aynı sonucu verir).

## 📖 Kullanım | Usage
### 🇬🇧 Day-to-Day: Authorizing a New USB Device

You do NOT run this daily. It is event-driven — only when you plug in a blocked USB device:
```bash
sudo usb-authorize.sh
```
### Workflow:
Step	Action	Screen Shows <br>
1	Plug in new USB device	Device is automatically BLOCKED<br>
2	Run sudo usb-authorize.sh	List of all blocked devices with IDs<br>
3	Enter the device ID number	Device details (hash, port, type)<br>
4	Temporary permission? → yes	Device gets temporary access for testing<br>
5	Test your device manually	Verify hardware works correctly<br>
6	Permanent seal? → PERMANENT	Device added to permanent whitelist<br>

🧠 Cognitive Friction: You must type PERMANENT in all caps to prevent accidental keystrokes. There is a 60-second timeout on every prompt — no response = automatic cancellation.

