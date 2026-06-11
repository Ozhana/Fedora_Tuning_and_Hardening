#!/usr/bin/env bash
# ==============================================================================
# PROJE         : FEDORA TUNING AND HARDENING
# KATMAN        : AUDIT ENGINE V4 (LAYER-00 Mutlak Denetimi)
# AMAÇ          : Sistem bütünlüğünü (Debloat, Ağ, USB, GNOME, Kurulumlar) 
#                 salt-okunur olarak çift durumlu (dual-state) denetler.
# ==============================================================================

set -Eeuo pipefail
export IFS=$'\n\t'
export LC_ALL=C
export PATH='/usr/sbin:/usr/bin:/sbin:/bin'

# ── ROOT YETKİSİ VE GÜVENLİ ÇALIŞMA ALANI ───────────────────────────────────

if [[ "${EUID}" -ne 0 ]]; then
    echo "[-] KRİTİK HATA: Bu denetim motoru root yetkisi gerektirir." >&2
    exit 1
fi

readonly SECURE_TMP=$(mktemp -d /run/lock/layer00_audit_v4.XXXXXX)
chmod 700 "$SECURE_TMP"

cleanup() {
    trap - EXIT INT TERM HUP QUIT
    rm -rf "$SECURE_TMP"
}
trap cleanup EXIT INT TERM HUP QUIT

# ── HEDEF KULLANICI TESPİTİ (00c İle Birebir Uyumlu) ────────────────────────

readonly TARGET_USER="${SUDO_USER:-$(logname 2>/dev/null || id -nu 1000)}"
readonly TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6 || echo "")

# ── TABLO MOTORU HAZIRLIĞI ──────────────────────────────────────────────────

readonly REPORT_FILE="${SECURE_TMP}/audit_report.md"

echo "| Kategori | Denetim Noktası | Olması Gereken | Şu Anki Durum | Durum |" > "$REPORT_FILE"
echo "| :--- | :--- | :--- | :--- | :--- |" >> "$REPORT_FILE"

append_result() {
    local category="$1"
    local check_name="$2"
    local expected="$3"
    local actual="$4"
    local custom_status="${5:-}"
    local status="❌ FAIL"
    
    if [[ -n "$custom_status" ]]; then
        status="$custom_status"
    elif [[ "$expected" == "$actual" ]]; then
        status="✅ PASS"
    fi
    
    printf "| %s | %s | %s | %s | %s |\n" "$category" "$check_name" "$expected" "$actual" "$status" >> "$REPORT_FILE"
}

# ── 1. DNF HIZLANDIRMA ──────────────────────────────────────────────────────

check_dnf_param() {
    local param="$1"
    local expected="$2"
    local actual
    actual=$(grep -oP "(?:^|\s)${param}=\K[^ ]+" /etc/dnf/dnf.conf 2>/dev/null || echo "Yok")
    append_result "DNF Config" "$param" "$expected" "$actual"
}

check_dnf_param "fastestmirror" "True"
check_dnf_param "max_parallel_downloads" "10"
check_dnf_param "defaultyes" "True"

# ── 2. GRUBBY BOOT PARAMETRELERİ (TÜM BLS GİRDİLERİ AYRIK) ──────────────────

bls_entries=$(grubby --info=ALL 2>/dev/null | awk -F= '/^args=/{print substr($0,index($0,"=")+1)}')
bls_count=$(echo "$bls_entries" | awk 'NF' | wc -l)
rhgb_count=$(echo "$bls_entries" | grep -cP '(?:^|\s)rhgb(?:\s|$)' || true)
quiet_count=$(echo "$bls_entries" | grep -cP '(?:^|\s)quiet(?:\s|$)' || true)
show_status_count=$(echo "$bls_entries" | grep -cP '(?:^|\s)systemd.show_status=true(?:\s|$)' || true)
loglevel_count=$(echo "$bls_entries" | grep -cP '(?:^|\s)loglevel=3(?:\s|$)' || true)

append_result "GRUB (ALL)" "rhgb" "0 Adet" "${rhgb_count} Adet"
append_result "GRUB (ALL)" "quiet" "0 Adet" "${quiet_count} Adet"
append_result "GRUB (ALL)" "show_status=true" "${bls_count} Adet" "${show_status_count} Adet"
append_result "GRUB (ALL)" "loglevel=3" "${bls_count} Adet" "${loglevel_count} Adet"

# ── 3. TAM DEBLOAT VE MOZILLA İZ KONTROLÜ ───────────────────────────────────

check_package_removed() {
    local pkg="$1"
    local actual="Yok"
    if rpm -q "$pkg" >/dev/null 2>&1; then actual="Kurulu"; fi
    append_result "Debloat" "$pkg" "Yok" "$actual"
}

debloat_pkgs=("firefox" "gnome-tour" "yelp" "gnome-connections" "gnome-weather" "gnome-boxes" "httpd" "avahi-daemon" "simple-scan" "totem" "cheese")
for p in "${debloat_pkgs[@]}"; do check_package_removed "$p"; done

# Mozilla Telemetri Dizini Koruması
act_moz="Yok"; [[ -d "$TARGET_HOME/.mozilla" ]] && act_moz="Mevcut"
act_cache="Yok"; [[ -d "$TARGET_HOME/.cache/mozilla" ]] && act_cache="Mevcut"
append_result "Telemetri İzi" "~/.mozilla" "Yok" "$act_moz"
append_result "Telemetri İzi" "~/.cache/mozilla" "Yok" "$act_cache"

# ── 4. KURULUM KONTROLLERİ (MUTLAK KİMLİK DOĞRULAMASI İLE) ──────────────────

check_pkg_installed() {
    local pkg="$1"
    local actual="Yok"
    if rpm -q "$pkg" >/dev/null 2>&1; then actual="Kurulu"; fi
    append_result "Kurulan RPM" "$pkg" "Kurulu" "$actual"
}

check_flatpak_installed() {
    local app_id="$1"
    local actual="Yok"
    # İsim değil, mutlak ID kontrolü
    if command -v flatpak &>/dev/null && flatpak info "$app_id" &>/dev/null; then 
        actual="Kurulu"
    fi
    append_result "Flatpak" "$app_id" "Kurulu" "$actual"
}

check_pkg_installed "rpmfusion-free-release"
check_pkg_installed "rpmfusion-nonfree-release"
check_pkg_installed "intel-media-driver"
check_pkg_installed "libva-utils"
check_pkg_installed "keepassxc"
check_pkg_installed "gnome-tweaks"
check_pkg_installed "btop"
check_pkg_installed "celluloid"
check_pkg_installed "dejavu-sans-mono-fonts"

check_flatpak_installed "com.github.tchx84.Flatseal"
check_flatpak_installed "com.mattjakeman.ExtensionManager"

# ── 5. SERVİS ZIRHI (DUAL-STATE: DISK VE BELLEK DOĞRULAMASI) ────────────────

check_dual_service_state() {
    local svc="$1"
    local exp_enabled="$2"
    local act_enabled
    local act_active
    local actual_str
    local custom_stat="❌ FAIL"
    
    act_enabled=$(systemctl is-enabled "$svc" 2>/dev/null || echo "not-found")
    act_active=$(systemctl is-active "$svc" 2>/dev/null || echo "unknown")
    
    if [[ "$act_enabled" == "not-found" ]]; then
        actual_str="Yok / Yok"
        # Sistemde yoksa ve biz onu zaten disable/mask etmek istiyorsak bu güvendedir.
        if [[ "$exp_enabled" == "masked" || "$exp_enabled" == "disabled" ]]; then
            custom_stat="✅ PASS (Yok)"
        fi
    else
        actual_str="$act_enabled / $act_active"
        if [[ "$act_enabled" == "$exp_enabled" ]]; then
            # RAM'de canlı çalışmamasını garantile
            if [[ "$act_active" != "active" && "$act_active" != "activating" ]]; then
                custom_stat="✅ PASS"
            fi
        fi
    fi
    
    append_result "Servis Zırhı" "$svc" "$exp_enabled / inactive" "$actual_str" "$custom_stat"
}

masked_svcs=("abrtd.service" "abrt-journal-core.service" "abrt-oops.service" "abrt-xorg.service" "avahi-daemon.service" "pcscd.service" "ModemManager.service" "cups.service" "cups.socket" "cups.path" "iscsid.service" "iscsid.socket" "iscsiuio.socket" "multipathd.service" "multipathd.socket" "httpd.service" "geoclue.service" "fedora-third-party-report.service" "abrt-pending.timer")
for s in "${masked_svcs[@]}"; do check_dual_service_state "$s" "masked"; done

disabled_svcs=("NetworkManager-wait-online.service" "sssd.service" "rpcbind.service" "rpcbind.socket" "libvirtd.service" "libvirtd.socket" "virtqemud.service" "virtqemud.socket" "qemu-guest-agent.service" "spice-vdagentd.service")
for s in "${disabled_svcs[@]}"; do check_dual_service_state "$s" "disabled"; done

# ── 6. SYSTEMD SHUTDOWN VE DNF OVERRIDES ────────────────────────────────────

check_file_content() {
    local category="$1"
    local name="$2"
    local file="$3"
    local regex="$4"
    local actual="Yok"
    if [[ -f "$file" ]] && grep -qP "$regex" "$file"; then actual="Mevcut"; fi
    append_result "$category" "$name" "Mevcut" "$actual"
}

check_file_content "Systemd Override" "Fast Shutdown" "/etc/systemd/system.conf.d/99-fast-shutdown.conf" "DefaultTimeoutStopSec=10s"
check_file_content "Systemd Override" "DNF Daemon Timeout" "/etc/systemd/system/dnf5daemon-server.service.d/override.conf" "TimeoutStopSec=10s"
check_file_content "Systemd Override" "DNF Makecache Timeout" "/etc/systemd/system/dnf-makecache.service.d/override.conf" "TimeoutStopSec=10s"

# ── 7. USB KALKANI VE KOMUT DOSYALARI ───────────────────────────────────────

act_usb_storage=$(grep -cP "^blacklist usb-storage" /etc/modprobe.d/block-usb-storage.conf 2>/dev/null || echo "0")
act_uas=$(grep -cP "^blacklist uas" /etc/modprobe.d/block-usb-storage.conf 2>/dev/null || echo "0")
append_result "USB Blacklist" "usb-storage" "1" "$act_usb_storage"
append_result "USB Blacklist" "uas" "1" "$act_uas"

act_usb_ac="Yok"; [[ -x "/usr/local/bin/usb-ac.sh" ]] && act_usb_ac="Mevcut"
act_usb_kapat="Yok"; [[ -x "/usr/local/bin/usb-kapat.sh" ]] && act_usb_kapat="Mevcut"
append_result "USB Executable" "usb-ac.sh" "Mevcut" "$act_usb_ac"
append_result "USB Executable" "usb-kapat.sh" "Mevcut" "$act_usb_kapat"

act_alias_ac=$(grep -cP "alias usb-ac=" "${TARGET_HOME}/.bashrc" 2>/dev/null || echo "0")
act_alias_kapat=$(grep -cP "alias usb-kapat=" "${TARGET_HOME}/.bashrc" 2>/dev/null || echo "0")
append_result "Bashrc Alias" "usb-ac" "1" "$act_alias_ac"
append_result "Bashrc Alias" "usb-kapat" "1" "$act_alias_kapat"

# ── 8. GNOME TELEMETRİ VANALARI ─────────────────────────────────────────────

check_gnome_dconf() {
    local key="$1"
    local expected="$2"
    local actual="D-Bus Kapalı/Hata"
    
    if actual_output=$(sudo -u "$TARGET_USER" dbus-run-session gsettings get org.gnome.desktop.privacy "$key" 2>/dev/null); then
        actual="$actual_output"
    fi
    append_result "GNOME Telemetri" "$key" "$expected" "$actual"
}

if [[ -n "$TARGET_USER" ]]; then
    check_gnome_dconf "report-technical-problems" "false"
    check_gnome_dconf "send-software-usage-stats" "false"
    check_gnome_dconf "location-accuracy-level" "'disabled'"
else
    append_result "GNOME Telemetri" "Kullanıcı" "Mevcut" "Bulunamadı" "❌ FAIL"
fi

# ── ÇIKTIYI TERMİNALE BASMA ─────────────────────────────────────────────────

echo -e "\n======================================================================"
echo -e "🛡️ LAYER-00 KESİN VE MUTLAK ADLİ DENETİM RAPORU (V4)"
echo -e "======================================================================\n"
cat "$REPORT_FILE" | column -t -s '|' 2>/dev/null || cat "$REPORT_FILE"
echo -e "\n======================================================================"
echo -e "[+] LAYER-00 Denetimi tamamlandı. İşletim sistemi RAM ve Disk matrisleri eşzamanlı tarandı."
echo -e "======================================================================\n"
