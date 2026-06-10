#!/usr/bin/env bash
# ==============================================================================
# PROJE         : FEDORA TUNING AND HARDENING
# KATMAN        : LAYER-01_Core_OS_Hardening
# BETİK         : 01b_time_nts_chrony.sh
# AMAÇ          : Network Time Security (NTS) Kriptografik Zaman Zırhı (V30_AEGIS)
# DONANIM       : Microsoft Surface Pro 9 (Intel Core Hibrit Mimari)
# KURAL         : Formattan sonra 1 KEZ çalıştırılacak doğrusal mühürleme motoru.
# ==============================================================================

set -Eeuo pipefail
export IFS=$'\n\t'
export LC_ALL=C

# 1. ASKERİ DÜZEY YETKİ VE SİSTEM ARAÇLARI GÜVENLİK DUVARI
if [[ $EUID -ne 0 ]]; then
    echo "[FATAL] Bu motor askeri düzeyde yetki gerektirir. 'sudo' ile çalıştırın." >&2
    exit 1
fi

for cmd in chronyd chronyc systemctl flock awk grep sed cp rm mv timeout bash mktemp sync stat realpath restorecon date chown logger; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "[FATAL] Gerekli sistem aracı bulunamadı: $cmd" >&2
        exit 1
    fi
done

# 2. ÜST DİZİN VE EV DİZİNİ MUTLAK GÜVENLİK ANALİZİ (PARENT OWNERSHIP ENFORCEMENT)
readonly TARGET_USER_NAME="${SUDO_USER:-$USER}"
readonly PASSWD_ENTRY=$(getent passwd "$TARGET_USER_NAME") || { 
    logger -p kern.emerg "aegis-time-nts: Kullanıcı veritabanı girdisi bulunamadı!"
    exit 1 
}
readonly TARGET_HOME_BASE=$(cut -d: -f6 <<< "$PASSWD_ENTRY")

if [[ -z "$TARGET_HOME_BASE" || ! -d "$TARGET_HOME_BASE" ]]; then
    echo "[-] HATA: Geçersiz veya sahte ev dizini patikası!" >&2
    exit 1
fi

readonly TARGET_HOME_REAL=$(realpath "$TARGET_HOME_BASE")
readonly LOG_DIR="${TARGET_HOME_REAL}/Desktop/LOG_FILES"

# Parent Ownership & Symlink Hijack Kalkanı
if [[ -e "$LOG_DIR" ]]; then
    readonly LOG_REAL=$(realpath -m "$LOG_DIR")
    case "$LOG_REAL" in
        "${TARGET_HOME_REAL}"/*) ;;
        *) 
            logger -p kern.emerg "aegis-time-nts: ADLİ ALARM! Log dizini sınır ihlali yaptı."
            exit 1 
            ;;
    esac
    readonly DIR_OWNER=$(stat -c '%U' "$LOG_DIR")
    if [[ "$DIR_OWNER" != "$TARGET_USER_NAME" && "$DIR_OWNER" != "root" ]]; then
        logger -p kern.emerg "aegis-time-nts: ADLİ ALARM! Güvensiz dizin sahipliği tespit edildi."
        exit 1
    fi
fi

mkdir -p "$LOG_DIR" && chmod 755 "$LOG_DIR"
chown "${TARGET_USER_NAME}:" "$LOG_DIR"
readonly LOG_FILE="${LOG_DIR}/Layer01_Time_NTS_Chrony.log"

# Zaman Damgalı Adli Log Rotasyon Kalkanı (Audit Chain Protection)
if [[ -f "$LOG_FILE" && $(stat -c%s "$LOG_FILE") -gt 5242880 ]]; then
    mv "$LOG_FILE" "${LOG_FILE}_$(date +%s).old"
fi

# Çift Kanallı Adli Log Akışı
exec > >(tee -a "$LOG_FILE") 2>&1

# 3. KERNEL LEVEL KORUMALI FLOCK MUTEX (STALE LOCK PROTECTION)
readonly LOCKFILE="/run/lock/aegis-time-nts.lock"
exec 9>"$LOCKFILE"
chmod 600 "$LOCKFILE"
if ! flock -n 9; then
    echo "[FATAL] Betik zaten kilitli ve başka bir oturumda çalışıyor! İptal edildi." >&2
    exit 1
fi

# 4. İDAMPOTENCY (GÜVENLİ SIRA BAĞIMSIZ BLOK MATRİS KONTROLÜ)
readonly CHRONY_CONF="/etc/chrony.conf"
if [[ -f "$CHRONY_CONF" ]]; then
    if grep -q "time.cloudflare.com" "$CHRONY_CONF" && \
       grep -q "nts.netnod.se" "$CHRONY_CONF" && \
       grep -q "ptbtime1.ptb.de" "$CHRONY_CONF" && \
       grep -q "port 0" "$CHRONY_CONF"; then
        echo "[INFO] Chrony NTS (V30) konfigürasyon matrisi eksiksiz mühürlü. İdempotent çıkış."
        exit 0
    fi
fi

echo "============================================================"
echo "🛡️ AEGIS CHRONY NTS (ZAMAN ŞİFRELEMESİ) OPTİMİZASYONU (V30)"
echo "============================================================"
read -rp "Devam etmek için büyük harflerle PERMANENT yazınız: " CONFIRM

if [[ "$CONFIRM" != "PERMANENT" ]]; then
    echo "[-] Onay alınamadı. İşlem iptal ediliyor."
    exit 0
fi

# 5. GERÇEK ZAMANLI ASENKRON PRE-FLIGHT NETWORK PROBE
echo "[*] NTS Ağ Durumu ve Kriptografik Erişim Hatları Doğrulanıyor..."
readonly TEST_SERVERS=("time.cloudflare.com" "nts.netnod.se" "ptbtime1.ptb.de")
REACHABLE_COUNT=0

for srv in "${TEST_SERVERS[@]}"; do
    if timeout 4 chronyd -Q -t 4 "server $srv iburst nts" >/dev/null 2>&1; then
        ((REACHABLE_COUNT++))
        echo "  [+] $srv -> TLS NTS-KE BAĞLANTISI AKTİF"
    else
        echo "  [-] $srv -> BAĞLANTI BAŞARISIZ VEYA ZAMAN AŞIMI"
    fi
done

if [[ $REACHABLE_COUNT -lt 2 ]]; then
    echo "[FATAL] Güven nisabı (Quorum) ağ katmanında sağlanamadı ($REACHABLE_COUNT/3). Kurulum iptal." >&2
    logger -p kern.emerg "aegis-time-nts: Ag katmaninda Nisap saglanamadi. MitM veya Kesinti Riski."
    exit 1
fi

readonly BACKUP_DIR=$(mktemp -d -p /run aegis-chrony-backup.XXXXXX)
chmod 700 "$BACKUP_DIR"
if [[ ! -f "$CHRONY_CONF" ]]; then
    echo "[FATAL] $CHRONY_CONF bulunamadı." >&2
    rm -rf "$BACKUP_DIR"
    exit 1
fi

if ! cp -a "$CHRONY_CONF" "$BACKUP_DIR/chrony.conf.bak"; then
    echo "[FATAL] Konfigürasyon yedeği alınamadı!" >&2
    rm -rf "$BACKUP_DIR"
    exit 1
fi

SERVICE_WAS_ACTIVE=0
SERVICE_WAS_ENABLED=$(systemctl is-enabled chronyd 2>/dev/null || echo "unknown")
[[ $(systemctl is-active chronyd 2>/dev/null) == "active" ]] && SERVICE_WAS_ACTIVE=1

DISK_WRITTEN=0
ROLLBACK_DONE=0
readonly SECURE_TMP_DIR=$(mktemp -d /run/lock/layer01b_nts.XXXXXX)
chmod 700 "$SECURE_TMP_DIR"
readonly TMP_CONF="${SECURE_TMP_DIR}/chrony.conf.tmp"

# 6. DETERMINISTIK TRAP VE SELINUX GÜVENCELİ KATI STATE ROLLBACK
cleanup() {
    local exit_code=$?
    trap - EXIT INT TERM ERR HUP QUIT
    
    if [[ $ROLLBACK_DONE -eq 1 ]]; then
        [[ -d "${BACKUP_DIR:-}" ]] && rm -rf "$BACKUP_DIR"
        [[ -d "${SECURE_TMP_DIR:-}" ]] && rm -rf "$SECURE_TMP_DIR"
        return 0
    fi
    
    if [[ $exit_code -ne 0 ]]; then
        logger -p kern.warn "aegis-time-nts: HATA! NTS Mühürlemesi Çöktü! Adli Rollback Başlatılıyor..."
        
        if [[ $DISK_WRITTEN -eq 1 && -f "$BACKUP_DIR/chrony.conf.bak" ]]; then
            local TMP_ROLLBACK
            TMP_ROLLBACK=$(mktemp -p /etc chrony-rollback.XXXXXX.conf)
            chmod 600 "$TMP_ROLLBACK"
            if cp -a "$BACKUP_DIR/chrony.conf.bak" "$TMP_ROLLBACK" && mv "$TMP_ROLLBACK" "$CHRONY_CONF"; then
                restorecon -R -F /etc/chrony.conf /var/lib/chrony /run/chrony /etc/chrony.keys /var/log/chrony >/dev/null 2>&1
                sync -d "$CHRONY_CONF"
            else
                logger -p kern.emerg "aegis-time-nts: ROLLBACK KRİZİ! Fiziksel disk restorasyonu başarısız!"
            fi
        fi
        
        case "$SERVICE_WAS_ENABLED" in
            "enabled") systemctl enable chronyd >/dev/null 2>&1 || true ;;
            "disabled") systemctl disable chronyd >/dev/null 2>&1 || true ;;
            "masked") systemctl mask chronyd >/dev/null 2>&1 || true ;;
        esac

        if [[ $SERVICE_WAS_ACTIVE -eq 1 ]]; then
            systemctl restart chronyd >/dev/null 2>&1 || true
        else
            systemctl stop chronyd >/dev/null 2>&1 || true
        fi
    fi
    
    ROLLBACK_DONE=1
    [[ -d "${BACKUP_DIR:-}" ]] && rm -rf "$BACKUP_DIR"
    [[ -d "${SECURE_TMP_DIR:-}" ]] && rm -rf "$SECURE_TMP_DIR"
    exit "$exit_code"
}
trap cleanup EXIT INT TERM ERR HUP QUIT

# 7. ATOMİK KONFİGÜRASYON ENJEKSİYONU VE SÖZDİZİMİ DENETİMİ
if ! cp -a "$CHRONY_CONF" "$TMP_CONF"; then
    echo "[FATAL] TMP dosyasına kopyalama başarısız." >&2
    exit 1
fi

if sed -n '/^# BEGIN V30_AEGIS/,/^# END V30_AEGIS/p' "$TMP_CONF" | grep -q '^# BEGIN V30_AEGIS'; then
    sed -i '/^# BEGIN V30_AEGIS/,/^# END V30_AEGIS/d' "$TMP_CONF"
fi

# Askeri Düzey Kriptografik Zaman Şablonu Enjeksiyonu
cat << 'EOF' >> "$TMP_CONF"
# BEGIN V30_AEGIS: NTS (Network Time Security) Zırhı
server time.cloudflare.com iburst nts
server nts.netnod.se iburst nts
server ptbtime1.ptb.de iburst nts
ntsdumpdir /var/lib/chrony
port 0
cmdport 0
logchanges 1
# END V30_AEGIS
EOF

# Canlı Çekirdek Parser Analizi (Sentaks Kontrolü)
if ! chronyd -Q -f "$TMP_CONF" >/dev/null 2>&1; then
    echo "[FATAL] Çekirdek Sözdizimi Hatası: Yeni konfigürasyon şablonu parse edilemedi!" >&2
    exit 1
fi

if ! mv "$TMP_CONF" "$CHRONY_CONF"; then
    echo "[FATAL] Atomik mühürleme (mv) başarısız oldu!" >&2
    exit 1
fi
DISK_WRITTEN=1

# SELinux Güvenlik Bağlamının Tüm Genişletilmiş Dizinlerle Onarımı (Kripto ve Ephemeral Alanları Dahil)
restorecon -R -Fv "$CHRONY_CONF" /var/lib/chrony /var/log/chrony /run/chrony /etc/chrony.keys
sync -d "$CHRONY_CONF"

# 8. SERVİS ORKESTRASYONU VE BAĞIMLILIK GRAFİK KİLİTLEMESİ (SYSTEMD ORCHESTRATION)
if systemctl list-units --all --type=service --no-legend 2>/dev/null | grep -q "systemd-timesyncd.service"; then
    if systemctl is-active --quiet systemd-timesyncd.service 2>/dev/null; then
        echo "[*] Masaüstü zaman eşitleyicisi çatışmayı önlemek adına durduruluyor..."
        systemctl disable --now systemd-timesyncd.service >/dev/null 2>&1 || true
    fi
fi

if ! systemctl enable chronyd >/dev/null 2>&1; then
    echo "[FATAL] Chronyd servisi Systemd üzerinde etkinleştirilemedi!" >&2
    exit 1
fi

if ! systemctl restart chronyd; then
    echo "[FATAL] Chronyd yeni NTS konfigürasyonu ile yeniden başlatılamadı!" >&2
    exit 1
fi

echo "[*] Kriptografik Zaman Senkronizasyonu Bekleniyor (Safe Burst Engine)..."
chronyc online >/dev/null 2>&1 || true
chronyc burst 4/4 >/dev/null 2>&1 || true

# MATEMATİKSEL KİMLİK BAĞLAMA VE STRÜKTÜREL KRİPTO DURUM VALIDASYONU
SYNC_SUCCESS=0
for i in {1..60}; do
    # Kolon bağımlılığı olmayan yapılandırılmış blok doğrulaması (Garantili internal kaynak denetimi)
    # Satırda FQDN/IP, hemen ardından NTS protokol tipi, Key length ve Cookies varlığı strüktürel taranır.
    if chronyc -N authdata 2>/dev/null | grep -qE "^[a-zA-Z0-9.-]+[ \t]+NTS[ \t]+[1-9][0-9]*[ \t]+[1-9][0-9]*"; then
        SYNC_SUCCESS=1
        break
    fi
    sleep 1
done

if [[ $SYNC_SUCCESS -eq 0 ]]; then
    echo "[FATAL] Kriptografik NTS doğrulaması (Cookies / Key Exchange) zaman aşımına uğradı! Durum kararsız." >&2
    exit 1
fi

# Boot-Time Drift Kontrolü: Systemd Bağımlılık Zincirinin Teşhisli Tetiklenmesi (Deadlock Kalkanlı)
if systemctl list-unit-files --type=service 2>/dev/null | grep -q "systemd-time-wait-sync.service"; then
    echo "[+] Boot-time zaman bağımlılık grafiği (systemd-time-wait-sync) aktif ediliyor..."
    
    # Açılış kilitlenmelerini engellemek için katı 15 saniyelik systemd override çivisi çakılır
    readonly OVERRIDE_DIR="/etc/systemd/system/systemd-time-wait-sync.service.d"
    mkdir -p "$OVERRIDE_DIR"
    cat << 'EOF' > "${OVERRIDE_DIR}/override.conf"
[Service]
ExecStart=
ExecStart=/usr/lib/systemd/systemd-time-wait-sync --timeout=15
EOF
    chmod 644 "${OVERRIDE_DIR}/override.conf"
    systemctl daemon-reload
    
    systemctl enable systemd-time-wait-sync.service >/dev/null 2>&1 || true
    systemctl restart systemd-time-wait-sync.service || true
fi

echo "============================================================"
echo "✅ [BAŞARILI] Chrony NTS (Zaman Şifrelemesi) Mühürlendi! (V30)"
echo "============================================================"
echo "🛡️ CHRONY TRACKING DURUMU:"
chronyc tracking | grep -E "Reference ID|Leap status"
echo "------------------------------------------------------------"
echo "🛡️ NTS STRÜKTÜREL AUTHDATA DOĞRULAMASI:"
chronyc -N authdata
echo "============================================================"
exit 0
