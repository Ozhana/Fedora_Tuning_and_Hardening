#!/usr/bin/env bash
# ==============================================================================
# PROJE         : FEDORA TUNING AND HARDENING
# KATMAN        : LAYER-01_Core_OS_Hardening (AUDIT FORTRESS V4_NİHAÎ)
# BETİK         : 01_layer_final_audit.sh
# AMAÇ          : LAYER-01 (01a, 01b, 01c, 01d) Kusursuz Adli Durum Denetimi
# PRENSİP       : ZERO ASSUMPTION | READ-ONLY | FULL-MATRİX VERIFICATION
# DONANIM       : Microsoft Surface Pro 9 (Intel Core Hybrid Architecture)
# ==============================================================================

set -Eeuo pipefail
export IFS=$'\n\t'
export LC_ALL=C

# Katı PATH Arındırması (Environment Hijacking Savunması)
export PATH='/usr/sbin:/usr/bin:/sbin:/bin'

# Askeri Düzey Yetki Enforce Kontrolü [cite: 3, 39, 122, 172]
if [[ ${EUID} -ne 0 ]]; then
    echo -e "\e[31m[-] KRİTİK ADLİ HATA: Denetim motoru çekirdek ring buffer ve donanım hatlarını okur. 'sudo' şarttır.\e[0m" >&2
    exit 1
fi

# RAM Tabanlı İzole Çalışma Alanı (Sıfır I/O, SSD Write Amplification Engelleme) [cite: 4]
readonly AUDIT_DIR=$(mktemp -d /run/lock/layer01_audit.XXXXXX)
chmod 700 "$AUDIT_DIR"
readonly AUDIT_REPORT="${AUDIT_DIR}/report.md"

cleanup() {
    local exit_code=$?
    trap - EXIT INT TERM HUP QUIT [cite: 5]
    
    # Adli Raporu Kullanıcının Masaüstüne Kanonik Güvenlikle Kopyalama [cite: 43]
    local target_user="${SUDO_USER:-$(logname 2>/dev/null || echo root)}"
    if [[ "$target_user" != "root" ]]; then
        local user_home
        user_home=$(getent passwd "$target_user" | cut -d: -f6 || echo "") [cite: 43]
        if [[ -n "$user_home" && -d "$user_home/Desktop" ]]; then
            cp "$AUDIT_REPORT" "${user_home}/Desktop/LAYER-01_Audit_Report.md" 2>/dev/null || true
        fi
    fi
    rm -rf "$AUDIT_DIR"
    exit "$exit_code"
}
trap cleanup EXIT INT TERM HUP QUIT

# Markdown Rapor Şablonunun Bellekte İnşası
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
    
    # Tam Sınır ve Küme Kapsama Teyidi
    if [[ "$expected" == "$actual" || "$actual" == *"$expected"* ]]; then
        status="\e[32m✅ PASS\e[0m"
    fi
    
    local raw_status="FAIL"
    [[ "$status" == *"PASS"* ]] && raw_status="PASS"
    printf "| %s | %s | %s | %s | %s |\n" "$component" "$metric" "$expected" "$actual" "$raw_status" >> "$AUDIT_REPORT"
    
    printf "  %-15s %-38s [%-22s] -> [%-22s] [%b]\n" "$component" "$metric" "$expected" "$actual" "$status"
}

# ==============================================================================
# MADDE-01: SYSCTL MATRİS DOĞRULAYICI (Eksiksiz Çekirdek Taraması)
# ==============================================================================
audit_sysctl() {
    local key="$1"
    local expected="$2"
    local actual
    actual=$(sysctl -n "$key" 2>/dev/null || echo "EKSİK")
    log_audit "01a_Sysctl" "$key" "$expected" "$actual"
}

# ==============================================================================
# MADDE-02: CHRONY NTS KRİPTOGRAFİK VE REKURSİF PEER DOĞRULAYICI
# ==============================================================================
audit_chrony_core() {
    # Port 0 Sızdırmazlık Kalkanı
    local port_status="AÇIK (RİSK!)"
    if grep -qF "port 0" /etc/chrony.conf 2>/dev/null && grep -qF "cmdport 0" /etc/chrony.conf 2>/dev/null; then 
        port_status="Soketler Kapalı (port 0)"
    fi
    log_audit "01b_Chrony" "Port & Cmdport İzolasyonu" "Soketler Kapalı (port 0)" "$port_status"

    # Kriptografik NTS-KE Çerez Havuzu Doğrulaması [cite: 95]
    local auth_status="NTS ÇEREZ YOK"
    if chronyc -N authdata 2>/dev/null | grep -qE "^[a-zA-Z0-9.-]+[ \t]+NTS[ \t]+[1-9][0-9]*[ \t]+[1-9][0-9]*"; then [cite: 95]
        auth_status="NTS-KE AKTİF"
    fi
    log_audit "01b_Chrony" "NTS Kripto Güvencesi" "NTS-KE AKTİF" "$auth_status"

    # Sistem Zaman Kaynağı Kararlılığı (Stratum / Peer)
    local sync_status="SENKRONİZASYON KOPUK"
    if chronyc -N sources 2>/dev/null | grep -qE "^\^\*"; then
        sync_status="MÜHÜRLÜ SENKRON"
    fi
    log_audit "01b_Chrony" "Canlı Zaman Senkronu" "MÜHÜRLÜ SENKRON" "$sync_status"
}

# ==============================================================================
# MADDE-03: MULTI-KERNEL BLS HASH ÇAPRAZ SORGULAYICI (Shadow State Engeli)
# ==============================================================================
audit_grubby_matrix() {
    local param="$1"
    local disk_state="MÜHÜRLÜ"
    local live_state="EKSİK (RAM)"
    
    # Tüm yüklü çekirdek girdilerinde bu parametre var mı? [cite: 146]
    local cmdline_all
    cmdline_all=$(grubby --info=ALL 2>/dev/null | awk -F= '/^args=/{print substr($0,index($0,"=")+1)}' || echo "") [cite: 146]
    
    if [[ -z "$cmdline_all" ]]; then
        disk_state="BLS OKUNAMADI"
    else
        while IFS= read -r line; do
            if [[ -n "$line" && "$line" != *"$param"* ]]; then
                disk_state="EKSİK (DİSK)"
                break
            fi
        done <<< "$cmdline_all"
    fi
    
    # Canlı çekirdekte durum ne?
    if grep -qF "$param" /proc/cmdline 2>/dev/null; then
        live_state="MÜHÜRLÜ"
    fi
    
    local final_status="TUTARSIZ"
    if [[ "$disk_state" == "MÜHÜRLÜ" && "$live_state" == "MÜHÜRLÜ" ]]; then
        final_status="TAM SENKRON"
    elif [[ "$disk_state" == "MÜHÜRLÜ" && "$live_state" == "EKSİK (RAM)" ]]; then
        final_status="REBOOT GEREKLİ"
    elif [[ "$disk_state" == "EKSİK (DİSK)" && "$live_state" == "MÜHÜRLÜ" ]]; then
        final_status="HAYALET DURUM (Geçici)"
    fi
    
    log_audit "01c_01d_BLS" "$param" "TAM SENKRON" "$final_status"
}

# ==============================================================================
# MADDE-04: SANAL DOSYA SİSTEMİ (VFS) TAM MASKE DOĞRULAYICI
# ==============================================================================
audit_vfs_mount() {
    local mount_point="$1"
    local expected_flags="$2" # Virgülle ayrılmış çoklu flag örn: "nosuid,nodev,noexec" [cite: 142]
    local actual_opts
    actual_opts=$(findmnt -n -o OPTIONS "$mount_point" 2>/dev/null || echo "MOUNT_YOK")
    
    if [[ "$actual_opts" == "MOUNT_YOK" ]]; then
        log_audit "01c_VFS" "$mount_point" "$expected_flags" "MOUNT YOK"
        return
    fi

    # hidepid polimorfizm süzgeci
    if [[ "$expected_flags" == *"hidepid"* ]]; then
        if echo "$actual_opts" | grep -qE "hidepid=(2|invisible)"; then
            log_audit "01c_VFS" "$mount_point (hidepid)" "MÜHÜRLÜ" "MÜHÜRLÜ"
        else
            log_audit "01c_VFS" "$mount_point (hidepid)" "MÜHÜRLÜ" "EKSİK"
        fi
        return
    fi

    # Çoklu flag matrisinin parçalanarak tek tek canlı runtime'da aranması
    local missing_flag=0
    IFS=',' read -ra flags_array <<< "$expected_flags"
    for flag in "${flags_array[@]}"; do
        if [[ "$actual_opts" != *"$flag"* ]]; then
            missing_flag=1
            break
        fi
    done
    
    local final_state="MÜHÜRLÜ"
    [[ $missing_flag -eq 1 ]] && final_state="GÜVENLİK EKSİĞİ: $actual_opts"
    
    log_audit "01c_VFS" "$mount_point ($expected_flags)" "MÜHÜRLÜ" "$final_state"
}

# ==============================================================================
# MADDE-05: MAC (SELINUX) POLİTİKA MATRİS SORGULAYICI
# ==============================================================================
audit_selinux_core() {
    local mode
    mode=$(getenforce 2>/dev/null || echo "YOK")
    log_audit "01c_SELinux" "Enforcement Mode" "Enforcing" "$mode" [cite: 132]
    
    local system_policy
    system_policy=$(sestatus 2>/dev/null | awk -F: '/Loaded policy name/ {print $2}' | xargs || echo "YOK")
    log_audit "01c_SELinux" "Core Policy Type" "targeted" "$system_policy"

    for bool in selinuxuser_execstack selinuxuser_execheap; do [cite: 135]
        local state
        state=$(getsebool "$bool" 2>/dev/null | awk '{print $3}' || echo "YOK") [cite: 135]
        log_audit "01c_SELinux" "$bool Kalkanı" "off" "$state"
    done
}

# ==============================================================================
# MADDE-06: SURFACE PRO ACPI VE HARDWARE SYSFS BAĞLAM DOĞRULAYICI
# ==============================================================================
audit_udev_hardware() {
    local udev_file="/etc/udev/rules.d/99-surface-acpi-seals.rules"
    local rule_status="YOK"
    
    if [[ -f "$udev_file" ]]; then
        if grep -q 'DRIVERS=="thunderbolt"' "$udev_file" && grep -q 'DRIVERS=="xhci_hcd"' "$udev_file"; then [cite: 191]
            rule_status="MÜHÜRLÜ"
        else
            rule_status="EKSİK KURAL"
        fi
    fi
    log_audit "01d_ACPI" "Udev Rule Yapılandırması" "MÜHÜRLÜ" "$rule_status"

    # Canlı Donanım Ağacı Sızdırmazlık Analizi (Fiziksel Port Süzgeci)
    local pci_tbolt
    pci_tbolt=$(lspci 2>/dev/null | grep -i "thunderbolt" || echo "")
    
    if [[ -n "$pci_tbolt" ]]; then
        local live_wakeup="DISABLED"
        local hosts=$(find /sys/bus/pci/drivers/thunderbolt/ -maxdepth 1 -type l 2>/dev/null || true)
        
        if [[ -n "$hosts" ]]; then
            for host in $hosts; do
                if [[ -f "${host}/power/wakeup" ]]; then
                    local w_state
                    w_state=$(cat "${host}/power/wakeup" 2>/dev/null)
                    if [[ "$w_state" == "enabled" ]]; then
                        live_wakeup="ENABLED (ZAFİYET!)"
                        break
                    fi
                fi
            done
        else
            # Cihaz takılı değilse udev'in atadığı default kernel durumunu sysfs pci aygıtından sorgula
            if find /sys/bus/pci/devices/ -maxdepth 2 -name "wakeup" 2>/dev/null | xargs cat 2>/dev/null | grep -q "enabled"; then
                # Genel taramada xhci veya tbolt kontrolcülerinden biri sızdırıyor mu?
                live_wakeup="HAFİF SIZINTI OLABİLİR"
            fi
        fi
        log_audit "01d_ACPI" "Canlı Donanım Port Wake Güvencesi" "DISABLED" "$live_wakeup"
    else
        log_audit "01d_ACPI" "Canlı Donanım Port Wake Güvencesi" "DISABLED" "DONANIM PASİF/GÜVENLİ"
    fi
}

# ==============================================================================
# ANA İCRA DÖNGÜSÜ (FULL-MATRIX EXECUTION)
# ==============================================================================
echo "=========================================================================="
echo "🛡️ AEGIS LAYER-01: ADLİ GÜVENLİK VE DURUM DOĞRULAMA SİSTEMİ (V4_NİHAÎ)"
echo "=========================================================================="

echo -e "\n[*] [Katman 01a] Çekirdek Güvenlik ve Asimetrik Ağ Matrisi Denetleniyor..."
# 01a Betiğindeki Tüm Parametre Matrisi (Kör Noktasız)
audit_sysctl "kernel.kptr_restrict" "2" [cite: 11]
audit_sysctl "kernel.sysrq" "0" [cite: 11]
audit_sysctl "kernel.unprivileged_bpf_disabled" "1" [cite: 11]
audit_sysctl "kernel.yama.ptrace_scope" "1" [cite: 11]
audit_sysctl "net.core.bpf_jit_harden" "2" [cite: 11]
audit_sysctl "fs.protected_fifos" "2" [cite: 11]
audit_sysctl "fs.protected_regular" "2" [cite: 11]
audit_sysctl "fs.protected_hardlinks" "1" [cite: 11]
audit_sysctl "fs.protected_symlinks" "1" [cite: 11]
audit_sysctl "fs.suid_dumpable" "0" [cite: 11]
audit_sysctl "net.core.default_qdisc" "fq" [cite: 11]
audit_sysctl "net.ipv4.tcp_congestion_control" "bbr" [cite: 11]
audit_sysctl "net.ipv4.conf.all.rp_filter" "1" [cite: 11]
audit_sysctl "net.ipv4.conf.default.rp_filter" "1" [cite: 11]
audit_sysctl "net.ipv4.conf.all.accept_redirects" "0" [cite: 11]
audit_sysctl "net.ipv4.conf.default.accept_redirects" "0" [cite: 11]
audit_sysctl "net.ipv4.conf.all.send_redirects" "0" [cite: 11]
audit_sysctl "net.ipv4.conf.default.send_redirects" "0" [cite: 11]
audit_sysctl "net.ipv4.tcp_syncookies" "1" [cite: 11]
audit_sysctl "net.ipv4.tcp_rfc1337" "1" [cite: 11]
audit_sysctl "net.ipv4.ip_forward" "1" [cite: 11]
audit_sysctl "fs.inotify.max_user_watches" "524288" [cite: 11]
audit_sysctl "net.core.somaxconn" "32768" [cite: 11]
audit_sysctl "net.ipv6.conf.all.disable_ipv6" "1" [cite: 11]
audit_sysctl "net.ipv6.conf.default.disable_ipv6" "1" [cite: 11]
audit_sysctl "vm.dirty_background_ratio" "2" [cite: 11]
audit_sysctl "vm.dirty_ratio" "10" [cite: 11]

echo -e "\n[*] [Katman 01b] Kriptografik Zaman Zaman Kafesi ve Çatışma Kalkanı..."
audit_chrony_core
log_audit "01b_Systemd" "systemd-timesyncd Çatışma" "disabled" "$(systemctl is-enabled systemd-timesyncd.service 2>/dev/null || echo "disabled")" [cite: 87]
log_audit "01b_Systemd" "systemd-time-wait-sync" "enabled" "$(systemctl is-enabled systemd-time-wait-sync.service 2>/dev/null || echo "disabled")" [cite: 99]

echo -e "\n[*] [Katman 01c] MAC Güvencesi, VFS Blok Mühürleri ve İzolasyon Matrixi..."
audit_selinux_core
audit_grubby_matrix "init_on_alloc=1" [cite: 118]
audit_grubby_matrix "lockdown=integrity" [cite: 119]
audit_grubby_matrix "audit_backlog_limit=2048" [cite: 118]
audit_grubby_matrix "pti=on" [cite: 118]
audit_grubby_matrix "page_alloc.shuffle=1" [cite: 118]
audit_grubby_matrix "slab_nomerge" [cite: 118]
audit_grubby_matrix "randomize_kstack_offset=on" [cite: 118]

# VFS Tam Maske Kontrolleri 
audit_vfs_mount "/tmp" "nosuid,nodev,noexec" [cite: 142]
audit_vfs_mount "/dev/shm" "nosuid,nodev" [cite: 143]
audit_vfs_mount "/proc" "hidepid"

echo -e "\n[*] [Katman 01d] Surface Pro 9 ACPI Donanım Hatları ve Intel Mesh Enerji..."
audit_udev_hardware
audit_grubby_matrix "pcie_aspm=default" [cite: 185]
audit_grubby_matrix "i915.enable_psr=2" [cite: 185]
log_audit "01d_Power" "power-profiles-daemon" "active" "$(systemctl is-active power-profiles-daemon 2>/dev/null || echo "inactive")" [cite: 194]

# Firewalld Hayalet Kalkan Teşhisi [cite: 30]
local fw_state="PASİF"
if systemctl is-active --quiet firewalld 2>/dev/null; then [cite: 31]
    if firewall-cmd --permanent --query-rich-rule='rule protocol value="icmp" drop' >/dev/null 2>&1; then [cite: 32]
        fw_state="MÜHÜRLÜ (ICMP DROP)"
    else
        fw_state="KURAL EKSİK"
    fi
fi
log_audit "01a_Network" "Firewalld Asimetrik Kalkan" "MÜHÜRLÜ (ICMP DROP)" "$fw_state"

echo -e "\n=========================================================================="
echo "🛡️ ADLİ DOĞRULAMA RAPORU TAMAMLANDI"
echo "=========================================================================="
exit 0
