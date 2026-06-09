#!/usr/bin/env bash
# ==============================================================================
# PROJE         : FEDORA TUNING AND HARDENING
# KATMAN        : LAYER-00_PreFlight_Debloat
# BETİK         : 00c_telemetry_purge.sh
# AMAC          : Sistem, Ağ ve USB Telemetrilerinin Tasfiyesi & Aegis V5
# DONANIM       : Microsoft Surface Pro 9 (Intel Iris Xe)
# REFERANS      : Single-User, Ultra-Paranoid, High-Performance Baseline
# ==============================================================================

set -Eeuo pipefail
export IFS=$'\n\t'
export LC_ALL=C

# ==============================================================================
# [KORUMALI ALAN: KERNEL SEVİYESİNDE ATOMİK MUTEX LOCK]
# ==============================================================================
readonly LOCK_FILE="/run/lock/layer00_telemetry.lock"
exec 9>"$LOCK_FILE"
flock -n 9 || {
    echo "[-] KRİTİK HATA: Süreç zaten çalışıyor veya kilit altında! Çıkılıyor." >&2
    exit 1
}

# ==============================================================================
# [DİNAMİK ADLİ KULLANICI VE EV DİZİNİ TESPİT MOTORU]
# ==============================================================================
readonly TARGET_USER="${SUDO_USER:-$(logname 2>/dev/null || id -nu 1000)}"
readonly PASSWD_ENTRY=$(getent passwd "$TARGET_USER") || {
    echo "[-] HATA: Sistem üzerinde gerçek insan kullanıcı tespit edilemedi!" >&2
    exit 1
}
readonly TARGET_HOME=$(cut -d: -f6 <<< "$PASSWD_ENTRY")

if [[ -z "$TARGET_HOME" || ! -d "$TARGET_HOME" ]]; then
    echo "[-] HATA: Geçersiz ev dizini patikası!" >&2
    exit 1
fi

# ==============================================================================
# [GÜVENLİ MASAÜSTÜ LOG VE CANONICAL REALPATH ASKERİ KONTROLÜ]
# ==============================================================================
readonly LOG_DIR="${TARGET_HOME}/Desktop/LOG_FILES"

if [[ -e "$LOG_DIR" ]]; then
    readonly TARGET_HOME_REAL=$(realpath "$TARGET_HOME")
    readonly LOG_REAL=$(realpath -m "$LOG_DIR")

    case "$LOG_REAL" in
        "$TARGET_HOME_REAL"/*) ;; 
        *)
            echo "[-] SİBER ATTAK TESPİT EDİLDİ: LOG_DIR ev dizini sınırları dışına taşırıyor! ($LOG_REAL)" >&2
            exit 1
            ;;
    esac
fi

mkdir -p "$LOG_DIR"
readonly LOG_FILE="${LOG_DIR}/Layer00_Telemetry_Purge.log"

# Log Rotasyon Kalkanı (Max 5MB)
if [[ -f "$LOG_FILE" && $(stat -c%s "$LOG_FILE") -gt 5242880 ]]; then
    mv -f "$LOG_FILE" "${LOG_FILE}.old"
fi

echo "[+] [$(date +'%Y-%m-%d %H:%M:%S')] Telemetri tasfiye motoru başlatıldı." >> "$LOG_FILE"

# ==============================================================================
# [TMPFS BAZLI ATOMİK GEÇİCİ ÇALIŞMA ALANI - TOCTOU GÜVENLİKLİ]
# ==============================================================================
readonly SECURE_TMP=$(mktemp -d /run/lock/layer00c_telemetry.XXXXXX)
chmod 700 "$SECURE_TMP"

# ==============================================================================
# [TRAP & CLEANUP MİMARİSİ - DUAL-CHANNEL ADLİ LOGLAMA ENTEGRELİ]
# ==============================================================================
cleanup() {
    local exit_code=$?
    trap - EXIT INT TERM HUP QUIT
    
    if [[ -d "$SECURE_TMP" ]]; then
        rm -rf "$SECURE_TMP"
    fi
    
    local log_msg="[*] [$(date +'%Y-%m-%d %H:%M:%S')] Telemetri motoru durduruldu. Durum Kodu: ${exit_code}"
    
    if ! echo "$log_msg" >> "$LOG_FILE" 2>/dev/null; then
        echo "<3>AEGIS_CRITICAL: Telemetri motoru log dosyasina yazamadi! Çikis Kodu: ${exit_code}" > /dev/kmsg || true
    fi
    
    flock -u 9 2>/dev/null || true
    return "$exit_code"
}
trap cleanup EXIT INT TERM HUP QUIT

# ==============================================================================
# CATEGORY 01: SYSTEMD SERVİSLERİNİN VERİTABANI KONTROLLÜ MÜHÜRLENMESİ
# ==============================================================================
purge_systemd_telemetry() {
    echo "[*] Aşama 1: Systemd telemetri servisleri taranıyor ve mühürleniyor..." | tee -a "$LOG_FILE"

    local systemd_db="${SECURE_TMP}/systemd_units.db"
    
    # Header ve boş satırları eleyen, kesin isim eşleşmeli temiz POSIX taraması
    systemctl list-unit-files --no-legend --no-pager --type=service,timer | awk '{print $1}' | grep -E '\.(service|timer)$' > "$systemd_db" || true

    local candidate_units=(
        "abrtd.service"
        "abrt-journal-core.service"
        "abrt-oops.service"
        "abrt-xorg.service"
        "geoclue.service"
        "fedora-third-party-report.service"
        "abrt-pending.timer"
    )

    local unit
    for unit in "${candidate_units[@]}"; do
        if grep -q "^${unit}$" "$systemd_db"; then
            systemctl mask --now "$unit" >> "$LOG_FILE" 2>&1 || true
            echo "[+] Telemetri Birimi Kesin Olarak Mühürlendi: $unit" >> "$LOG_FILE"
        fi
    done
}
purge_systemd_telemetry

# ==============================================================================
# CATEGORY 02: AEGIS PROTOKOLÜ V5 - DUAL-VERIFICATION HARDWARE USB İZOLASYONU
# ==============================================================================
echo "[*] Aşama 2: Çekirdek seviyesinde mutlak USB modül kalkanı (Aegis V5) inşa ediliyor..." | tee -a "$LOG_FILE"

readonly USB_BLACKLIST_CONF="/etc/modprobe.d/block-usb-storage.conf"
readonly USB_TMP_CONF="${SECURE_TMP}/block-usb-storage.conf"

cat << 'EOF' > "$USB_TMP_CONF"
# FEDORA HARDENING: Aegis Modül İzolasyon Kalkanı V5
blacklist usb-storage
blacklist uas
EOF

if [[ ! -f "$USB_BLACKLIST_CONF" ]] || ! cmp -s "$USB_TMP_CONF" "$USB_BLACKLIST_CONF"; then
    install -m 644 "$USB_TMP_CONF" "$USB_BLACKLIST_CONF"
    echo "[+] USB modül kalkanı konfigürasyonu atomik olarak mühürlendi." >> "$LOG_FILE"
fi

readonly USB_AC_BIN="/usr/local/bin/usb-ac.sh"
readonly USB_KAPAT_BIN="/usr/local/bin/usb-kapat.sh"
readonly AC_TMP="${SECURE_TMP}/usb-ac.sh"
readonly KAPAT_TMP="${SECURE_TMP}/usb-kapat.sh"

# usb-ac.sh V5
cat << 'EOF' > "$AC_TMP"
#!/usr/bin/env bash
set -Eeuo pipefail
if [[ $EUID -ne 0 ]]; then echo "[!] HATA: Root yetkisi gerek." >&2; exit 1; fi

modprobe --allow-blacklist usb-storage
modprobe --allow-blacklist uas 2>/dev/null || true

echo "🔓 [SİSTEM] USB Depolama sürücüleri aktif edildi."
systemd-cat -t aegis-usb -p info <<< "USB Depolama modulleri yuklendi. Portlar depolamaya acildi."
EOF

# usb-kapat.sh V5 - Kurumsal Standartta Çekirdek Seviyesinde Donanım Süzgeci
cat << 'EOF' > "$KAPAT_TMP"
#!/usr/bin/env bash
set -Eeuo pipefail
if [[ $EUID -ne 0 ]]; then echo "[!] HATA: Root yetkisi gerek." >&2; exit 1; fi

isolate_usb_hardware() {
    echo "🛡️ [SİSTEM] USB Söküm Protokolü V5 başlatılıyor..."
    sync

    local sys_block="/sys/class/block"
    if [[ -d "$sys_block" ]]; then
        local dev_dir
        for dev_dir in "$sys_block"/*; do
            if [[ -e "$dev_dir" ]]; then
                local dev_name
                dev_name=$(basename "$dev_dir")
                
                # Heuristic string taraması çöpe atıldı; subsytem bağı mutlak olarak çözülüyor
                local subsystem_link="${dev_dir}/device/subsystem"
                if [[ -L "$subsystem_link" ]]; then
                    local real_subsystem
                    real_subsystem=$(readlink "$subsystem_link")
                    local bus_type
                    bus_type=$(basename "$real_subsystem")
                    
                    local is_usb=0
                    if [[ "$bus_type" == "usb" ]]; then
                        is_usb=1
                    # İkincil Doğrulama Hattı: NVMe bridge veya manipüle edilmiş donanımları udev tabanından yakala
                    elif command -v udevadm &>/dev/null; then
                        if udevadm info --query=property --name="/dev/${dev_name}" 2>/dev/null | grep -q "ID_BUS=usb"; then
                            is_usb=1
                        fi
                    fi
                    
                    if (( is_usb )); then
                        if [[ -f /proc/mounts ]]; then
                            while IFS= read -r mount_line; do
                                local match_dev="/dev/${dev_name}"
                                local current_dev
                                current_dev=$(echo "$mount_line" | awk '{print $1}')
                                
                                if [[ "$current_dev" == "$match_dev" ]]; then
                                    local target_mp
                                    target_mp=$(echo "$mount_line" | awk '{print $2}')
                                    echo "[!] Adli Donanım Kalkanı: Gerçek harici USB aygıtı yakalandı (${dev_name}). Sökülüyor: ${target_mp}"
                                    umount "$target_mp" 2>/dev/null || umount -l "$target_mp"
                                fi
                            done < /proc/mounts
                        fi
                    fi
                fi
            fi
        done
    fi

    if modprobe -r uas usb-storage 2>/dev/null; then
        echo "🔒 [SİSTEM] USB depolama sürücüleri çekirdekten kaldırıldı."
        systemd-cat -t aegis-usb -p info <<< "USB Depolama modulleri basariyla sokuldu. Portlar depolamaya kapatildi."
    else
        echo "[!] HATA: Sürücü modülleri kilitli veya meşgul!" >&2
        systemd-cat -t aegis-usb -p warning <<< "USB Depolama modulleri sökülemedi: Cihaz mesgul."
        exit 1
    fi
}
isolate_usb_hardware
EOF

# Betiklerin /usr/local/bin alanına atomik mühürlenmesi
install -m 755 "$AC_TMP" "$USB_AC_BIN"
install -m 755 "$KAPAT_TMP" "$USB_KAPAT_BIN"

# BASHRC ÜZERİNDEN ATOMİK ALIAS ENJEKSİYONU
readonly BASHRC_FILE="${TARGET_HOME}/.bashrc"
readonly BASHRC_TMP="${SECURE_TMP}/.bashrc"
readonly ALIAS_MARKER="# 🏎️ FEDORA KURULUM USB ON-DEMAND CONTROL CODES"

if ! grep -q "$ALIAS_MARKER" "$BASHRC_FILE"; then
    cp -p "$BASHRC_FILE" "$BASHRC_TMP"
    cat << 'EOF' >> "$BASHRC_TMP"

# 🏎️ FEDORA KURULUM USB ON-DEMAND CONTROL CODES
alias usb-ac='sudo /usr/local/bin/usb-ac.sh'
alias usb-kapat='sudo /usr/local/bin/usb-kapat.sh'
EOF
    install -m 644 "$BASHRC_TMP" "$BASHRC_FILE"
    echo "[+] Aegis USB alias yapılandırması .bashrc dosyasına atomik olarak işlendi." >> "$LOG_FILE"
fi

# ==============================================================================
# CATEGORY 03: GNOME MASAÜSTÜ TELEMETRİ VANALARININ ATOMİK ENJEKSİYONU
# ==============================================================================
echo "[*] Aşama 3: GNOME veri toplama havuzları dconf seviyesinde susturuluyor..." | tee -a "$LOG_FILE"

if command -v gsettings &>/dev/null; then
    # Her bir anahtar için ayrı session açıp dconf'u körleştirmek yerine tekil kabuk oturumu mühürlemesi
    sudo -u "$TARGET_USER" dbus-run-session bash -c "
        gsettings set org.gnome.desktop.privacy report-technical-problems false
        gsettings set org.gnome.desktop.privacy send-software-usage-stats false
        gsettings set org.gnome.desktop.privacy location-accuracy-level 'disabled'
    " 2>>"$LOG_FILE"
    echo "[+] GNOME Masaüstü gizlilik ayarları tekil D-Bus atomik subshell oturumuyla çakıldı." >> "$LOG_FILE"
fi

# ==============================================================================
# [SÜREÇ TAMAMLANMA BİLDİRİMİ]
# ==============================================================================
echo "[+] BAŞARILI: LAYER-00 Telemetri Tasfiye Motoru Süreci Kusursuz Tamamladı!" | tee -a "$LOG_FILE"
exit 0
