#!/usr/bin/env bash
# ==============================================================================
# PROJE         : FEDORA TUNING AND HARDENING
# KATMAN        : LAYER-01_Core_OS_Hardening
# BETİK         : 01a_kernel_sysctl_tcp_bbr.sh
# AMAC          : Kernel Hardening, TCP BBR, Docker Ön Hazırlık & I/O Optimizasyonu
# DONANIM       : Microsoft Surface Pro 9 (Intel Iris Xe / AX211 Wi-Fi 6E)
# PHILOSOPHY    : ZERO ASSUMPTION | PURE STATE CHECKING | TRUE ATOMIC RENAME
# ==============================================================================

# KATI SÖZ DİZİMİ VE HATA YÖNETİMİ (Anayasa Madde 1)
set -Eeuo pipefail
export IFS=$'\n\t'
export LC_ALL=C

# ROOT YETKİSİ ENFORCEMENT
if [[ "${EUID}" -ne 0 ]]; then
    echo -e "\e[31m[X] KRİTİK HATA: Bu motor askeri düzeyde imtiyaz gerektirir. 'sudo' ile çalıştırın.\e[0m" >&2
    exit 1
fi

# KERNEL SEVİYESİNDE ATOMİK MUTEX LOCK (TOCTOU & ÇİFTE ÇALIŞMA ENGELLEME)
readonly LOCK_FILE="/run/lock/layer01a_kernel_hardened.lock"
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    echo -e "\e[31m[X] KRİTİK HATA: Paralel süreç algılandı! Eşzamanlı icra engellendi.\e[0m" >&2
    exit 1
fi

# FHS UYUMLU KORUMALI ADLİ LOG DIZINI YAPILANDIRMASI
readonly LOG_DIR="/var/log/fedora-hardening"
mkdir -p "${LOG_DIR}"
chmod 700 "${LOG_DIR}"
readonly LOG_FILE="${LOG_DIR}/Layer01_Kernel_Sysctl_BBR.log"

# ATOMİK VE RASTGELE GEÇİCİ ÇALIŞMA ALANI (MKTEMP -D TMPFS ENTEGRASYONU)
readonly SECURE_TMP=$(mktemp -d /run/lock/layer01a_XXXXXX)
chmod 700 "${SECURE_TMP}"

# RECURSION ENGELLENMİŞ TRAP & DETERMINISTIC CLEANUP MİMARİSİ
cleanup() {
    local exit_code=$?
    trap - EXIT INT TERM HUP QUIT
    rm -rf "${SECURE_TMP}"
    flock -u 9 2>/dev/null || true
    { echo "[*] [$(date +'%Y-%m-%d %H:%M:%S')] LAYER-01a Çıkış Kodu: ${exit_code}"; } >> "${LOG_FILE}" 2>/dev/null || \
    echo "[!] Adli günlük kilitlendi, kmsg hattına sevk ediliyor..." >/dev/kmsg 2>/dev/null || true
}
trap cleanup EXIT INT TERM HUP QUIT

# ÇIKTILARI LOG DOSYASINA VE TERMINALE GÜVENLİ YÖNLENDİRME (SINGLE PIPELINE)
exec > >(tee -a "${LOG_FILE}") 2>&1

echo "======================================================================"
echo "[+] LAYER-01a: ÇEKİRDEK GÜVENLİK VE PERFORMANS MOTORU TETİKLENDİ"
echo "======================================================================"

readonly SYSCTL_TARGET="/etc/sysctl.d/99-hardened.conf"
readonly SYSCTL_TMP_FILE="${SECURE_TMP}/99-hardened.conf.tmp"

# SURFACE PRO 9 DONANIMSAL WI-FI INTERFACE DOĞRULAMASI (ZERO ASSUMPTION)
readonly PHYSICAL_NIC=$(iw dev 2>/dev/null | awk '/interface/ {print $2}' | head -n 1 || echo "")

# ÇEKİRDEK MODÜL DESTEK DOĞRULAMASI (BBR ENJEKSİYONU)
readonly AVAILABLE_CC=$(cat /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null || echo "")
if ! grep -qw "bbr" <<< "${AVAILABLE_CC}"; then
    echo "[*] 'bbr' modülü çekirdeğe çağrılıyor..."
    if ! modprobe tcp_bbr 2>/dev/null; then
        echo "[X] KRİTİK HATA: Çekirdek 'bbr' modülünü desteklemiyor veya yükleyemedi." >&2
        exit 1
    fi
fi

# ATOMİK SYSCTL MATRİS İNŞASI (DOCKER VE FUTURE eBPF KOORDİNATLI)
cat << 'EOF' > "${SYSCTL_TMP_FILE}"
# ==============================================================================
# V18_AEGIS: ASKERİ DÜZEY ÇEKİRDEK GÜVENLİĞİ VE ASİMETRİK AĞ KALKANI
# ==============================================================================

# 1. BELLEK İÇİ ZARARLI KOD İCRASI VE MEMORY HIJACKING ENGELLEME
kernel.kptr_restrict = 2
kernel.sysrq = 0
kernel.unprivileged_bpf_disabled = 1
kernel.yama.ptrace_scope = 1
net.core.bpf_jit_harden = 2

# MİMARİ UYUM NOTU (FALCO / TETRAGON / CILIUM ENTEGRASYONU):
# Host üzerinde doğrudan root veya yüksek yetenek setleriyle (CAP_SYS_ADMIN, CAP_BPF) 
# ayağa kalkacak olan siber denetim ajanları, bu katı eBPF JIT kalkanlarına takılmadan 
# kernel ring buffer'ı güvenle dinleyebilir. Katmanlar arası çatışma sıfırlanmıştır.

# 2. DOSYA SİSTEMİ MÜHÜRLERİ VE LYNIS 80+ ENFORCEMENT
fs.protected_fifos = 2
fs.protected_regular = 2
fs.protected_hardlinks = 1
fs.protected_symlinks = 1
fs.suid_dumpable = 0

# 3. TCP BBR VE WI-FI 6E BUFFERBLOAT İNHİBİSYONU
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# 4. ASİMETRİK DDOS, SYN FLOOD VE MAN-IN-THE-MIDDLE SAVUNMASI
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_syn_retries = 5
net.ipv4.tcp_rfc1337 = 1

# 5. DOCKER ARKA PLAN ALTYAPI HAZIRLIK VE UYUM MATRİSİ
net.ipv4.ip_forward = 1

# 6. DOCKER PERFORMANS VE KAYNAK HARDENING LİMİTLERİ (HIGH-THROUGHPUT)
fs.inotify.max_user_watches = 524288
net.core.somaxconn = 32768

# 7. IPV6 VERİ SIZINTISI VE PROTOKOL MÜHÜRLEME
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0

# 8. SURFACE PRO 9 DISK ISI İNHİBİSYONU VE DOCKER ASENKRON I/O OPTİMİZASYONU
vm.dirty_background_ratio = 2
vm.dirty_ratio = 10
EOF

# Dinamik Wi-Fi Koruma Hatlarını Matrise Ekleme (WAF Dostu Seçici Loglama)
if [[ -n "${PHYSICAL_NIC}" ]]; then
    echo "net.ipv4.conf.${PHYSICAL_NIC}.log_martians = 1" >> "${SYSCTL_TMP_FILE}"
else
    echo "net.ipv4.conf.all.log_martians = 1" >> "${SYSCTL_TMP_FILE}"
fi

# ------------------------------------------------------------------------------
# HIGH-PERFORMANCE IN-MEMORY COMPLIANCE ENGINE (DETERMINISTIC HASHING)
# ------------------------------------------------------------------------------
verify_live_kernel_state() {
    local drift_found=0
    local -r live_raw="${SECURE_TMP}/sysctl_raw.db"
    
    # Fedora okuma hatalarını süzerek ham canlı tabloyu belleğe mühürler
    sysctl -a -e 2>/dev/null > "${live_raw}" || true

    # Deterministik İkili Alan Ayrıştırma Motoru (IFS='=')
    declare -A LIVE_KERNEL_MAP
    while IFS='=' read -r raw_key raw_val; do
        [[ -z "${raw_key}" ]] && continue
        
        # Sadece baş ve son boşlukları cerrahi olarak budama (String korumalı)
        local clean_key clean_val
        clean_key=$(echo "${raw_key}" | sed -e 's/^[ \t]*//' -e 's/[ \t]*$//')
        clean_val=$(echo "${raw_val}" | sed -e 's/^[ \t]*//' -e 's/[ \t]*$//')
        
        LIVE_KERNEL_MAP["${clean_key}"]="${clean_val}"
    done < "${live_raw}"

    # Hedef matris ile canlı belleğin süzülmesi
    while IFS='=' read -r target_key target_val; do
        [[ -z "${target_key}" || "${target_key}" =~ ^# ]] && continue
        
        target_key=$(echo "${target_key}" | sed -e 's/^[ \t]*//' -e 's/[ \t]*$//')
        target_val=$(echo "${target_val}" | sed -e 's/^[ \t]*//' -e 's/[ \t]*$//')
        
        # Çekirdek parametresi bu mimaride yoksa atla (CONFIG_BPF_JIT_ALWAYS_ON Safe)
        if [[ -z "${LIVE_KERNEL_MAP[${target_key}]+unset}" ]]; then
            echo "[!] ADLİ BİLGİ: '${target_key}' anahtarı güncel çekirdekte yok (Atlanıyor)." >&2
            continue
        fi
        
        local current_val="${LIVE_KERNEL_MAP[${target_key}]}"
        if [[ "${current_val}" != "${target_val}" ]]; then
            echo "[!] DURUM SAPMASI TESPİT EDİLDİ: ${target_key} -> Canlı Bellek: [${current_val}] | Hedef: [${target_val}]" >&2
            drift_found=1
        fi
    done < "${SYSCTL_TMP_FILE}"
    
    return "${drift_found}"
}

# ------------------------------------------------------------------------------
# DETERMINISTIC IDEMPOTENCY PIPELINE
# ------------------------------------------------------------------------------
echo "[*] Sistem ve canlı çekirdek durum matrisi taranıyor..."
set +e
verify_live_kernel_state
readonly DRIFT_CODE=$?
set -e

if [[ -f "${SYSCTL_TARGET}" && "${DRIFT_CODE}" == "0" ]]; then
    if cmp -s "${SYSCTL_TMP_FILE}" "${SYSCTL_TARGET}"; then
        echo "[+] Bilgi: Çekirdek parametre matrisi hem diskte hem canlı bellekte %100 senkronize. İdempotent çıkış."
        exit 0
    fi
fi

# ------------------------------------------------------------------------------
# REAL-TIME LIVE SÖZDİZİMİ VE BÜTÜNLÜK DOĞRULAMASI
# ------------------------------------------------------------------------------
echo "[*] Geliştirilen sysctl parametre matrisinin sözdizimi doğrulanıyor..."
while IFS='=' read -r key val; do
    [[ -z "${key}" || "${key}" =~ ^# ]] && continue
    key=$(echo "${key}" | sed -e 's/^[ \t]*//' -e 's/[ \t]*$//')
    if sysctl -n "${key}" >/dev/null 2>&1; then
        continue
    else
        echo "[!] Adli Uyarı: '${key}' anahtarı canlı runtime doğrulamayı geçemedi."
    fi
done < "${SYSCTL_TMP_FILE}"

# ------------------------------------------------------------------------------
# TRUE ATOMIC REPLACEMENT (RENAME(2) ENFORCEMENT)
# ------------------------------------------------------------------------------
if [[ -f "${SYSCTL_TARGET}" ]]; then
    readonly TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    readonly TARGET_HASH=$(sha256sum "${SYSCTL_TARGET}" | cut -d' ' -f1)
    echo "[*] Mevcut konfigürasyon sürüm olarak yedekleniyor. Sürüm: ${TIMESTAMP} | SHA256: ${TARGET_HASH}"
    cp -a "${SYSCTL_TARGET}" "${SYSCTL_TARGET}.${TIMESTAMP}.bak"
fi

echo "[*] Yapılandırma '/etc/sysctl.d/' katmanına atomik olarak mühürleniyor..."
# Aynı dosya sisteminde .new uzantısıyla hazırla, izinlerini mühürle
install -m 644 "${SYSCTL_TMP_FILE}" "${SYSCTL_TARGET}.new"

# VFS rename(2) sistem çağrısını tetikleyerek tek saat çevriminde takas et
mv -f "${SYSCTL_TARGET}.new" "${SYSCTL_TARGET}"

# POSIX Dizin ve Dosya Blok Flush İşlemleri
sync -f "${SYSCTL_TARGET}"
sync -f /etc/sysctl.d

# Çekirdek kurallarını nihai olarak enjekte etme
echo "[*] Nihai konfigürasyon çekirdek yığına enjekte ediliyor..."
sysctl --system

# ------------------------------------------------------------------------------
# FIREWALLD IDEMPOTENT HAYALET MODU (STEALTH MODE) ENFORCEMENT
# ------------------------------------------------------------------------------
echo "[*] Adım 2: Firewalld alt yapısı ve rich-rule durum analizi başlatılıyor..."
if systemctl is-active --quiet firewalld 2>/dev/null; then
    readonly ICMP_RULE='rule protocol value="icmp" drop'
    if firewall-cmd --permanent --query-rich-rule="${ICMP_RULE}" >/dev/null 2>&1; then
        echo "[+] Firewalld hayalet modu (ICMP Drop) zaten aktif ve idempotent."
    else
        echo "[*] Hayalet modu kuralı eksik. Asimetrik kalkan firewalld tablosuna ekleniyor..."
        firewall-cmd --permanent --add-rich-rule="${ICMP_RULE}"
        firewall-cmd --reload
        echo "[+] Firewalld hayalet modu başarıyla mühürlendi."
    fi
else
    echo "[-] Bilgi: Firewalld aktif değil veya pasif durumda. Atlanıyor."
fi

# ------------------------------------------------------------------------------
# NİHAİ STATE DOĞRULAMASI (VERIFICATION PIPELINE)
# ------------------------------------------------------------------------------
echo -e "\n======================================================================"
echo "[+] NİHAİ ÇEKİRDEK GÜVENLİK VE PERFORMANS RAPORU"
echo "======================================================================"
echo -n "-> TCP Congestion Control : " && sysctl -n net.ipv4.tcp_congestion_control
echo -n "-> Default Qdisc           : " && sysctl -n net.core.default_qdisc
echo -n "-> eBPF JIT Hardening      : " && (sysctl -n net.core.bpf_jit_harden 2>/dev/null || echo "N/A (Always ON)")
echo -n "-> Ptrace Scope Filter     : " && sysctl -n kernel.yama.ptrace_scope
echo -n "-> IPv6 Status (1=Disabled): " && sysctl -n net.ipv6.conf.all.disable_ipv6
echo -n "-> VM Dirty BG Ratio       : " && sysctl -n vm.dirty_background_ratio
echo -n "-> IP Forwarding (Docker)  : " && sysctl -n net.ipv4.ip_forward
echo "======================================================================"
echo -e "\e[32m[!] AEGIS LAYER-01a OPERASYONU KUSURSUZ TAMAMLANDI!\e[0m"
echo -e "\e[34m[i] Detaylı analiz log dosyası: ${LOG_FILE}\e[0m"
