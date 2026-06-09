#!/usr/bin/env bash

# ==============================================================================
# KIMLIK: Enterprise-Grade Sistem Mimarı ve Kıdemli Siber Güvenlik Uzmanı
# AMAC: Fedora 44 Workspace - Post-Format Agresif Debloat & Sürücü Hattı
# DONANIM: Microsoft Surface Pro 9 (Single User)
# KURAL: Formattan sonra 1 KEZ çalıştırılacak doğrusal icra motoru.
# ==============================================================================

# STRIKT MOD (ANAYASA MADDE 1)
set -Eeuo pipefail
IFS=$'\n\t'

# ROOT YETKİSİ KONTROLÜ
if [[ $EUID -ne 0 ]]; then
    echo "[-] HATA: Bu motor askeri düzeyde yetki gerektirir. 'sudo' ile çalıştırın." >&2
    exit 1
fi

# KERNEL SEVİYESİNDE ATOMİK KİLİT (TOCTOU & RACE CONDITION KESİN ENGELLEME)
readonly LOCK_FILE="/run/lock/layer00_aggressive_debloat.lock"
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    echo "[-] HATA: Betik zaten çalışıyor veya kilitli! Eşzamanlı icra engellendi." >&2
    exit 1
fi

# DİNAMİK KULLANICI TESPİT MOTORU
TARGET_USER="${SUDO_USER:-}"
if [[ -z "$TARGET_USER" || "$TARGET_USER" == "root" ]]; then
    TARGET_USER=$(logname 2>/dev/null || awk -F: '$3 == 1000 {print $1}' /etc/passwd)
fi

if [[ -z "$TARGET_USER" ]]; then
    echo "[-] HATA: Gerçek sistem kullanıcısı tespit edilemedi!" >&2
    exit 1
fi

# GÜVENLİ GETENT SORGULAMA VE TEŞHİS MOTORU (ANTI-CRASH)
PASSWD_ENTRY=$(getent passwd "$TARGET_USER") || {
    echo "[-] HATA: '${TARGET_USER}' kullanıcısına ait yerel hesap veritabanı girdisi bulunamadı!" >&2
    exit 1
}

TARGET_HOME=$(cut -d: -f6 <<< "$PASSWD_ENTRY")

# GEÇERSİZ EV DİZİNİ KORUMASI (CRITICAL PATH PROTECTION)
if [[ -z "$TARGET_HOME" || ! -d "$TARGET_HOME" ]]; then
    echo "[-] HATA: Hedef ev dizini geçersiz veya mevcut değil: '${TARGET_HOME:-}'" >&2
    exit 1
fi

# LOG DIZINI VE GÜVENLİK ÖNLEMLERİ (SYMLINK HIJACKING SAVUNMASI)
readonly LOG_DIR="${TARGET_HOME}/Desktop/LOG_FILES"

if [[ -L "$LOG_DIR" ]]; then
    echo "[-] ADLİ ALARM: Log dizini bir sembolik bağ (symlink)! Saldırı engellendi." >&2
    exit 1
fi

mkdir -p "$LOG_DIR"
readonly LOG_FILE="${LOG_DIR}/Layer00_Aggressive_Debloat.log"

# GEÇİCİ ALAN GÜVENLİĞİ (/run/lock ALTINDA ROOT ODAKLI TMPFS ENTEGRASYONU)
readonly SECURE_TMP="/run/lock/layer00_debloat_tmp"
rm -rf "$SECURE_TMP" 2>/dev/null || true
mkdir -p "$SECURE_TMP"
chmod 700 "$SECURE_TMP"

# RECURSION ENGELLENMİŞ, TEKİL DOSYA TABANLI TRAP & CLEANUP MİMARİSİ
cleanup() {
    local exit_code=$?
    # Sonsuz döngüyü engellemek için trap mekanizmasını anında çöz
    trap - EXIT INT TERM HUP QUIT
    
    # Geçici alanı ve mühürlü dosyaları temizle
    rm -rf "$SECURE_TMP" 2>/dev/null || true
    
    # Kilit dosyasını atomic olarak serbest bırak ve sadece dosyayı temizle
    flock -u 9 2>/dev/null || true
    rm -f "$LOCK_FILE" 2>/dev/null || true
    
    if [[ -n "${LOG_FILE:-}" && -f "$LOG_FILE" ]]; then
        echo "[*] Bilgi: Debloat motoru durduruldu. Çıkış Kodu: ${exit_code}" >> "$LOG_FILE"
    fi
    return "$exit_code"
}
trap cleanup EXIT INT TERM HUP QUIT

# ÇIKTILARI LOG DOSYASINA VE TERMINALE GÜVENLİ YÖNLENDIRME
exec > >(tee -a "$LOG_FILE") 2>&1

echo "======================================================================"
echo "[+] AGRESİF DEBLOAT VE DONANIM HIZLANDIRMA MOTORU TETİKLENDİ: $(date)"
echo "======================================================================"

# ==============================================================================
# 1. DNF CONFIGURATION OPTIMIZATION (IDEMPOTENT ATOMIC REPLACEMENT)
# ==============================================================================
echo "[*] Adım 1: DNF öncelikli hız parametreleri atomik olarak işleniyor..."
readonly DNF_CONF="/etc/dnf/dnf.conf"

awk '
BEGIN { f=0; p=0; d=0 }
/^fastestmirror=/ { $0="fastestmirror=True"; f=1 }
/^max_parallel_downloads=/ { $0="max_parallel_downloads=10"; p=1 }
/^defaultyes=/ { $0="defaultyes=True"; d=1 }
{ print }
END {
    if(!f) print "fastestmirror=True"
    if(!p) print "max_parallel_downloads=10"
    if(!d) print "defaultyes=True"
}' "$DNF_CONF" > "${SECURE_TMP}/dnf.conf.new"

install -m 644 "${SECURE_TMP}/dnf.conf.new" "$DNF_CONF"

# ==============================================================================
# 2. RPM FUSION VE INTEL GPU DONANIMSAL HIZLANDIRMA ENTEGRASYONU (IDEMPOTENT)
# ==============================================================================
echo "[*] Adım 2: RPM Fusion depo durumu kontrol ediliyor..."
if ! rpm -q rpmfusion-free-release &>/dev/null || ! rpm -q rpmfusion-nonfree-release &>/dev/null; then
    echo "[*] Bilgi: RPM Fusion depoları eksik. Yükleme başlatılıyor..."
    FEDORA_VER=$(rpm -E %fedora)
    dnf install -y \
        "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_VER}.noarch.rpm" \
        "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_VER}.noarch.rpm"
else
    echo "[+] Bilgi: RPM Fusion depoları zaten entegre edilmiş. Atlanıyor."
fi

echo "[*] Adım 3: Aktif repolar baseline loguna mühürleniyor..."
echo "--- INSTALLED REPOS BASELINE ---" >> "$LOG_FILE"
dnf repolist >> "$LOG_FILE" 2>&1 || true
echo "--------------------------------" >> "$LOG_FILE"

echo "[*] Adım 4: Hassas donanım analizi ile Intel GPU doğrulanıyor..."
if lspci -nnk | grep -A3 -Ei 'VGA|Display|3D' | grep -qi intel; then
    missing_gpu_pkg=0
    rpm -q intel-media-driver &>/dev/null || missing_gpu_pkg=1
    rpm -q libva-utils &>/dev/null || missing_gpu_pkg=1
    
    if (( missing_gpu_pkg )); then
        echo "[*] Bilgi: Intel VA-API donanımsal hızlandırma sürücüleri kuruluyor..."
        dnf install -y intel-media-driver libva-utils
    else
        echo "[+] Bilgi: Intel VA-API sürücüleri zaten sistemde mevcut. Atlanıyor."
    fi
else
    echo "[!] Uyarı: Sistemde aktif Intel GPU bulunamadı. Sürücü kurulumu pasif geçildi."
fi

# ==============================================================================
# 3. PLYMOUTH İPTALİ VE METİN TABANLI BOOT ENJEKSİYONU
# ==============================================================================
echo "[*] Adım 5: Plymouth grafik ekranı iptal ediliyor, saf metin boot moduna geçiliyor..."
if grubby --update-kernel=ALL --remove-args="rhgb quiet"; then
    echo "[+] Başarılı: Boot ekranı şeffaf metin akış moduna alındı."
else
    echo "[!] Uyarı: Grubby kernel parametre manipülasyonu başarısız oldu."
fi

# ==============================================================================
# 4. DOĞRUSAL PAKET İMHASI (DNF5 ADMİNİSTRASYONU)
# ==============================================================================
readonly DEBLOAT_PKGS=(
    "firefox"               # Baş tarayıcı LibreWolf olacağı için stok Firefox imha edilir.
    "gnome-tour"            # Gereksiz arayüz rehberi.
    "yelp"                  # GNOME Yardım dokümantasyonu (Saldırı yüzeyi).
    "gnome-connections"     # Uzak masaüstü istemcisi (Gereksiz port/bağlantı riski).
    "gnome-weather"         # Arka planda konum/hava durumu sorgulayan telemetri primi.
    "httpd"                 # Apache kalıntıları temizlenir.
    "avahi-daemon"          # Yerel ağda mDNS yayını yapan tehlikeli protokol bileşeni.
    "simple-scan"           # Saldırı yüzeyi genişleten stok tarayıcı aracı.
    "totem"                 # Potansiyel gstreamer zafiyeti barındıran stok video oynatıcı.
    "cheese"                # Donanım erişim riski oluşturan stok kamera uygulaması.
)

echo "[*] Adım 6: DNF5 paket imha hattı doğrusal olarak başlatılıyor..."
if dnf remove -y -- "${DEBLOAT_PKGS[@]}"; then
    echo "[+] Başarılı: Belirlenen stok paketler sistemden kazındı."
else
    echo "[!] Uyarı: Paket imha hattında bazı sorunlar oluştu, adımlara devam ediliyor."
fi

echo "[*] Adım 7: Sahipsiz paket bağımlılıkları taranıyor ve raporlanıyor..."
echo "--- UNNEEDED PACKAGES REPORT ---" >> "$LOG_FILE"
dnf repoquery --unneeded >> "$LOG_FILE" 2>&1 || true
echo "--------------------------------" >> "$LOG_FILE"

echo "[*] Adım 8: Güvenli bağımlılık temizliği yürütülüyor..."
dnf autoremove -y

# ==============================================================================
# 5. FLATPAK REPO VE TEMEL ARAÇ ENTEGRASYONU (CRITICAL ENFORCEMENT)
# ==============================================================================
echo "[*] Adım 9: Flathub güvenli uzak deposu ekleniyor..."
if command -v flatpak &> /dev/null; then
    flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    
    echo "[*] Adım 10: Sandbox yönetim ve üretkenlik araçları kuruluyor..."
    # KRITIK PAKETLER: Başarısızlık durumunda betik koruma amacıyla durdurulur (Anayasa Sertliği)
    flatpak install flathub com.github.tchx84.Flatseal -y
    flatpak install flathub com.mattjakeman.ExtensionManager -y
    
    # OPSİYONEL ÜRETKENLİK PAKETLERİ: Başarısızlık durumunda uyarı verip devam eder
    flatpak install flathub com.github.xournalpp.xournalpp -y || echo "[-] Uyarı: Xournal++ kurulamadı."
    flatpak install flathub org.kde.okular -y || echo "[-] Uyarı: Okular kurulamadı."
    
    echo "[*] Adım 11: Flatpak uzantı ve depo detayları mühürleniyor..."
    flatpak remotes --show-details >> "$LOG_FILE" 2>&1 || true
else
    echo "[-] HATA: Flatpak alt yapısı sistemde bulunamadı! Kritik araçlar yüklenemiyor." >&2
    exit 1
fi

echo "[*] Adım 12: Yerel adli analiz ve güvenlik araçları RPM hattından entegre ediliyor..."
dnf install -y keepassxc gnome-tweaks btop celluloid dejavu-sans-mono-fonts

# ==============================================================================
# 6. POST-DEBLOAT GELECEK KATMAN BASELINE RAPORLAMASI
# ==============================================================================
echo "[*] Adım 13: AIDE ve sistem bütünlüğü katmanı öncesi paket baseline matrisi oluşturuluyor..."
echo "--- BASELINE INSTALLED PACKAGES ---" >> "$LOG_FILE"
rpm -qa | sort >> "$LOG_FILE" 2>&1 || true
echo "-----------------------------------" >> "$LOG_FILE"

echo "[*] Adım 14: Sonraki katmanlar için güncel servis durum matrisi çıkarılıyor..."
echo "--- SYSTEMD UNIT FILES BASELINE ---" >> "$LOG_FILE"
systemctl list-unit-files >> "$LOG_FILE" 2>&1 || true
echo "------------------------------------" >> "$LOG_FILE"

echo "======================================================================"
echo "[+] LAYER-00 AGRESİF DEBLOAT VE SÜRÜCÜ AYARLARI BAŞARIYLA MÜHÜRLENDİ."
echo "======================================================================"
