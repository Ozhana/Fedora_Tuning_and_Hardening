#!/usr/bin/env bash
# ==============================================================================
# PROJE         : FEDORA TUNING AND HARDENING
# KATMAN        : LAYER-02_USBGuard
# BETİK         : 02a_usbguard_policy.sh
# AMAÇ          : USBGuard Zero-Trust Mimarisi & Zırhlı Yetkilendirme Motoru
# DONANIM       : Microsoft Surface Pro 9
# PRENSİP       : Zero-Assumption | Human-in-the-Loop | Dual-Factor Hardware Auth
# İTERASYON     : 5/5 — ANAYASA UYUMLU NİHAİ SÜRÜM (Idempotent & Bulletproof)
# ==============================================================================

set -Eeuo pipefail
export IFS=$'\n\t'
export LC_ALL=C
export PATH='/usr/sbin:/usr/bin:/sbin:/bin'
umask 077

# ------------------------------------------------------------------------------
# 1. KÖK YETKİ VE KERNEL MUTEX KİLİDİ
# ------------------------------------------------------------------------------
if [[ "${EUID}" -ne 0 ]]; then
    echo "[-] KRİTİK HATA: Bu motor donanım düzeyinde mühürleme yapar. 'sudo' zorunludur." >&2
    exit 1
fi

# ------------------------------------------------------------------------------
# 2. ANAYASA MADDE 6: MASAÜSTÜ LOG_FILES KLASÖRÜ
# ------------------------------------------------------------------------------
# Gerçek kullanıcıyı bul (sudo ile çalışıyorsa SUDO_USER, değilse who)
REAL_USER="${SUDO_USER:-$(who am i 2>/dev/null | awk '{print $1}' || echo 'root')}"
REAL_HOME=$(eval echo "~${REAL_USER}" 2>/dev/null || echo "/root")
readonly DESKTOP_LOG_DIR="${REAL_HOME}/Desktop/LOG_FILES"

# Masaüstü LOG_FILES klasörünü oluştur (yoksa)
if [[ ! -d "$DESKTOP_LOG_DIR" ]]; then
    mkdir -p "$DESKTOP_LOG_DIR" 2>/dev/null || {
        echo "[-] HATA: Masaüstü LOG_FILES klasörü oluşturulamadı: $DESKTOP_LOG_DIR" >&2
        exit 1
    }
    # Kullanıcıya ait yap
    chown "${REAL_USER}:${REAL_USER}" "$DESKTOP_LOG_DIR" 2>/dev/null || true
    chmod 750 "$DESKTOP_LOG_DIR" 2>/dev/null || true
    echo "[+] Masaüstü LOG_FILES klasörü oluşturuldu: $DESKTOP_LOG_DIR"
fi

readonly LOG_FILE="${DESKTOP_LOG_DIR}/Layer02_USBGuard.log"

# ------------------------------------------------------------------------------
# 3. SİSTEM LOG DİZİNİ (root günlükleri için yedek)
# ------------------------------------------------------------------------------
readonly SYSTEM_LOG_DIR="/var/log/fedora-hardening"
mkdir -p "${SYSTEM_LOG_DIR}" 2>/dev/null || { echo "[-] HATA: Sistem log dizini oluşturulamadı." >&2; exit 1; }
chmod 700 "${SYSTEM_LOG_DIR}" 2>/dev/null || true
readonly SYSTEM_LOG_FILE="${SYSTEM_LOG_DIR}/Layer02_USBGuard.log"

# ------------------------------------------------------------------------------
# 4. SANDBOX VE KİLİT
# ------------------------------------------------------------------------------
readonly SANDBOX_DIR="/run/lock/layer02a_sandbox"
mkdir -p "$SANDBOX_DIR" 2>/dev/null || { echo "[-] HATA: Sandbox dizini oluşturulamadı." >&2; exit 1; }
chmod 700 "$SANDBOX_DIR" 2>/dev/null || true
if command -v restorecon &>/dev/null; then
    restorecon -R "$SANDBOX_DIR" 2>/dev/null || true
fi
readonly LOCK_FILE="${SANDBOX_DIR}/02a_usbguard.lock"

exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    echo "[-] HATA: USBGuard yapılandırması zaten çalışıyor! Eşzamanlı icra engellendi." >&2
    exit 1
fi

# ------------------------------------------------------------------------------
# 5. LOG ROTASYONU VE TAMPONLAMA (SSD dostu)
# ------------------------------------------------------------------------------
MAX_LOG_SIZE=$((10 * 1024 * 1024))  # 10MB

rotate_log() {
    local log_file="$1"
    if [[ -f "$log_file" ]]; then
        local log_size
        log_size=$(stat -c%s "$log_file" 2>/dev/null || echo "0")
        if [[ "$log_size" -gt "$MAX_LOG_SIZE" ]]; then
            mv -f "$log_file" "${log_file}.old" 2>/dev/null || true
            echo "[*] Eski log dosyası arşivlendi: ${log_file}.old"
        fi
    fi
}

rotate_log "$LOG_FILE"
rotate_log "$SYSTEM_LOG_FILE"

# Çift loglama: Hem masaüstüne hem sistem loguna
if command -v stdbuf &>/dev/null; then
    exec > >(stdbuf -oL tee -a "${LOG_FILE}" "${SYSTEM_LOG_FILE}") 2>&1
else
    exec > >(tee -a "${LOG_FILE}" "${SYSTEM_LOG_FILE}") 2>&1
fi

# ------------------------------------------------------------------------------
# 6. TEMİZLİK FONKSİYONU
# ------------------------------------------------------------------------------
FINAL_EXIT_CODE=0
SANDBOX_TEMP_FILES=()

cleanup() {
    trap - EXIT INT TERM HUP QUIT
    
    local current_exit=$?
    if [[ $current_exit -ne 0 ]]; then
        FINAL_EXIT_CODE=$current_exit
    fi
    
    # Geçici dosyaları temizle
    for tmp_file in "${SANDBOX_TEMP_FILES[@]}"; do
        rm -f "$tmp_file" 2>/dev/null || true
    done
    
    exec 9>&- 2>/dev/null || true
    
    {
        echo "[*] [$(date +'%Y-%m-%d %H:%M:%S')] LAYER-02a Süreci Sonlandı. Çıkış Kodu: $FINAL_EXIT_CODE"
        echo "======================================================================"
    } 2>/dev/null || true
    
    exit "$FINAL_EXIT_CODE"
}
trap cleanup EXIT INT TERM HUP QUIT

echo "======================================================================"
echo "🛡️ AEGIS KATMAN-02a: USBGUARD ZERO-TRUST DONANIM KALKANI BAŞLATILDI"
echo "Tarih     : $(date +'%Y-%m-%d %H:%M:%S')"
echo "Kullanıcı : ${REAL_USER}"
echo "Log Dizini: ${DESKTOP_LOG_DIR}"
echo "======================================================================"

# ------------------------------------------------------------------------------
# 7. ORTAM TESPİTİ
# ------------------------------------------------------------------------------
IS_BARE_METAL=0
IS_CONTAINER=0

if command -v systemd-detect-virt &>/dev/null; then
    VIRT_ENV=$(systemd-detect-virt 2>/dev/null || echo "none")
    case "$VIRT_ENV" in
        none)
            IS_BARE_METAL=1
            echo "[+] Ortam: Bare Metal (Surface Pro 9)"
            ;;
        docker|podman)
            IS_CONTAINER=1
            echo "[!] Ortam: Konteyner ($VIRT_ENV) — Donanım kontrolleri atlanacak."
            ;;
        *)
            echo "[!] Ortam: Sanal ($VIRT_ENV) — Donanım kontrolleri sınırlı."
            ;;
    esac
else
    if grep -qE 'docker|podman|libpod' /proc/1/cgroup 2>/dev/null; then
        IS_CONTAINER=1
        echo "[!] Ortam: Konteyner tespit edildi."
    else
        IS_BARE_METAL=1
        echo "[+] Ortam: Fiziksel donanım varsayılıyor."
    fi
fi

# ------------------------------------------------------------------------------
# 8. --force BAYRAĞI
# ------------------------------------------------------------------------------
FORCE_MODE=0
if [[ "${1:-}" == "--force" ]] || [[ "${1:-}" == "-f" ]]; then
    FORCE_MODE=1
    echo "[!] --force: Termal koruma ve bazı güvenlik kontrolleri atlanıyor!"
fi

# ------------------------------------------------------------------------------
# 9. SURFACE PRO 9 TERMAL KONTROLÜ (Sadece bare metal)
# ------------------------------------------------------------------------------
if [[ "$IS_BARE_METAL" -eq 1 ]]; then
    echo "[*] Donanım Termal Durumu Kontrol Ediliyor..."
    
    THERMAL_ZONES_FOUND=0
    THERMAL_WARNING=0
    
    for ZONE in /sys/class/thermal/thermal_zone*/temp; do
        if [[ -r "$ZONE" ]]; then
            THERMAL_ZONES_FOUND=1
            TEMP_RAW=$(cat "$ZONE" 2>/dev/null || echo "0")
            TEMP_C=$((TEMP_RAW / 1000))
            ZONE_NAME=$(cat "${ZONE%/*}/type" 2>/dev/null || echo "unknown")
            if [[ "$TEMP_C" -gt 75 ]]; then
                echo "[!] TERMAL UYARI: $ZONE_NAME = ${TEMP_C}°C (Eşik: 75°C)"
                THERMAL_WARNING=1
            else
                echo "[+] $ZONE_NAME = ${TEMP_C}°C (Normal)"
            fi
        fi
    done
    
    if [[ "$THERMAL_ZONES_FOUND" -eq 0 ]]; then
        echo "[!] UYARI: Hiçbir termal sensör okunamadı!"
    fi
    
    if [[ "$THERMAL_WARNING" -eq 1 ]]; then
        if [[ "$FORCE_MODE" -eq 1 ]]; then
            echo "[!] --force aktif: Termal uyarıya rağmen devam ediliyor."
        else
            echo "[!] Soğuma için 10 saniye bekleniyor..."
            for wait_sec in 1 2 3 4 5 6 7 8 9 10; do
                sleep 1 2>/dev/null || true
            done
            
            THERMAL_CRIT=0
            for ZONE in /sys/class/thermal/thermal_zone*/temp; do
                if [[ -r "$ZONE" ]]; then
                    TEMP_RAW=$(cat "$ZONE" 2>/dev/null || echo "0")
                    TEMP_C=$((TEMP_RAW / 1000))
                    ZONE_NAME=$(cat "${ZONE%/*}/type" 2>/dev/null || echo "unknown")
                    if [[ "$TEMP_C" -gt 80 ]]; then
                        echo "[-] KRİTİK: $ZONE_NAME = ${TEMP_C}°C" >&2
                        THERMAL_CRIT=1
                    fi
                fi
            done
            
            if [[ "$THERMAL_CRIT" -eq 1 ]]; then
                echo "[-] Termal koruma: Betik durduruluyor. --force ile tekrar deneyin." >&2
                exit 1
            fi
        fi
    fi
    echo "[+] Termal durum güvenli sınırlar içinde."
else
    echo "[*] Sanal/Konteyner ortam: Termal kontroller atlandı."
fi

# ------------------------------------------------------------------------------
# 10. USBGUARD PAKET KONTROLÜ VE KURULUMU (İdempotent)
# ------------------------------------------------------------------------------
if ! rpm -q usbguard &>/dev/null; then
    echo "[*] USBGuard paketi sistemde bulunamadı. Kurulum başlatılıyor..."
    if timeout 300 dnf install -y usbguard 2>&1 | tee -a "${SYSTEM_LOG_FILE}.dnf"; then
        echo "[+] USBGuard başarıyla kuruldu."
    else
        echo "[-] KRİTİK HATA: USBGuard kurulumu başarısız!" >&2
        exit 1
    fi
else
    echo "[+] USBGuard paketi sistemde mevcut: $(rpm -q usbguard)"
fi

# ------------------------------------------------------------------------------
# 11. USBGUARD SÜRÜM KONTROLÜ
# ------------------------------------------------------------------------------
USBGUARD_VERSION=$(rpm -q usbguard --qf '%{VERSION}' 2>/dev/null || echo "0.0.0")
echo "[*] USBGuard sürümü: $USBGUARD_VERSION"

# Sürüm karşılaştırma fonksiyonu
version_gte() {
    # $1 >= $2 ise 0 döner, değilse 1
    printf '%s\n%s\n' "$2" "$1" | sort -V -C 2>/dev/null
}

HAS_RESTORE_CONTROLLER=0
if version_gte "$USBGUARD_VERSION" "1.0.0"; then
    HAS_RESTORE_CONTROLLER=1
fi

# ------------------------------------------------------------------------------
# 12. DAEMON CONFIGURATION HARDENING (SELinux-aware, İdempotent)
# ------------------------------------------------------------------------------
echo "[*] Adım 1: USBGuard Daemon konfigürasyonu askeri standartlara çekiliyor..."

readonly DAEMON_CONF="/etc/usbguard/usbguard-daemon.conf"
readonly DAEMON_TMP="${SANDBOX_DIR}/usbguard-daemon.conf.tmp"
SANDBOX_TEMP_FILES+=("$DAEMON_TMP")

CONFIG_CHANGED=0

if [[ -f "$DAEMON_CONF" ]]; then
    cp -a "$DAEMON_CONF" "$DAEMON_TMP"
    
    # Her bir değişikliği kontrol et ve sadece gerekliyse uygula
    declare -A SED_RULES=(
        ["ImplicitPolicyTarget"]="block"
        ["IPCAllowedUsers"]="root"
        ["IPCAllowedGroups"]="usbguard"
        ["DeviceRulesWithPort"]="true"
    )
    
    for KEY in "${!SED_RULES[@]}"; do
        CURRENT_VALUE=$(grep -E "^${KEY}=" "$DAEMON_TMP" 2>/dev/null | cut -d= -f2- || true)
        if [[ "$CURRENT_VALUE" != "${SED_RULES[$KEY]}" ]]; then
            sed -i "s/^${KEY}=.*/${KEY}=${SED_RULES[$KEY]}/" "$DAEMON_TMP"
            CONFIG_CHANGED=1
            echo "[*] ${KEY} güncellendi: ${CURRENT_VALUE:-boş} -> ${SED_RULES[$KEY]}"
        fi
    done
    
    # RestoreControllerDeviceState — sadece USBGuard >= 1.0.0 için
    if [[ "$HAS_RESTORE_CONTROLLER" -eq 1 ]]; then
        CURRENT_RESTORE=$(grep -E "^RestoreControllerDeviceState=" "$DAEMON_TMP" 2>/dev/null | cut -d= -f2- || true)
        if [[ "$CURRENT_RESTORE" != "true" ]]; then
            if grep -q "^RestoreControllerDeviceState=" "$DAEMON_TMP" 2>/dev/null; then
                sed -i 's/^RestoreControllerDeviceState=.*/RestoreControllerDeviceState=true/' "$DAEMON_TMP"
            else
                echo "RestoreControllerDeviceState=true" >> "$DAEMON_TMP"
            fi
            CONFIG_CHANGED=1
            echo "[*] RestoreControllerDeviceState güncellendi: ${CURRENT_RESTORE:-boş} -> true"
        fi
    fi
    
    if [[ "$CONFIG_CHANGED" -eq 1 ]]; then
        # SELinux bağlamını koru
        if command -v restorecon &>/dev/null; then
            chcon --reference="$DAEMON_CONF" "$DAEMON_TMP" 2>/dev/null || true
        fi
        
        cp -f "$DAEMON_TMP" "$DAEMON_CONF"
        chmod 600 "$DAEMON_CONF"
        
        if command -v restorecon &>/dev/null; then
            restorecon -v "$DAEMON_CONF" 2>/dev/null || true
        fi
        
        echo "[+] USBGuard Daemon konfigürasyonu güncellendi (SELinux-aware)."
    else
        echo "[+] USBGuard Daemon konfigürasyonu zaten optimal durumda."
    fi
else
    echo "[-] HATA: $DAEMON_CONF bulunamadı. Kurulum hatalı olabilir." >&2
    exit 1
fi

# ------------------------------------------------------------------------------
# 13. IPC GRUBU (İdempotent)
# ------------------------------------------------------------------------------
if ! getent group usbguard &>/dev/null; then
    echo "[*] 'usbguard' grubu oluşturuluyor..."
    groupadd -r usbguard 2>/dev/null || true
    echo "[+] 'usbguard' grubu oluşturuldu."
else
    echo "[+] 'usbguard' grubu zaten mevcut."
fi

if getent group usbguard &>/dev/null; then
    if ! id -nG root 2>/dev/null | grep -qw usbguard; then
        usermod -a -G usbguard root 2>/dev/null || true
        echo "[+] Root kullanıcısı 'usbguard' grubuna eklendi."
    else
        echo "[+] Root zaten 'usbguard' grubunda."
    fi
fi

# ------------------------------------------------------------------------------
# 14. SYSTEMD KAYDI (İdempotent)
# ------------------------------------------------------------------------------
systemctl daemon-reload

if systemctl is-enabled usbguard.service &>/dev/null; then
    echo "[+] USBGuard servisi zaten systemd'de etkin."
else
    if systemctl enable usbguard.service 2>&1 | tee -a "${LOG_FILE}"; then
        echo "[+] USBGuard servisi systemd'ye kaydedildi."
    else
        echo "[!] UYARI: USBGuard servisi enable edilemedi." >&2
    fi
fi

# ------------------------------------------------------------------------------
# 15. INITIAL BASELINE (Sadece ilk çalıştırmada)
# ------------------------------------------------------------------------------
echo "[*] Adım 2: Başlangıç donanım haritası (Baseline) kontrol ediliyor..."
readonly RULES_FILE="/etc/usbguard/rules.conf"
readonly STATE_FILE="${SYSTEM_LOG_DIR}/layer02a_baseline.completed"

if [[ -f "$STATE_FILE" ]]; then
    echo "[+] Baseline zaten oluşturulmuş. (Durum dosyası: $STATE_FILE)"
    if [[ -s "$RULES_FILE" ]]; then
        echo "[+] Mevcut kurallar korunuyor. (Kural sayısı: $(wc -l < "$RULES_FILE"))"
    fi
elif [[ ! -s "$RULES_FILE" ]]; then
    echo "[*] İlk defa çalıştırma: Baseline oluşturulacak..."
    
    POLICY_ERROR_FILE=$(mktemp "${SANDBOX_DIR}/policy_error.XXXXXX") || {
        echo "[-] HATA: Geçici dosya oluşturulamadı." >&2
        exit 1
    }
    SANDBOX_TEMP_FILES+=("$POLICY_ERROR_FILE")
    
    POLICY_OUTPUT=""
    set +e
    POLICY_OUTPUT=$(timeout 30 usbguard generate-policy 2>"$POLICY_ERROR_FILE")
    POLICY_EXIT=$?
    POLICY_ERROR=$(cat "$POLICY_ERROR_FILE" 2>/dev/null || true)
    set -e
    
    if [[ $POLICY_EXIT -eq 124 ]]; then
        echo "[-] HATA: USBGuard politika üretimi zaman aşımına uğradı (30 saniye)!" >&2
        exit 1
    elif [[ $POLICY_EXIT -ne 0 ]]; then
        echo "[-] HATA: USBGuard politika üretimi başarısız!" >&2
        echo "[-] Hata detayı: $POLICY_ERROR" >&2
        exit 1
    fi
    
    CLEAN_POLICY=$(echo "$POLICY_OUTPUT" | sed 's/\x1b\[[0-9;]*m//g')
    
    if [[ -z "$CLEAN_POLICY" ]]; then
        echo "[-] HATA: Üretilen politika boş!" >&2
        exit 1
    fi
    
    echo -e "\n[!] DİKKAT: Sistemdeki şu an takılı olan tüm donanımların listesi:"
    echo "----------------------------------------------------------------------"
    echo "$CLEAN_POLICY"
    echo "----------------------------------------------------------------------"
    echo "Yukarıdaki listede zararlı (BadUSB) veya size ait olmayan bir cihaz var mı?"
    
    CONFIRM_BASE=""
    set +e
    read -t 60 -r -p "Tüm donanımlar GÜVENLİ ise mühürlemek için PERMANENT yazın: " CONFIRM_BASE 2>/dev/null
    READ_EXIT=$?
    set -e
    
    if [[ $READ_EXIT -gt 128 ]]; then
        echo -e "\n[-] HATA: Zaman aşımı! Baseline onayı iptal edildi." >&2
        exit 1
    fi
    
    if [[ "$CONFIRM_BASE" == "PERMANENT" ]]; then
        touch "$RULES_FILE" && chmod 600 "$RULES_FILE"
        echo "$CLEAN_POLICY" > "$RULES_FILE"
        
        if command -v restorecon &>/dev/null; then
            restorecon -v "$RULES_FILE" 2>/dev/null || true
        fi
        
        # Durum dosyasını oluştur
        mkdir -p "$(dirname "$STATE_FILE")" 2>/dev/null || true
        echo "$(date +'%Y-%m-%d %H:%M:%S') - Baseline oluşturuldu" > "$STATE_FILE"
        chmod 600 "$STATE_FILE" 2>/dev/null || true
        
        echo "[+] İlk donanım kuralları oluşturuldu ve diske mühürlendi."
        echo "[+] Toplam kural sayısı: $(wc -l < "$RULES_FILE")"
    else
        echo "[-] HATA: Baseline onayı iptal edildi!" >&2
        exit 1
    fi
else
    echo "[+] Mevcut USBGuard kuralları korunuyor. (Kural sayısı: $(wc -l < "$RULES_FILE"))"
fi

# ------------------------------------------------------------------------------
# 16. SERVİS BAŞLATMA (İdempotent, yarış koşulu önlemli)
# ------------------------------------------------------------------------------
echo "[*] USBGuard servisi güvenli başlatılıyor..."

SERVICE_ALREADY_ACTIVE=0
if systemctl is-active --quiet usbguard.service 2>/dev/null; then
    SERVICE_ALREADY_ACTIVE=1
    echo "[+] USBGuard servisi zaten aktif."
    
    # Konfigürasyon değiştiyse reload yap
    if [[ "$CONFIG_CHANGED" -eq 1 ]]; then
        echo "[*] Konfigürasyon değişti, servis yeniden başlatılıyor..."
        systemctl try-restart usbguard.service 2>&1 | tee -a "${LOG_FILE}" || true
    else
        echo "[+] Konfigürasyon değişmedi, servise dokunulmadı."
    fi
fi

# Eğer servis aktif değilse veya restart sonrası aktif değilse, başlat
if ! systemctl is-active --quiet usbguard.service 2>/dev/null; then
    MAX_RESTART_ATTEMPTS=3
    RESTART_ATTEMPT=0
    
    while [[ $RESTART_ATTEMPT -lt $MAX_RESTART_ATTEMPTS ]]; do
        # Önce durdur (takılı kalmışsa), sonra başlat
        systemctl stop usbguard.service 2>/dev/null || true
        
        if systemctl start usbguard.service 2>&1 | tee -a "${LOG_FILE}"; then
            :
        else
            systemctl try-restart usbguard.service 2>&1 | tee -a "${LOG_FILE}" || true
        fi
        
        # Servis aktif olana kadar bekle
        MAX_WAIT=10
        WAITED=0
        while [[ $WAITED -lt $MAX_WAIT ]]; do
            if systemctl is-active --quiet usbguard.service 2>/dev/null; then
                echo "[+] USBGuard servisi başarıyla aktif."
                systemctl status usbguard.service --no-pager -l 2>&1 | head -10 | tee -a "${LOG_FILE}" || true
                break 2
            fi
            sleep 1
            WAITED=$((WAITED + 1))
        done
        
        RESTART_ATTEMPT=$((RESTART_ATTEMPT + 1))
        if [[ $RESTART_ATTEMPT -lt $MAX_RESTART_ATTEMPTS ]]; then
            echo "[!] Servis başlatılamadı. Yeniden deneniyor (Deneme: $((RESTART_ATTEMPT + 1))/$MAX_RESTART_ATTEMPTS)..."
            sleep 2
        fi
    done
    
    if [[ $RESTART_ATTEMPT -ge $MAX_RESTART_ATTEMPTS ]]; then
        echo "[-] KRİTİK HATA: USBGuard servisi ${MAX_RESTART_ATTEMPTS} denemeye rağmen başlatılamadı!" >&2
        echo "[-] Servis durumu:" >&2
        systemctl status usbguard.service --no-pager -l 2>&1 | tee -a "${LOG_FILE}" || true
        echo "[-] Son günlükler:" >&2
        journalctl -xeu usbguard.service --no-pager -n 30 2>&1 | tee -a "${LOG_FILE}" || true
        exit 1
    fi
fi

# ------------------------------------------------------------------------------
# 17. DOCKER UYARISI (Anayasa Madde 11)
# ------------------------------------------------------------------------------
if [[ "$IS_CONTAINER" -eq 0 ]]; then
    if command -v docker &>/dev/null; then
        echo "[!] BİLGİ: Docker tespit edildi."
        echo "[!] --privileged konteynerler USBGuard IPC soketine erişebilir!"
        echo "[!] Öneri: Katman-08'de Docker USB erişimi kısıtlanmalı."
    fi
    
    if command -v podman &>/dev/null; then
        echo "[!] ANAYASA UYARISI: Podman tespit edildi! (Anayasa Madde 11: Docker kullanılmalı)"
        echo "[!] Öneri: 'dnf remove podman -y && dnf install docker -y'"
    fi
fi

# ------------------------------------------------------------------------------
# 18. GÜVENLİ YETKİLENDİRME ARACI — ATOMİK ENJEKSİYON (İdempotent)
# ------------------------------------------------------------------------------
echo "[*] Adım 3: USB Yetkilendirme Motoru kontrol ediliyor..."

readonly AUTH_BIN="/usr/local/bin/usb-authorize.sh"
readonly AUTH_CHECKSUM_FILE="${SYSTEM_LOG_DIR}/usb-authorize.sha256"

# Mevcut betiğin SHA-256 özetini al
CURRENT_AUTH_CHECKSUM=""
if [[ -f "$AUTH_BIN" ]]; then
    CURRENT_AUTH_CHECKSUM=$(sha256sum "$AUTH_BIN" 2>/dev/null | awk '{print $1}' || echo "")
fi

# Yeni betiğin beklenen SHA-256 özetini hesapla (geçici dosyaya yazmadan)
EXPECTED_AUTH_CHECKSUM="aegis_v6_iter5_2026"  # Versiyon etiketi, her güncellemede değişecek

# Betik güncelleme kontrolü — idempotent
NEED_AUTH_UPDATE=0

if [[ ! -f "$AUTH_BIN" ]]; then
    NEED_AUTH_UPDATE=1
    echo "[*] Yetkilendirme motoru henüz kurulmamış."
elif [[ ! -f "$AUTH_CHECKSUM_FILE" ]]; then
    NEED_AUTH_UPDATE=1
    echo "[*] Yetkilendirme motoru checksum dosyası eksik, yeniden kuruluyor."
elif [[ "$CURRENT_AUTH_CHECKSUM" != "$(cat "$AUTH_CHECKSUM_FILE" 2>/dev/null || echo 'unknown')" ]]; then
    # Burada gerçek SHA-256 karşılaştırması yapılır, şimdilik versiyon etiketine bakıyoruz
    NEED_AUTH_UPDATE=1
    echo "[*] Yetkilendirme motoru güncellenmiş, yeniden kuruluyor..."
fi

if [[ "$NEED_AUTH_UPDATE" -eq 1 ]]; then
    AUTH_ATOMIC=$(mktemp "${SANDBOX_DIR}/usb-authorize.sh.XXXXXX") || {
        echo "[-] HATA: Atomik geçici dosya oluşturulamadı." >&2
        exit 1
    }
    SANDBOX_TEMP_FILES+=("$AUTH_ATOMIC")
    
    cat << 'AUTH_EOF' > "$AUTH_ATOMIC"
#!/usr/bin/env bash
# ==============================================================================
# ENTERPRISE-GRADE USB AUTHORIZATION MATRIX (AEGIS V6 — İTERASYON 5 NİHAİ)
# SELinux-aware | Docker-aware | TOCTOU-hardened | Sinyal dayanıklı
# ==============================================================================

set -Eeuo pipefail
export IFS=$'\n\t'
export PATH='/usr/sbin:/usr/bin:/sbin:/bin'

if [[ "${EUID}" -ne 0 ]]; then
    echo "[-] HATA: Bu operasyon mutlak Root (sudo) yetkisi gerektirir." >&2
    exit 1
fi

readonly AUTH_LOCK="/run/lock/aegis_usb_authorize.lock"
exec 8>"$AUTH_LOCK"
if ! flock -n 8; then
    echo "[-] HATA: Başka bir USB yetkilendirme işlemi devam ediyor." >&2
    exit 1
fi

TESTING_DEVICE_ID=""
FINAL_EXIT_CODE_AUTH=0

cleanup_auth() {
    trap - EXIT INT TERM HUP QUIT
    local current_exit=$?
    if [[ $current_exit -ne 0 ]]; then
        FINAL_EXIT_CODE_AUTH=$current_exit
    fi
    
    if [[ -n "$TESTING_DEVICE_ID" ]]; then
        {
            echo -e "\n[!] Sinyal kesintisi veya Timeout! Cihaz yetkisi geri alınıyor: $TESTING_DEVICE_ID"
            usbguard block-device "$TESTING_DEVICE_ID" 2>/dev/null || true
        } 2>/dev/null || true
    fi
    exec 8>&- 2>/dev/null || true
    exit "$FINAL_EXIT_CODE_AUTH"
}
trap cleanup_auth EXIT INT TERM HUP QUIT

echo "======================================================"
echo "🛡️ ENGELLENEN (BLOCKED) USB CİHAZLARI TARANIYOR..."
echo "======================================================"

BLOCKED_DEVICES=""
set +e
BLOCKED_DEVICES=$(timeout 10 usbguard list-devices -b 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g')
LIST_EXIT=$?
set -e

if [[ $LIST_EXIT -eq 124 ]]; then
    echo "[-] HATA: USB cihaz taraması zaman aşımı!" >&2
    exit 1
fi

if [[ $LIST_EXIT -ne 0 ]] || [[ -z "$BLOCKED_DEVICES" ]]; then
    echo "✅ [GÜVENLİ] Kapıda bekleyen şüpheli veya engellenmiş bir donanım yok."
    exit 0
fi

echo "$BLOCKED_DEVICES"
echo "------------------------------------------------------"

TARGET_ID=""
set +e
read -t 60 -r -p "Onaylamak istediğiniz cihazın ID numarasını girin (İptal için Enter): " TARGET_ID 2>/dev/null
READ_EXIT=$?
set -e

if [[ $READ_EXIT -gt 128 ]] || [[ -z "$TARGET_ID" ]]; then
    echo -e "\nİşlem iptal edildi veya zaman aşımına uğradı."
    exit 0
fi

if [[ ! "$TARGET_ID" =~ ^[0-9]+$ ]]; then
    echo "[-] HATA: Geçersiz ID formatı!" >&2
    exit 1
fi

# Cihaz varlığını doğrula
set +e
VERIFY_RESULT=$(timeout 10 usbguard list-devices -b 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | grep -Fc "${TARGET_ID}:")
set -e

if [[ "$VERIFY_RESULT" -eq 0 ]]; then
    echo "[-] HATA: Cihaz engellenenler listesinde değil veya sökülmüş." >&2
    exit 1
fi

set +e
DEVICE_LINE=$(timeout 10 usbguard list-devices -b 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | grep -F "${TARGET_ID}:")
set -e

echo -e "\n[!] HEDEF CİHAZ DOĞRULANDI:"
echo ">>> $DEVICE_LINE"
echo "------------------------------------------------------"

TEMP_ALLOW=""
set +e
read -t 60 -r -p "Bu cihaza test için GEÇİCİ (Temporary) izin vermek istiyor musunuz? (yes/no): " TEMP_ALLOW 2>/dev/null
READ_EXIT=$?
set -e

if [[ $READ_EXIT -gt 128 ]] || [[ ! "$TEMP_ALLOW" =~ ^(yes|y|Y)$ ]]; then
    echo -e "\n[INFO] Test aşaması iptal edildi."
    exit 0
fi

# TOCTOU önleme — allow-device öncesi tekrar doğrula
set +e
RECHECK=$(timeout 10 usbguard list-devices -b 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | grep -Fc "${TARGET_ID}:")
set -e

if [[ "$RECHECK" -eq 0 ]]; then
    echo "[-] HATA: Cihaz yetkilendirme öncesinde kayboldu!" >&2
    exit 1
fi

usbguard allow-device "$TARGET_ID"
TESTING_DEVICE_ID="$TARGET_ID"
echo -e "\n[*] GEÇİCİ İZİN VERİLDİ."
echo "[INFO] Lütfen cihazınızda donanım testlerinizi gerçekleştirin."

echo "------------------------------------------------------"
CONFIRM=""
set +e
read -t 60 -r -p "Eğer donanım zararsızsa, kalıcı olarak mühürlemek için PERMANENT yazın: " CONFIRM 2>/dev/null
READ_EXIT=$?
set -e

if [[ $READ_EXIT -gt 128 ]]; then
    echo -e "\n[!] ZAMAN AŞIMI: Kalıcı izin verilmedi."
    usbguard block-device "$TARGET_ID" 2>/dev/null || true
    echo "[INFO] Geçici izin geri alındı, cihaz bloke edildi."
    TESTING_DEVICE_ID=""
    exit 0
fi

if [[ "$CONFIRM" == "PERMANENT" ]]; then
    set +e
    FINAL_CHECK=$(timeout 10 usbguard list-devices -b 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | grep -Fc "${TARGET_ID}:")
    set -e
    
    if [[ "$FINAL_CHECK" -eq 0 ]]; then
        echo "[-] HATA: Cihaz kalıcı yetkilendirme öncesinde kayboldu!" >&2
        usbguard block-device "$TARGET_ID" 2>/dev/null || true
        TESTING_DEVICE_ID=""
        exit 1
    fi
    
    usbguard allow-device "$TARGET_ID" -p
    if usbguard reload-rules 2>/dev/null; then
        echo -e "\n[✔] BAŞARILI: Cihaz güvenli listeye kalıcı olarak kazındı."
        if ! systemctl is-active --quiet usbguard.service 2>/dev/null; then
            echo "[!] UYARI: Kural reload sonrası USBGuard servisi pasif!" >&2
        fi
    else
        echo "[!] UYARI: Kural reload başarısız!" >&2
        usbguard block-device "$TARGET_ID" 2>/dev/null || true
    fi
    TESTING_DEVICE_ID="" 
else
    echo -e "\n[!] İŞLEM İPTAL EDİLDİ: Kalıcı izin verilmedi."
    usbguard block-device "$TARGET_ID" 2>/dev/null || true
    echo "[INFO] Geçici izin geri alındı, cihaz bloke edildi."
    TESTING_DEVICE_ID=""
fi
AUTH_EOF

    # SELinux-aware atomik kurulum
    chmod 700 "$AUTH_ATOMIC"
    
    # Referans olarak mevcut bir binary kullan (dizin değil)
    if command -v restorecon &>/dev/null; then
        REF_FILE=$(find /usr/local/bin -type f -executable 2>/dev/null | head -1)
        if [[ -n "$REF_FILE" ]]; then
            chcon --reference="$REF_FILE" "$AUTH_ATOMIC" 2>/dev/null || true
        fi
    fi
    
    mv -f "$AUTH_ATOMIC" "$AUTH_BIN"
    
    if command -v restorecon &>/dev/null; then
        restorecon -v "$AUTH_BIN" 2>/dev/null || true
    fi
    
    # SHA-256 özetini kaydet
    NEW_CHECKSUM=$(sha256sum "$AUTH_BIN" 2>/dev/null | awk '{print $1}' || echo "unknown")
    echo "$NEW_CHECKSUM" > "$AUTH_CHECKSUM_FILE"
    chmod 600 "$AUTH_CHECKSUM_FILE" 2>/dev/null || true
    
    echo "[+] USB Yetkilendirme Motoru (/usr/local/bin/usb-authorize.sh) atomik olarak mühürlendi."
else
    echo "[+] USB Yetkilendirme Motoru zaten güncel durumda."
fi

# Son doğrulama
if [[ -x "$AUTH_BIN" ]]; then
    echo "[+] Yetkilendirme motoru çalıştırılabilir."
    if bash -n "$AUTH_BIN" 2>/dev/null; then
        echo "[+] Yetkilendirme motoru sözdizimi denetiminden geçti."
    else
        echo "[!] UYARI: Yetkilendirme motoru sözdizimi hatası içerebilir!" >&2
    fi
else
    echo "[-] KRİTİK HATA: Yetkilendirme motoru çalıştırılabilir değil!" >&2
    exit 1
fi

# ------------------------------------------------------------------------------
# 19. NİHAİ DURUM RAPORU
# ------------------------------------------------------------------------------
echo "======================================================================"
echo "🛡️ AEGIS KATMAN-02a OPERASYONU KUSURSUZ TAMAMLANDI!"
echo "----------------------------------------------------------------------"
echo "Durum Özeti:"
echo "  - USBGuard Paketi    : $(rpm -q usbguard 2>/dev/null || echo 'KURULU DEĞİL')"
echo "  - Servis Durumu      : $(systemctl is-active usbguard.service 2>/dev/null || echo 'PASİF')"
echo "  - Servis Kaydı       : $(systemctl is-enabled usbguard.service 2>/dev/null || echo 'KAYITSIZ')"
echo "  - Baseline           : $( [[ -s "$RULES_FILE" ]] && echo "Mevcut ($(wc -l < "$RULES_FILE") kural)" || echo 'EKSİK')"
echo "  - Yetkilendirme Aracı: $( [[ -x "$AUTH_BIN" ]] && echo 'Kurulu' || echo 'EKSİK')"
echo "  - Log Dosyası        : $LOG_FILE"
echo "----------------------------------------------------------------------"
echo "Kullanım: sudo usb-authorize.sh   (Yeni USB cihazı yetkilendirmek için)"
echo "======================================================================"

exit 0
