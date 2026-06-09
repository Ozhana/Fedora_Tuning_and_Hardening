#!/usr/bin/env bash
# ==============================================================================
# LAYER-00: PreFlight, Aggressive Debloat & Telemetry Purge (Post-Install Engine)
# Cihaz: Surface Pro 9 | OS: Fedora 44 Workspace | Profil: Post-Install Hardening
# Açıklama: Formattan sonra sadece 1 KEZ çalıştırılacak doğrusal sıkılaştırma motoru.
# ==============================================================================

# 1. STRICT MODE (ANAYASA)
set -Eeuo pipefail
IFS=$'\n\t'

# Hedef Kullanıcı ve Ev Dizini Tespiti
TARGET_USER="${SUDO_USER:-$USER}"
USER_HOME="/home/$TARGET_USER"

# 2. LOGLAMA YAPILANDIRMASI (Masaüstü Statik Akışı)
LOG_DIR="$USER_HOME/Desktop/LOG_FILES"
mkdir -p "$LOG_DIR" && chmod 755 "$LOG_DIR"
LOG_FILE="$LOG_DIR/Layer00_PreFlight.log"

exec > >(tee -a "$LOG_FILE") 2>&1

echo "[*] [$(date +'%Y-%m-%d %H:%M:%S')] LAYER-00: Tek Seferlik Sıkılaştırma Motoru Başlatıldı."

# 3. KESİNTİ TOLERANSI (Güvenli Geçici Alan ve Trap)
SECURE_TMP=$(mktemp -d -t layer0PostInstall_XXXXXX)
chmod 700 "$SECURE_TMP"

cleanup() {
    local exit_code=$?
    echo "[*] Geçici dizin alanları kazınıyor..."
    rm -rf "$SECURE_TMP"
    echo "[*] LAYER-00 Süreci Bitti. Çıkış Kodu: $exit_code"
}
trap cleanup EXIT ERR INT TERM

# Yetki Doğrulaması
if [[ "${EUID}" -ne 0 ]]; then
    echo "[!] KRİTİK HATA: Bu betik root (sudo) yetkileriyle çalıştırılmalıdır." >&2
    exit 1
fi

# ==============================================================================
# GÖREV 1: DNF HIZLANDIRMA VE ATOMİK YAZIM
# ==============================================================================
echo "[*] Adım 1: Paket yöneticisi (DNF) paralel indirme motoru optimize ediliyor..."
DNF_CONF="/etc/dnf/dnf.conf"
DNF_TEMP="$SECURE_TMP/dnf.conf.tmp"

[[ -f "$DNF_CONF" ]] && cp "$DNF_CONF" "$DNF_TEMP" || touch "$DNF_TEMP"

declare -A DNF_TWEAKS=(
    ["fastestmirror"]="True"
    ["max_parallel_downloads"]="10"
    ["defaultyes"]="True"
)

for key in "${!DNF_TWEAKS[@]}"; do
    value="${DNF_TWEAKS[$key]}"
    if grep -q "^${key}=" "$DNF_TEMP"; then
        sed -i "s/^${key}=.*/${key}=${value}/" "$DNF_TEMP"
    else
        echo "${key}=${value}" >> "$DNF_TEMP"
    fi
done

install -m 644 "$DNF_TEMP" "$DNF_CONF"
echo "[+] DNF Hızlandırma parametreleri sisteme mühürlendi."

# ==============================================================================
# GÖREV 2: GÖRSEL BOOT PARAMETRELERİNİN METİN AKIŞINA ÇEVRİLMESİ
# ==============================================================================
echo "[*] Adım 2: Grafik ekran log perdesi (Plymouth) kaldırılıyor, metin akışı açılıyor..."

# rhgb ve quiet parametrelerini kaldır, yerine hata yakalayıcıları ekle
if grubby --info=ALL | grep -q "rhgb quiet"; then
    grubby --update-kernel=ALL --remove-args="rhgb quiet"
    grubby --update-kernel=ALL --args="systemd.show_status=true loglevel=3"
    echo "[+] Boot ekranı text tabanlı arıza tespit moduna geçirildi."
else
    echo "[-] Boot ekranı parametreleri zaten optimal."
fi

# ==============================================================================
# GÖREV 3: AGRESİF DEBLOAT (STOK AMBALAJLARIN TEMİZLİĞİ)
# ==============================================================================
echo "[*] Adım 3: Saldırı yüzeyini genişleten stok uygulamalar kazınıyor..."

BLOAT_PKGS=(
    "firefox"
    "gnome-tour"
    "yelp"
    "gnome-connections"
    "gnome-weather"
    "gnome-boxes"
)

echo "[+] Doğrusal Kaldırma İşlemi Başlatıldı: ${BLOAT_PKGS[*]}"
dnf remove -y "${BLOAT_PKGS[@]}"
dnf autoremove -y
echo "[+] Stok paket debloating tamamlandı."

# ==============================================================================
# GÖREV 4: SEÇİCİ SERVİS HARDENING VE NETWORK RECOVERY TIKANIKLIK ÖNLEMİ
# ==============================================================================
echo "[*] Adım 4: Arka plan izleme ve telemetri servisleri izole ediliyor..."

# Kritik Ağ/Kurtarma hatlarını bozmayacak saf mühürleme (Mask) listesi
SERVICES_TO_MASK=(
    "abrtd.service" 
    "abrt-journal-core.service" 
    "abrt-oops.service" 
    "abrt-xorg.service"
    "avahi-daemon.service" 
    "pcscd.service"
    "ModemManager.service" 
    "cups.service" 
    "cups.socket" 
    "cups.path"
    "iscsid.service" 
    "iscsid.socket" 
    "iscsiuio.socket"
    "multipathd.service" 
    "multipathd.socket" 
    "httpd.service"
)

for svc in "${SERVICES_TO_MASK[@]}"; do
    systemctl stop "$svc" 2>/dev/null || true
    systemctl mask "$svc" >/dev/null 2>&1
done

# Kurtarma Güvenlik Duvarı: Headless recovery lockout önlemi için disable hattı
SERVICES_TO_DISABLE=(
    "NetworkManager-wait-online.service"
    "sssd.service"
    "rpcbind.service"
    "rpcbind.socket"
    "libvirtd.service"
    "libvirtd.socket"
    "virtqemud.service"
    "virtqemud.socket"
    "qemu-guest-agent.service"
    "spice-vdagentd.service"
)

for svc in "${SERVICES_TO_DISABLE[@]}"; do
    systemctl disable --now "$svc" >/dev/null 2>&1 || true
done
echo "[+] Telemetri maskelendi, kurtarma hatları ağ güvenliği için disable edildi."

# ==============================================================================
# GÖREV 5: ATOMİK KAPANIŞ SÜRELERİ (SYSTEMD OVERRIDE)
# ==============================================================================
echo "[*] Adım 5: Sistem kapanma gecikmeleri 10 saniyeye düşürülüyor..."

SYSTEMD_CONF_DIR="/etc/systemd/system.conf.d"
mkdir -p "$SYSTEMD_CONF_DIR"

cat <<EOF > "$SECURE_TMP/99-fast-shutdown.conf"
[Manager]
DefaultTimeoutStopSec=10s
EOF
install -m 644 "$SECURE_TMP/99-fast-shutdown.conf" "$SYSTEMD_CONF_DIR/99-fast-shutdown.conf"

# DNF5 Daemon Hizmet Süreleri
for service_override in "dnf5daemon-server.service.d" "dnf-makecache.service.d"; do
    override_dir="/etc/systemd/system/${service_override}"
    mkdir -p "$override_dir"
    echo -e "[Service]\nTimeoutStopSec=10s" > "$SECURE_TMP/override.conf"
    install -m 644 "$SECURE_TMP/override.conf" "${override_dir}/override.conf"
done

systemctl daemon-reload
echo "[+] Kapanış ve daemon zaman aşımı kilitleri 10 saniyeye sabitlendi."

# ==============================================================================
# GÖREV 6: ATOMİK EV DİZİNİ TARAYICI TELEMETRİ TEMİZLİĞİ (CRASH PROOF)
# ==============================================================================
echo "[*] Adım 6: Stok kurulumdan kalan Mozilla izleme verileri atomik olarak kazınıyor..."

while IFS=: read -r _ _ uid _ _ home _; do
    if [[ "$uid" -ge 1000 && -d "$home" && "$home" != "/nohome" ]]; then
        # Kısmi silme zafiyetini (Inconsistent State) engellemek için önce güvenli alana taşı, sonra sil
        if [[ -d "$home/.mozilla" ]]; then
            mv "$home/.mozilla" "$SECURE_TMP/mozilla_wipe_$(date +%s)" 2>/dev/null || true
            echo "[+] Stok .mozilla dizini atomik olarak sistemden söküldü."
        fi
        if [[ -d "$home/.cache/mozilla" ]]; then
            mv "$home/.cache/mozilla" "$SECURE_TMP/mozilla_cache_wipe_$(date +%s)" 2>/dev/null || true
            echo "[+] Stok .mozilla önbelleği atomik olarak sistemden söküldü."
        fi
    fi
done < /etc/passwd

echo "[+] [$(date +'%Y-%m-%d %H:%M:%S')] LAYER-00: Ön Uçuş, Text-Boot, Debloat ve Ağ Süzgeci Tamamlandı."
