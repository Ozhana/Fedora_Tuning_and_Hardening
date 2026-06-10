#!/usr/bin/env bash
# ==============================================================================
# PROJE         : FEDORA TUNING AND HARDENING
# KATMAN        : LAYER-01_Core_OS_Hardening
# BETİK         : 01c_selinux_fstab_grub.sh
# AMAÇ          : Çekirdek Seviyesi MAC (SELinux), Akıllı fstab Enjeksiyonu,
#                 \K Token Destekli Deterministik BLS Çekirdek Hardening Motoru
# DONANIM       : Microsoft Surface Pro 9 (Intel Iris Xe)
# REFERANS      : Single-User, Ultra-Paranoid, High-Performance Baseline
# ==============================================================================

set -Eeuo pipefail
export IFS=$'\n\t'
export LC_ALL=C

# ── Anayasal Maskeleme ve Katı İzin Matrisi ──────────────────────────────────
umask 077

# ── Katı PATH Arındırma ve Sıkılaştırma Zinciri ────────────────────────────────
export PATH='/usr/sbin:/usr/bin:/sbin:/bin'
readonly MKDIR_BIN='/usr/bin/mkdir'
readonly CHMOD_BIN='/usr/bin/chmod'
readonly RM_BIN='/usr/bin/rm'
readonly CP_BIN='/usr/bin/cp'
readonly MV_BIN='/usr/bin/mv'
readonly GREP_BIN='/usr/bin/grep'
readonly SED_BIN='/usr/bin/sed'
readonly AWK_BIN='/usr/bin/awk'
readonly FIND_BIN='/usr/bin/find'
readonly XARGS_BIN='/usr/bin/xargs'
readonly STAT_BIN='/usr/bin/stat'
readonly SHA256_BIN='/usr/bin/sha256sum'
readonly PYTHON_BIN='/usr/bin/python3'

# İkili (Binary) Varlık Doğrulama Kalkanı (Paranoid Check)
for binary in "$MKDIR_BIN" "$CHMOD_BIN" "$RM_BIN" "$CP_BIN" "$MV_BIN" "$GREP_BIN" "$SED_BIN" "$AWK_BIN" "$FIND_BIN" "$XARGS_BIN" "$STAT_BIN" "$SHA256_BIN" "$PYTHON_BIN"; do
    if [[ ! -x "$binary" ]]; then
        echo "[-] KRİTİK GÜVENLİK ALARMI: Güvenilir sistem ikilisi eksik veya infaz edilemez: $binary" >&2
        exit 1
    fi
done

# ── Korumalı Sandbox ve Çekirdek Mutex Alanı ──────────────────────────────────
readonly SANDBOX_DIR="/run/lock/layer01c_sandbox"
"$MKDIR_BIN" -p "$SANDBOX_DIR" && "$CHMOD_BIN" 700 "$SANDBOX_DIR"
readonly LOCK_FILE="${SANDBOX_DIR}/01c_core_core.lock"

exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    echo "[-] HATA: Eşzamanlı icra engellendi! Kilit aktiftir: $LOCK_FILE" >&2
    exit 1
fi

# ── Durumsal Kimlik ve Ev Dizini Kanonizasyonu (loginctl & getent tabanlı) ───
get_real_target_user() {
    local active_user
    active_user="${SUDO_USER:-}"
    if [[ -z "$active_user" || "$active_user" == "root" ]]; then
        active_user=$(loginctl list-users --no-legend | "$AWK_BIN" '{print $2}' | "$GREP_BIN" -v "root" | head -1 || echo "")
    fi
    if [[ -z "$active_user" ]]; then
        active_user=$(getent passwd | "$AWK_BIN" -F: '$3 >= 1000 && $3 < 65000 {print $1}' | head -1 || echo "")
    fi
    echo "$active_user"
}

readonly TARGET_USER=$(get_real_target_user)
if [[ -z "$TARGET_USER" ]]; then
    echo "[-] KRİTİK HATA: Sistem üzerinde gerçek insan kullanıcı tespit edilemedi!" >&2
    exit 1
fi

readonly PASSWD_ENTRY=$(getent passwd "$TARGET_USER") || {
    echo "[-] KRİTİK HATA: Hesaba ait yerel veritabanı girdisi bulunamadı!" >&2
    exit 1
}
readonly TARGET_HOME=$(cut -d: -f6 <<< "$PASSWD_ENTRY")
if [[ -z "$TARGET_HOME" || ! -d "$TARGET_HOME" ]]; then
    echo "[-] KRİTİK HATA: Hedef ev dizini geçersiz!" >&2
    exit 1
fi

# Symlink Hijacking Kalkanı ile Loglama Yapılandırması (Kanonik Doğrulama)
readonly LOG_DIR="${TARGET_HOME}/Desktop/LOG_FILES"
readonly TARGET_HOME_REAL=$(realpath "$TARGET_HOME")
readonly LOG_REAL=$(realpath -m "$LOG_DIR")

case "$LOG_REAL" in
    "${TARGET_HOME_REAL}"/*) ;;
    *)
        echo "[-] ADLİ ALARM: Geçersiz log patikası tespiti! Symlink hijacking engellendi." >&2
        exit 1
        ;;
esac

if [[ -L "$LOG_DIR" ]]; then
    echo "[-] ADLİ ALARM: Log dizini bir sembolik bağ (symlink)! Saldırı engellendi." >&2
    exit 1
fi

"$MKDIR_BIN" -p "$LOG_DIR" && "$CHMOD_BIN" 755 "$LOG_DIR"
readonly LOG_FILE="${LOG_DIR}/Layer01c_Core_Hardening.log"
readonly SCRIPT_VERSION="9.0.0"

exec > >(tee -a "$LOG_FILE") 2>&1

# ── Kurumsal Kalıcı Yedekleme ve State Kalkanı ───────────────────────────────
readonly BASE_BACKUP_DIR="/root/backups/hardening/layer01c"
"$MKDIR_BIN" -p "$BASE_BACKUP_DIR" && "$CHMOD_BIN" 700 "$BASE_BACKUP_DIR"
readonly STATE_FILE="${BASE_BACKUP_DIR}/.state.db"

readonly SELINUX_CFG="/etc/selinux/config"
readonly FSTAB="/etc/fstab"

# Surface Pro 9 Optimize Çekirdek Parametreleri
readonly KERNEL_PARAMS=(
    "slab_nomerge"
    "init_on_alloc=1"
    "page_alloc.shuffle=1"
    "pti=on"
    "randomize_kstack_offset=on"
    "kptr_restrict=2"
    "audit_backlog_limit=2048"
    "audit=1"
    "spec_store_bypass_disable=on"
    "spectre_v2=on"
    "l1tf=full"
    "mmio_stale_data=full"
    "retbleed=auto"
    "mitigations=auto"
    "lockdown=integrity"
)

# ── Trap & Cleanup Mekanizması (Özyinelemesiz Çekirdek Koruması) ──────────────
cleanup() {
    local exit_code=$?
    trap - EXIT INT TERM HUP QUIT
    flock -u 9 2>/dev/null || true
    echo "[+] [$(date +'%Y-%m-%d %H:%M:%S')] LAYER-01c Süreci Sonlandı. Çıkış Kodu: $exit_code"
}
trap cleanup EXIT INT TERM HUP QUIT

if [[ ${EUID} -ne 0 ]]; then
    echo "[-] KRİTİK HATA: Askeri düzey mühürleme için root yetkisi şarttır." >&2
    exit 1
fi

# ── Python-Safe POSIX Fsync Güvencesi (Shell Interpolation Engelli) ──────────
execute_posix_fsync() {
    local target_file="$1"
    "$PYTHON_BIN" - "$target_file" <<'PYEOF'
import os
import sys
try:
    fd = os.open(sys.argv[1], os.O_RDONLY)
    os.fsync(fd)
    os.close(fd)
except Exception as e:
    sys.exit(1)
PYEOF
}

# ── Kriptografik Durum ve Konfigürasyon Sapması Doğrulaması (ALL-Entries) ─────
generate_config_signature() {
    (
        cat "$SELINUX_CFG" 2>/dev/null || true
        cat "$FSTAB" 2>/dev/null || true
        if command -v grubby &>/dev/null; then grubby --info=ALL 2>/dev/null || true; fi
        echo "${KERNEL_PARAMS[*]}"
    ) | "$SHA256_BIN" | "$AWK_BIN" '{print $1}'
}

if [[ -f "$STATE_FILE" ]]; then
    readonly SAVED_SIGNATURE=$("$AWK_BIN" '/^signature:/ {print $2}' "$STATE_FILE" 2>/dev/null || true)
    readonly CURRENT_SIGNATURE=$(generate_config_signature)
    if [[ "$SAVED_SIGNATURE" == "$CURRENT_SIGNATURE" ]]; then
        echo "[+] Bilgi: Sistem mevcut imza ile zaten mühürlenmiş. Yapılandırma sapması yok."
        echo "[+] Tekrar çalıştırmak için adli mühür dosyasını silin: rm -f $STATE_FILE"
        exit 0
    fi
fi

echo "======================================================================"
echo "[+] LAYER-01c: MAC, ATOMİK FSTAB REPLACEMENT VE REAL-TIME BLS ENGINE"
echo "======================================================================"

# ── KATEGORİ 01: SELINUX ENFORCING VE ATOMIK METADATA GÜVENCESİ ───────────────
harden_selinux_core() {
    echo "[*] Adım 1: SELinux çekirdek zırhı ve targeted policy yapılandırılıyor..."
    if [[ -f "$SELINUX_CFG" ]]; then
        "$CP_BIN" -a "$SELINUX_CFG" "${BASE_BACKUP_DIR}/selinux_config.bak"
        local selinux_tmp="${SANDBOX_DIR}/selinux.tmp"
        
        "$AWK_BIN" '
        /^SELINUX=/ { $0="SELINUX=enforcing"; s=1 }
        /^SELINUXTYPE=/ { $0="SELINUXTYPE=targeted"; t=1 }
        { print }
        END {
            if(!s) print "SELINUX=enforcing"
            if(!t) print "SELINUXTYPE=targeted"
        }' "$SELINUX_CFG" > "$selinux_tmp"
        
        execute_posix_fsync "$selinux_tmp"
        "$MV_BIN" -f "$selinux_tmp" "$SELINUX_CFG"
        "$CHMOD_BIN" 644 "$SELINUX_CFG"
    fi

    if command -v getenforce &>/dev/null; then
        if [[ "$(getenforce)" == "Permissive" ]]; then
            setenforce 1
            echo "[+] Canlı çekirdek runtime SELinux Enforcing moduna alındı."
        fi
    fi

    if command -v setsebool &>/dev/null; then
        local bools=("selinuxuser_execheap=0" "selinuxuser_execstack=0")
        local bool_set b_name b_val
        for bool_set in "${bools[@]}"; do
            b_name="${bool_set%%=*}"
            b_val="${bool_set##*=}"
            setsebool -P "$b_name" "$b_val" 2>/dev/null || true
        done
    fi
}
harden_selinux_core

# ── KATEGORİ 02: GÜVENLİ VE ATOMİK FSTAB ENJEKSİYONU (FALSE-SUCCESS ENGELLİ) ──
harden_fstab_core() {
    echo "[*] Adım 2: /etc/fstab dosyası bütünlüğü korunarak zırhlandırılıyor..."
    if [[ -f "$FSTAB" ]]; then
        "$CP_BIN" -a "$FSTAB" "${BASE_BACKUP_DIR}/fstab.bak"
        local fstab_tmp="${SANDBOX_DIR}/fstab.tmp"
        local audit_gid fstab_options
        
        # Gid=0 sızıntı riski tamamen engellendi (Grup yoksa defaults'a kilitlenir)
        audit_gid=$(getent group audit | cut -d: -f3 || echo "")
        if [[ -n "$audit_gid" ]]; then
            fstab_options="defaults,nosuid,nodev,noexec,hidepid=2,gid=${audit_gid}"
        else
            fstab_options="defaults,nosuid,nodev,noexec,hidepid=2"
        fi
        
        # AWK yerel scope yapısı ile temiz başlangıç
        "$AWK_BIN" -v opts="$fstab_options" '
        BEGIN { 
            FS=OFS="\t"
            updated=0
        }
        {
            if ($1 ~ /^[[:space:]]*#/ || $1 == "") { print $0; next }
            
            split($0, alanlar, /[ \t]+/)
            fs_spec=alanlar[1]; fs_file=alanlar[2]; fs_type=alanlar[3]; fs_opts=alanlar[4]; fs_dump=alanlar[5]; fs_pass=alanlar[6]
            
            if (fs_file == "/tmp" && fs_type == "tmpfs") {
                if (fs_opts !~ /noexec/) fs_opts=fs_opts ",noexec,nosuid,nodev"
            }
            if (fs_file == "/dev/shm" && fs_type == "tmpfs") {
                if (fs_opts !~ /nosuid/) fs_opts=fs_opts ",nosuid,nodev"
            }
            if (fs_file == "/proc" && fs_type == "proc") {
                fs_opts=opts
                updated=1
            }
            
            print fs_spec, fs_file, fs_type, fs_opts, (fs_dump != "" ? fs_dump : "0"), (fs_pass != "" ? fs_pass : "0")
        }
        END {
            if (updated == 0) {
                print "proc", "/proc", "proc", opts, "0", "0"
            }
        }' "$FSTAB" > "$fstab_tmp"
        
        execute_posix_fsync "$fstab_tmp"
        "$MV_BIN" -f "$fstab_tmp" "$FSTAB"
        "$CHMOD_BIN" 644 "$FSTAB"
    fi
}
harden_fstab_core

# ── KATEGORİ 03: DETERMINISTIK GRUBBY RAM CACHE ENJEKSİYONU ───────────────────
harden_grubby_bls() {
    echo "[*] Adım 3: Modern BLS motoru üzerinden deterministik parametre yönetimi..."
    if command -v grubby &>/dev/null; then
        local current_cmdline p_key existing_val
        
        # 15 kez disk okumayı (throttling) engellemek adına tek seferlik RAM önbelleği
        current_cmdline=$(grubby --info=DEFAULT | "$AWK_BIN" -F= '/^args=/{print substr($0,index($0,"=")+1)}')
        
        for param in "${KERNEL_PARAMS[@]}"; do
            p_key="${param%%=*}"
            
            # Sürüm ve tırnak bağımsız, tam sınır eşleşmesi sağlayan kurumsal \K belirteci
            if echo "$current_cmdline" | "$GREP_BIN" -qP '(?:^|\s)'"$p_key"='[^ ]+'; then
                # Mevcut parametrenin değerini tam sınırlarla süz
                existing_val=$(echo "$current_cmdline" | "$GREP_BIN" -oP '(?:^|\s)'"$p_key"='?\K[^ \t"'\'' ]+' | head -1 || echo "")
                
                if [[ "$existing_val" != "${param##*=}" ]]; then
                    grubby --update-kernel=ALL --remove-args="${p_key}=${existing_val}"
                    grubby --update-kernel=ALL --args="$param"
                    echo "[+] Çekirdek Parametresi Güncellendi: ${p_key} -> ${param##*=}"
                    # Canlı RAM cache satırını asenkron güncelle (Zero-Drift)
                    current_cmdline=$(echo "$current_cmdline" | "$SED_BIN" -E "s/(^|\s)${p_key}=[^ ]*/ /" || echo "")
                    current_cmdline+=" $param"
                fi
            # Word Boundary kalkanı ile alt dize çakışması (audit=10 vs audit=1) imha edildi
            elif ! echo "$current_cmdline" | "$GREP_BIN" -qP '(?:^|\s)'"$param"'(?:\s|$)'; then
                grubby --update-kernel=ALL --args="$param"
                echo "[+] Çekirdek Parametresi Enjekte Edildi: $param"
                current_cmdline+=" $param"
            fi
        done
        
        local grub_defaults="/etc/default/grub"
        if [[ -f "$grub_defaults" ]]; then
            "$SED_BIN" -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=5/' "$grub_defaults"
        fi
    else
        echo "[-] HATA: 'grubby' motoru bulunamadı! BLS mühürleme yapılamadı." >&2
        exit 1
    fi
}
harden_grubby_bls

# ── KATEGORİ 04: CERRAHİ SELINUX CONTEXT RESTORASYONU (MİNİMUM I/O) ───────────
apply_selinux_restoration() {
    echo "[*] Adım 4: Yapılandırılan dosyalar için SELinux etiket zırhı doğrulanıyor..."
    if command -v restorecon &>/dev/null; then
        restorecon -Fv "$SELINUX_CFG" "$FSTAB"
    fi
}
apply_selinux_restoration

# ── NİHAİ MÜHÜRLEME VE İMZA ÇAKILMASI ──────────────────────────────────────────
finalize_state_db() {
    local final_signature
    final_signature=$(generate_config_signature)
    {
        echo "katman: LAYER-01c_FINAL_SECURE"
        echo "mühür_tarihi: $(date +'%Y-%m-%d %H:%M:%S')"
        echo "signature: ${final_signature}"
        echo "durum: SUCCESS"
    } > "$STATE_FILE"
    "$CHMOD_BIN" 400 "$STATE_FILE"
}
finalize_state_db

echo "======================================================================"
echo "[+] LAYER-01c TAMAMLANDI. TÜM PARAMETRELER İÇİN REBOOT GEREKLİDIR!"
echo "======================================================================"
exit 0
