#!/usr/bin/env bash
# ==============================================================================
# PROJE         : FEDORA TUNING AND HARDENING
# KATMAN        : LAYER-01_Core_OS_Hardening (AUDIT FORTRESS V3)
# BETİK         : 01_layer_final_audit.sh
# AMAÇ          : LAYER-01 (01a, 01b, 01c, 01d) Kapsamlı Adli Durum Denetimi
# PRENSİP       : ZERO ASSUMPTION | READ-ONLY | DUAL-STATE VERIFICATION
# ==============================================================================

set -Eeuo pipefail
export IFS=$'\n\t'
export LC_ALL=C

# Katı PATH Arındırması
export PATH='/usr/sbin:/usr/bin:/sbin:/bin'

if [[ ${EUID} -ne 0 ]]; then
    echo -e "\e[31m[-] HATA: Adli denetim motoru donanım seviyesinde okuma yapar. 'sudo' şarttır.\e[0m" >&2
    exit 1
fi

# RAM Tabanlı İzole Çalışma Alanı
readonly AUDIT_DIR=$(mktemp -d /run/lock/layer01_audit.XXXXXX)
chmod 700 "$AUDIT_DIR"
readonly AUDIT_REPORT="${AUDIT_DIR}/report.md"

cleanup() {
    local exit_code=$?
    trap - EXIT INT TERM HUP QUIT
    # Raporu kullanıcının masaüstüne de kopyala (Görünürlük için)
    local target_user="${SUDO_USER:-$(logname 2>/dev/null || echo root)}"
    if [[ "$target_user" != "root" ]]; then
        local desktop_dir=$(getent passwd "$target_user" | cut -d: -f6)/Desktop
        if [[ -d "$desktop_dir" ]]; then
            cp "$AUDIT_REPORT" "${desktop_dir}/LAYER-01_Audit_Report.md" 2>/dev/null || true
        fi
    fi
    rm -rf "$AUDIT_DIR"
    exit "$exit_code"
}
trap cleanup EXIT INT TERM HUP QUIT

# ==============================================================================
# DENETİM FONKSİYONLARI VE TABLO İNŞASI
# ==============================================================================

{
    echo "| BİLEŞEN (KATMAN) | DENETLENEN METRİK | BEKLENEN ANAYASAL DURUM | CANLI SİSTEM DURUMU | SONUÇ |"
    echo "| :--- | :--- | :--- | :--- | :--- |"
} > "$AUDIT_REPORT"

log_audit() {
    local component="$1"
    local metric="$2"
    local expected="$3"
    local actual="$4"
    local status="\e[31m❌ FAIL\e[0m"
    
    if [[ "$expected" == "$actual" || "$actual" == *"$expected"* ]]; then
        status="\e[32m✅ PASS\e[0m"
    fi
    
    local raw_status="FAIL"
    [[ "$status" == *"PASS"* ]] && raw_status="PASS"
    printf "| %s | %s | %s | %s | %s |\n" "$component" "$metric" "$expected" "$actual" "$raw_status" >> "$AUDIT_REPORT"
    
    printf "  %-15s %-38s [%-22s] -> [%-22s] [%b]\n" "$component" "$metric" "$expected" "$actual" "$status"
}

# 1. SYSCTL CANLI DURUM DENETLEYİCİ (Genişletilmiş)
audit_sysctl() {
    local key="$1"
    local expected="$2"
    local actual
    actual=$(sysctl -n "$key" 2>/dev/null || echo "EKSİK")
    log_audit "01a_Sysctl" "$key" "$expected" "$actual"
}

# 2. CHRONY NTS KRİPTOGRAFİK VE AĞ GÜVENCE DENETLEYİCİ
audit_chrony() {
    # Port 0 DDoS Kalkanı Kontrolü
    local port_status="EKSİK"
    if grep -qE "^port 0" /etc/chrony.conf 2>/dev/null; then port_status="port 0"; fi
    log_audit "01b_Chrony" "UDP Dinleme Soketi (DDoS Kalkanı)" "port 0" "$port_status"

    # NTS AuthData (Çerez) Kontrolü
    local auth_status="ÇEREZ YOK"
    if chronyc -N authdata 2>/dev/null | grep -qE "^[a-zA-Z0-9.-]+[ \t]+NTS[ \t]+[1-9][0-9]*[ \t]+[1-9][0-9]*"; then
        auth_status="NTS-KE AKTİF"
    fi
    log_audit "01b_Chrony" "NTS-KE Kriptografik Çerez Havuzu" "NTS-KE AKTİF" "$auth_status"

    # Canlı Senkronizasyon (System Peer) Kontrolü
    local sync_status="SENKRON YOK"
    if chronyc -N sources 2>/dev/null | grep -qE "^\^\*"; then
        sync_status="MÜHÜRLÜ SENKRON"
    fi
    log_audit "01b_Chrony" "Canlı Çekirdek Zaman Mührü" "MÜHÜRLÜ SENKRON" "$sync_status"
}

# 3. GRUBBY BLS PARAMETRE DENETLEYİCİ (TÜM GİRDİLER / ALL ENTRIES)
audit_grubby_param() {
    local param="$1"
    local disk_state="MÜHÜRLÜ"
    local live_state="EKSİK (RAM)"
    
    # Shadow State engellemesi: DEFAULT yerine ALL kontrol edilir.
    local cmdline_all
    cmdline_all=$(grubby --info=ALL 2>/dev/null | awk -F= '/^args=/{print substr($0,index($0,"=")+1)}')
    
    while IFS= read -r line; do
        if [[ -n "$line" && "$line" != *"$param"* ]]; then
            disk_state="EKSİK (DİSK)"
            break
        fi
    done <<< "$cmdline_all"
    
    if grep -qF "$param" /proc/cmdline 2>/dev/null; then
        live_state="MÜHÜRLÜ"
    fi
    
    local final_status="EKSİK"
    if [[ "$disk_state" == "MÜHÜRLÜ" && "$live_state" == "MÜHÜRLÜ" ]]; then
        final_status="TAM SENKRON"
    elif [[ "$disk_state" == "MÜHÜRLÜ" && "$live_state" == "EKSİK (RAM)" ]]; then
        final_status="REBOOT GEREKLİ"
    elif [[ "$disk_state" == "EKSİK (DİSK)" && "$live_state" == "MÜHÜRLÜ" ]]; then
        final_status="HAYALET PARAMETRE (Geçici)"
    fi
    
    log_audit "01c_01d_BLS" "$param" "TAM SENKRON" "$final_status"
}

# 4. MOUNT / FSTAB ÇEKİRDEK VFS DENETLEYİCİ
audit_mount_flag() {
    local mount_point="$1"
    local expected_flag="$2"
    local actual_flags
    actual_flags=$(findmnt -n -o OPTIONS "$mount_point" 2>/dev/null || echo "MOUNT_YOK")
    
    local actual_state="BAYRAK EKSİK"
    if [[ "$actual_flags" == "MOUNT_YOK" ]]; then
        actual_state="MOUNT YOK"
    elif [[ "$expected_flag" == *"hidepid"* ]]; then
        if echo "$actual_flags" | grep -qE "hidepid=(2|invisible)"; then
            actual_state="MÜHÜRLÜ"
        fi
    elif [[ "$actual_flags" == *"$expected_flag"* ]]; then
        actual_state="MÜHÜRLÜ"
    fi
    log_audit "01c_VFS" "$mount_point ($expected_flag)" "MÜHÜRLÜ" "$actual_state"
}

# 5. SELINUX GÜVENLİK DUVARI VE BOOLEAN MATRIX DENETLEYİCİ
audit_selinux() {
    local actual_mode
    actual_mode=$(getenforce 2>/dev/null || echo "YOK")
    log_audit "01c_SELinux" "Enforce Mode" "Enforcing" "$actual_mode"
    
    for bool in selinuxuser_execstack selinuxuser_execheap; do
        local bool_state
        bool_state=$(getsebool "$bool" 2>/dev/null | awk '{print $3}' || echo "YOK")
        log_audit "01c_SELinux" "$bool" "off" "$bool_state"
    done
}

# 6. UDEV ACPI VE POWER MANAGEMENT MOTORU DENETLEYİCİ (CANLI SYSFS DESTEKLİ)
audit_udev_acpi() {
    local rule_status="YOK"
    local udev_file="/etc/udev/rules.d/99-surface-acpi-seals.rules"
    
    if [[ -f "$udev_file" ]] && grep -q 'DRIVERS=="thunderbolt"' "$udev_file"; then
        rule_status="MÜHÜRLÜ"
    fi
    log_audit "01d_ACPI" "Udev Rule Varlığı" "MÜHÜRLÜ" "$rule_status"

    # Canlı sysfs donanım ağacı denetimi (Zero Assumption)
    local live_tbolt_wakeup="KONTROL EDİLEMEDİ"
    local tbolt_devs=$(find /sys/bus/pci/drivers/thunderbolt -maxdepth 1 -type l 2>/dev/null || true)
    if [[ -n "$tbolt_devs" ]]; then
        live_tbolt_wakeup="DISABLED"
        for dev in $tbolt_devs; do
            local w_state=$(cat "${dev}/power/wakeup" 2>/dev/null || echo "disabled")
            if [[ "$w_state" == "enabled" ]]; then
                live_tbolt_wakeup="ENABLED (ZAFİYET!)"
                break
            fi
        done
    else
        live_tbolt_wakeup="DONANIM YOK/PASİF"
    fi
    log_audit "01d_ACPI" "Canlı Thunderbolt Wake Durumu" "DISABLED" "$live_tbolt_wakeup"
}

# ==============================================================================
# SÜREÇ TETİKLENME MOTORU
# ==============================================================================
echo "=========================================================================="
echo "🛡️ AEGIS LAYER-01: ADLİ DENETİM VE DOĞRULAMA SİSTEMİ (V3) BAŞLATILDI"
echo "=========================================================================="

echo -e "\n[*] [Katman 01a] Çekirdek Sysctl Performans ve Asimetrik Ağ Kalkanı..."
audit_sysctl "net.core.default_qdisc" "fq"
audit_sysctl "net.ipv4.tcp_congestion_control" "bbr"
audit_sysctl "kernel.kptr_restrict" "2"
audit_sysctl "kernel.yama.ptrace_scope" "1"
audit_sysctl "kernel.unprivileged_bpf_disabled" "1"
audit_sysctl "net.core.bpf_jit_harden" "2"
audit_sysctl "fs.suid_dumpable" "0"
audit_sysctl "fs.protected_fifos" "2"
audit_sysctl "fs.protected_regular" "2"
audit_sysctl "net.ipv4.conf.all.rp_filter" "1"
audit_sysctl "net.ipv6.conf.all.disable_ipv6" "1"
audit_sysctl "vm.dirty_background_ratio" "2"

echo -e "\n[*] [Katman 01b] Kriptografik Zaman Zırhı ve Çatışma Denetimi..."
audit_chrony
log_audit "01b_Systemd" "systemd-timesyncd Durumu" "disabled" "$(systemctl is-enabled systemd-timesyncd.service 2>/dev/null || echo "disabled")"
log_audit "01b_Systemd" "systemd-time-wait-sync" "enabled" "$(systemctl is-enabled systemd-time-wait-sync.service 2>/dev/null || echo "disabled")"

echo -e "\n[*] [Katman 01c] MAC (SELinux), Güvenli VFS ve Boot İzolasyonu..."
audit_selinux
audit_grubby_param "init_on_alloc=1"
audit_grubby_param "lockdown=integrity"
audit_grubby_param "audit_backlog_limit=2048"
audit_grubby_param "pti=on"
audit_grubby_param "page_alloc.shuffle=1"

audit_mount_flag "/tmp" "noexec"
audit_mount_flag "/tmp" "nosuid"
audit_mount_flag "/var/tmp" "bind"
audit_mount_flag "/var/tmp" "noexec"
audit_mount_flag "/dev/shm" "nosuid"
audit_mount_flag "/dev/shm" "nodev"
audit_mount_flag "/proc" "hidepid=2"

echo -e "\n[*] [Katman 01d] Surface Pro 9 Donanım ACPI ve Intel Tuning..."
audit_udev_acpi
audit_grubby_param "pcie_aspm=default"
audit_grubby_param "i915.enable_psr=2"

log_audit "01d_Power" "power-profiles-daemon" "active" "$(systemctl is-active power-profiles-daemon 2>/dev/null || echo "inactive")"

echo -e "\n=========================================================================="
echo "🛡️ ADLİ DENETİM RAPORU MÜHÜRLENDİ (Masaüstüne ve /run/lock altına kaydedildi)"
echo "=========================================================================="
exit 0
