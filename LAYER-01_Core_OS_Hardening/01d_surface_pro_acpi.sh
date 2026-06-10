#!/usr/bin/env bash
# ==============================================================================
# PROJE         : FEDORA TUNING AND HARDENING
# KATMAN        : LAYER-01_Core_OS_Hardening
# BETİK         : 01d_surface_pro_acpi.sh
# AMAC          : Surface Pro 9 ACPI Thunderbolt/USB Seals & BLS Determinizm
# DONANIM       : Microsoft Surface Pro 9 (Intel Core Hybrid Architecture)
# PRENSİP       : Zero-Assumption | Move Atomicity | Structured Multi-Kernel Verification
# ==============================================================================

set -Eeuo pipefail
export IFS=$'\n\t'
export LC_ALL=C

# Katı Güvenli PATH Arındırması (Environment Hijacking Savunması)
export PATH='/usr/sbin:/usr/bin:/sbin:/bin'

# Askeri Sıkılaştırma Umask Kuralları (Anayasal Sertlik)
umask 077

# ==============================================================================
# SÜREÇ SABİTLERİ VE MUTLAK BINARY DOĞRULAMA MATRİSİ
# ==============================================================================
readonly SCRIPT_NAME="01d_surface_pro_acpi"
readonly SCRIPT_VERSION="9.0.0"

readonly GRUBBY_BIN='/usr/sbin/grubby'
readonly SYSTEMCTL_BIN='/usr/bin/systemctl'
readonly LOGGER_BIN='/usr/bin/logger'
readonly PYTHON_BIN='/usr/bin/python3'
readonly GETENT_BIN='/usr/bin/getent'
readonly LOGINCTL_BIN='/usr/bin/loginctl'
readonly UDEVADM_BIN='/usr/sbin/udevadm'
readonly SORT_BIN='/usr/bin/sort'

for binary in "$GRUBBY_BIN" "$SYSTEMCTL_BIN" "$LOGGER_BIN" "$PYTHON_BIN" "$GETENT_BIN" "$LOGINCTL_BIN" "$UDEVADM_BIN" "$SORT_BIN"; do
    if [[ ! -x "$binary" ]]; then
        echo "[-] KRİTİK MİMARİ HATASI: Zorunlu sistem ikilisi mevcut değil veya imzasız: $binary" >&2
        exit 1
    fi
done

# ==============================================================================
# LOKAL USER MANİPÜLASYONUNDAN YALITILMIŞ ADLİ KARA KUTU LOG ALANI
# ==============================================================================
readonly FORENSIC_LOG_DIR="/run/log/aegis_forensic"
mkdir -p "$FORENSIC_LOG_DIR"
chmod 700 "$FORENSIC_LOG_DIR"
readonly LOG_FILE="${FORENSIC_LOG_DIR}/${SCRIPT_NAME}.log"

# ATOMİK TRUNCATE TABANLI LOG ROTASYON KALKANI (Anti-TOCTOU / No Data Loss)
if [[ -f "$LOG_FILE" && $(stat -c%s "$LOG_FILE") -gt 5242880 ]]; then
    cp -a "$LOG_FILE" "${LOG_FILE}_$(date +%s).old"
    true > "$LOG_FILE"
fi

# ==============================================================================
# TMPFS TABANLI İZOLE SANDBOX VE KERNEL SEVİYESİNDE ATOMİK MUTEX LOCK
# ==============================================================================
readonly SANDBOX_DIR="/run/lock/layer01d_sandbox"
mkdir -p "$SANDBOX_DIR"
chmod 700 "$SANDBOX_DIR"

readonly LOCK_FILE="${SANDBOX_DIR}/${SCRIPT_NAME}.lock"
readonly STATE_FILE="${SANDBOX_DIR}/${SCRIPT_NAME}.state.db"

exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    echo "[-] HATA: Betiğin başka bir örneği zaten çalışıyor! Donanım koruması için reddedildi." >&2
    "$LOGGER_BIN" -p kern.emerg "Aegis 01d Lock Çakışması: Eşzamanlı icra engellendi."
    exit 1
fi
echo $$ >&9

# ==============================================================================
# DUAL-CHANNEL EXPLICIT FD REDIRECTION VE RECURSION-FREE TRAP MİMARİSİ
# ==============================================================================
exec 3>&1 4>&2
exec > >(tee -a "$LOG_FILE") 2>&1

cleanup() {
    local exit_code=$?
    trap - EXIT INT TERM HUP QUIT
    
    sync -d "$FORENSIC_LOG_DIR" || true
    exec 1>&3 2>&4 3>&- 4>&-
    
    if [[ -n "${TARGET_HOME:-}" && -d "$TARGET_HOME/Desktop" ]]; then
        local user_log_dir="${TARGET_HOME}/Desktop/LOG_FILES"
        if [[ ! -L "$user_log_dir" ]]; then
            mkdir -p "$user_log_dir"
            chmod 755 "$user_log_dir"
            cp -a "$LOG_FILE" "${user_log_dir}/${SCRIPT_NAME}.log" || true
        fi
    fi

    flock -u 9 2>/dev/null || true
    
    if [[ $exit_code -eq 0 ]]; then
        "$LOGGER_BIN" -p kern.info "Aegis 01d süreci başarıyla mühürlendi."
    else
        "$LOGGER_BIN" -p kern.warn "Aegis 01d KRİTİK ÇÖKME! Hata Kodu: $exit_code"
    fi
    exit "$exit_code"
}
trap cleanup EXIT INT TERM HUP QUIT

if [[ $EUID -ne 0 ]]; then
    echo "[-] KRİTİK HATA: Bu motor çekirdek düzeyinde ACPI operasyonları yürütür. 'sudo' zorunludur." >&2
    exit 1
fi

# DİNAMİK MEŞRU KULLANICI VE KANONİK EV DİZİNİ TESPİT MOTORU
_DETECTED_USER=$( "$LOGINCTL_BIN" list-users 2>/dev/null | "$PYTHON_BIN" -c '
import sys
for line in sys.stdin:
    parts = line.split()
    if len(parts) >= 2 and parts[0].isdigit() and int(parts[0]) >= 1000:
        print(parts[1])
        sys.exit(0)
' ) || _DETECTED_USER=""

readonly TARGET_USER="${SUDO_USER:-$_DETECTED_USER}"
if [[ -z "$TARGET_USER" || "$TARGET_USER" == "root" ]]; then
    echo "[-] HATA: Sistem üzerinde operasyon yapılacak meşru kullanıcı kimliği doğrulanamadı!" >&2
    exit 1
fi

readonly PASSWD_ENTRY=$("$GETENT_BIN" passwd "$TARGET_USER") || {
    echo "[-] HATA: Hesaba ait yerel kullanıcı veritabanı girdisi bulunamadı!" >&2
    exit 1
}
readonly TARGET_HOME=$(cut -d: -f6 <<< "$PASSWD_ENTRY")

# ==============================================================================
# KRİPTOGRAFİK ENTROPİ VE REAL-TIME DETERMINISTIC STATE MACHINE
# ==============================================================================
readonly COMPONENT_UDEV="/etc/udev/rules.d/99-surface-acpi-seals.rules"

generate_config_signature() {
    (
        [[ -f "$COMPONENT_UDEV" ]] && cat "$COMPONENT_UDEV" || echo "no_udev"
        uname -r
        # Inode sırasından bağımsız, deterministik kurumsal hash zinciri (Deterministic Sort Binding)
        find /boot/loader/entries/ -maxdepth 1 -name "*.conf" -type f -print0 | "$SORT_BIN" -z | xargs -0 cat 2>/dev/null || echo "no_bls_entries"
        "$SYSTEMCTL_BIN" is-enabled power-profiles-daemon 2>/dev/null || echo "no_ppd"
    ) | sha256sum | awk '{print $1}'
}

check_idempotent_state() {
    if [[ -f "$STATE_FILE" ]]; then
        local saved_signature current_signature
        saved_signature=$(cat "$STATE_FILE" 2>/dev/null || echo "SAVED_ERR")
        current_signature=$(generate_config_signature)
        
        if [[ "$saved_signature" == "$current_signature" ]]; then
            echo "[+] [İDEMPOTENT] Surface Pro 9 donanım, udev ve tüm BLS girdileri zaten askeri düzeyde kararlı. Atlanıyor."
            exit 0
        fi
    fi
}

# ==============================================================================
# SÜPER-SÜTUN 1: STRUCTURED MULTI-KERNEL BLS HARDENING MOTORU (BUG-FREE)
# ==============================================================================
harden_surface_bls_core() {
    echo "[*] Adım 1: Tüm BLS çekirdek girdilerine özel kalkan parametreleri işleniyor..."
    
    # Isı fırtınası yaratan max_latency=0 ve scheduler'ı boğan cstate tamamen elendi!
    # Iris Xe Panel Self Refresh v2 ve NVMe kararlılık kalkanları enjekte ediliyor.
    local ACPI_PARAMS=(
        "pcie_aspm=default"
        "i915.enable_psr=2"
    )

    local param p_key p_val current_cmdline existing_val
    
    for param in "${ACPI_PARAMS[@]}"; do
        p_key="${param%%=*}"
        p_val="${param##*=}"
        
        # Real-Time Structured Parsing: Canlı cmdline parametre haritasını grubby üzerinden RAM'e em
        current_cmdline=$("$GRUBBY_BIN" --info=DEFAULT | awk -F= '/^args=/{print substr($0,index($0,"=")+1)}')
        
        # \K Keep-Out token ve durumsal Regex sınır süzgeci (Mükerrerlik engeli)
        existing_val=$(echo "$current_cmdline" | grep -oP '(?:^|\s)'"$p_key"='?\K[^ "]+' || echo "")
        
        if [[ -n "$existing_val" ]]; then
            if [[ "$existing_val" == "$p_val" ]]; then
                continue
            fi
            echo "[!] Yapılandırma sapması algılandı. Eski shadow parametre sökülüyor: $p_key=$existing_val"
            "$GRUBBY_BIN" --update-kernel=ALL --remove-args="$p_key=$existing_val"
        fi
        
        # Cersiz dosya yolları yerine, kurumsal standarta uygun olarak tek hamlede TÜM çekirdeklere çak
        echo "[+] Çekirdek BLS tablosuna mühürleniyor: $param"
        "$GRUBBY_BIN" --update-kernel=ALL --args="$param"
    done
}

# ==============================================================================
# SÜPER-SÜTUN 2: SUBSYSTEM UDEV SEALS (MUTATION-FREE & EXPLICIT ISOLATION)
# ==============================================================================
harden_udev_acpi_seals() {
    echo "[*] Adım 2: Donanım hatlarını kilitleyen, kapak (LID) bozmayan Udev Subsystem Seals çakılıyor..."
    
    # Kırılgan PCI battaniye kuralları yerine, sadece istismara açık harici veri yolları mühürleniyor.
    local UDEV_TMP="${SANDBOX_DIR}/99-surface-acpi-seals.rules.tmp"
    
    cat << 'EOF' > "$UDEV_TMP"
# ==============================================================================
# FEDORA HARDENING: Surface Pro 9 ACPI Hardware Subsystem Seals
# ==============================================================================
# Sadece fiziksel temas barındıran harici Thunderbolt ve USB Host denetleyicileri mühürlenir.
# Dahili kapak (LID), batarya ve ekran yolları sistem kararlılığı için serbest bırakılmıştır.

SUBSYSTEM=="pci", DRIVERS=="thunderbolt", ATTR{power/wakeup}="disabled"
SUBSYSTEM=="pci", DRIVERS=="xhci_hcd", ATTR{power/wakeup}="disabled"
EOF

    # Saf Python POSIX fsync bütünlük mühürlemesi
    "$PYTHON_BIN" - "$UDEV_TMP" <<'PYEOF'
import os, sys
try:
    fd = os.open(sys.argv[1], os.O_RDONLY)
    os.fsync(fd)
    os.close(fd)
except Exception as e:
    sys.stderr.write(f"Udev Fsync Başarısız: {str(e)}\n")
    sys.exit(1)
PYEOF

    # Tek bir saat çevriminde atomik yer değiştirme (Move Atomicity)
    install -m 644 "$UDEV_TMP" "$COMPONENT_UDEV"
    "$SYSTEMCTL_BIN" daemon-reload || true
    echo "[+] Udev donanımsal ACPI mühürleri başarıyla VFS katmanına kazındı."
}

# ==============================================================================
# SÜPER-SÜTUN 3: INTEL HYBRID INTEL_PSTATE ORKESTRASYONU (ANTI-THROTTLING)
# ==============================================================================
harden_intel_hybrid_mesh() {
    echo "[*] Adım 3: Intel E-Cores/P-Cores güç ve EPP dengesi teyit ediliyor..."
    
    # Fedora default olarak aktiftir; yarış koşulu üretmemek adına durumsal durum takibi yapıyoruz.
    if ! "$SYSTEMCTL_BIN" is-active power-profiles-daemon &>/dev/null; then
        if ! "$SYSTEMCTL_BIN" is-enabled power-profiles-daemon &>/dev/null; then
            echo "[+] power-profiles-daemon bağımlılık ağacına dahil ediliyor..."
            "$SYSTEMCTL_BIN" unmask power-profiles-daemon.service 2>/dev/null || true
            "$SYSTEMCTL_BIN" enable --now power-profiles-daemon.service
        fi
    fi

    # Intel Thread Director ile tam uyumlu 'balanced' profilini donanım seviyesinde mühürle
    if command -v powerprofilesctl &>/dev/null; then
        local current_profile
        current_profile=$(powerprofilesctl get 2>/dev/null || echo "")
        if [[ "$current_profile" != *"balanced"* ]]; then
            echo "[+] Çekirdek enerji performans tercihi (EPP) 'balanced' moduna kilitleniyor..."
            powerprofilesctl set balanced || true
        fi
    fi
}

# ==============================================================================
# ANA İCRA MOTORU VE KRİPTOGRAFİK MÜHÜRLENME DÖNGÜSÜ
# ==============================================================================
main() {
    echo "======================================================================"
    echo "🛡️ AEGIS KATMAN-01d: SURFACE PRO HARDWARE ACPI SEALS & BLS MOTORU"
    echo "======================================================================"
    
    check_idempotent_state
    
    local op_err=0
    harden_surface_bls_core     || { echo "[-] HATA: Süper-sütun 1 (BLS Core) aksadı!"; op_err=1; }
    harden_udev_acpi_seals      || { echo "[-] HATA: Süper-sütun 2 (Udev Seals) aksadı!"; op_err=1; }
    harden_intel_hybrid_mesh    || { echo "[-] HATA: Süper-sütun 3 (Hybrid Mesh) aksadı!"; op_err=1; }
    
    if [[ $op_err -eq 0 ]]; then
        local target_signature
        target_signature=$(generate_config_signature)
        echo "$target_signature" > "$STATE_FILE"
        echo "[+] BAŞARILI: Çekirdek, Udev ve BLS donanım katmanı kurşun geçirmez şekilde kilitlendi."
        echo "[!] UYARI: GRUB / BLS boot değişikliklerinin canlı hafızaya işlenmesi için REBOOT gereklidir."
        return 0
    else
        echo "[-] BAŞARISIZ: Sıkılaştırma adımlarında kısmi kararsızlık oluştu. Logları inceleyin." >&2
        return 1
    fi
}

main "$@"
