#!/bin/sh

# Chimera Linux x86_64 UEFI Installer
# Basic installation without repair mode
# POSIX shell compatible

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# Global variables
SELECTED_DISK=""
EFI_PARTITION=""
ROOT_PARTITION=""
INSTALL_ROOT="/media/root"
INSTALLATION_TYPE=""

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        printf "${RED}Ten installer musi byc uruchomiony jako root${NC}\n"
        exit 1
    fi
}

check_uefi() {
    if [ ! -d "/sys/firmware/efi" ]; then
        printf "${RED}System nie jest uruchomiony w trybie UEFI${NC}\n"
        printf "${YELLOW}Ten installer wymaga systemu UEFI${NC}\n"
        exit 1
    fi
}

check_chimera_tools() {
    printf "${BLUE}Sprawdzanie wymaganych narzedzi...${NC}\n"
    
    if ! command -v chimera-bootstrap > /dev/null 2>&1; then
        printf "${RED}chimera-bootstrap nie znaleziony${NC}\n"
        exit 1
    fi
    
    if ! command -v parted > /dev/null 2>&1; then
        printf "${YELLOW}Instalacja parted...${NC}\n"
        apk add parted util-linux || exit 1
    fi
    
    for tool in mkfs.fat mkfs.f2fs lsblk; do
        if ! command -v "$tool" > /dev/null 2>&1; then
            case "$tool" in
                mkfs.fat) apk add dosfstools;;
                mkfs.f2fs) apk add f2fs-tools;;
                lsblk) apk add util-linux;;
            esac
        fi
    done
    
    printf "${GREEN}Wszystkie narzedzia dostepne${NC}\n"
}

show_header() {
    clear
    printf "${CYAN}╔══════════════════════════════════════════════════════╗${NC}\n"
    printf "${CYAN}║          Chimera Linux UEFI Installer                ║${NC}\n"
    printf "${CYAN}║                x86_64 Edition                        ║${NC}\n"
    printf "${CYAN}╚══════════════════════════════════════════════════════╝${NC}\n"
    printf "\n"
}

show_requirements() {
    show_header
    printf "${WHITE}WYMAGANIA PARTYCJONOWANIA UEFI + systemd-boot:${NC}\n"
    printf "\n"
    printf "${CYAN}Wymagane partycje:${NC}\n"
    printf "  ${GREEN}1. EFI System Partition (ESP)${NC}\n"
    printf "     - Typ: EFI System\n"
    printf "     - Rozmiar: minimum 512MB\n"
    printf "     - System plikow: FAT32\n"
    printf "     - Punkt montowania: /boot\n"
    printf "\n"
    printf "  ${GREEN}2. Root filesystem${NC}\n"
    printf "     - Typ: Linux filesystem\n"
    printf "     - Rozmiar: minimum 14GB\n"
    printf "     - System plikow: f2fs\n"
    printf "\n"
    printf "Nacisnij Enter aby kontynuowac..."
    read dummy
}

detect_disks() {
    printf "${BLUE}Wykrywanie dostepnych dyskow...${NC}\n"
    
    DISK_LIST_FILE="/tmp/chimera_disks.$$"
    > "$DISK_LIST_FILE"
    
    for disk in /dev/sd[a-z] /dev/mmcblk[0-9] /dev/nvme[0-9]n1; do
        if [ -b "$disk" ]; then
            SIZE=$(lsblk -dno SIZE "$disk" 2>/dev/null || printf "unknown")
            MODEL=$(lsblk -dno MODEL "$disk" 2>/dev/null || printf "unknown")
            printf "%s|%s|%s\n" "$disk" "$SIZE" "$MODEL" >> "$DISK_LIST_FILE"
        fi
    done
    
    if [ ! -s "$DISK_LIST_FILE" ]; then
        printf "${RED}Nie znaleziono zadnych dyskow${NC}\n"
        exit 1
    fi
}

select_disk() {
    show_header
    printf "${WHITE}WYKRYTE DYSKI:${NC}\n\n"
    
    i=1
    while IFS='|' read -r disk size model; do
        printf "%2d) %-12s %-8s %s\n" "$i" "$disk" "$size" "$model"
        i=$((i + 1))
    done < "$DISK_LIST_FILE"
    
    total_disks=$((i - 1))
    printf "\n"
    
    while true; do
        printf "Wybierz dysk (1-%d): " "$total_disks"
        read choice
        
        if [ "$choice" -ge 1 ] 2>/dev/null && [ "$choice" -le "$total_disks" ]; then
            SELECTED_DISK=$(sed -n "${choice}p" "$DISK_LIST_FILE" | cut -d'|' -f1)
            break
        fi
        printf "${RED}Nieprawidlowy wybor${NC}\n"
    done
    
    rm -f "$DISK_LIST_FILE"
}

show_current_layout() {
    show_header
    printf "${WHITE}AKTUALNY UKLAD PARTYCJI - %s:${NC}\n\n" "$SELECTED_DISK"
    lsblk -f "$SELECTED_DISK" 2>/dev/null || true
    printf "\n"
}

confirm_disk_wipe() {
    printf "${RED}UWAGA: Ta operacja usunie WSZYSTKIE dane na dysku %s${NC}\n" "$SELECTED_DISK"
    printf "\nWpisz 'TAK' aby potwierdzic: "
    read confirmation
    if [ "$confirmation" != "TAK" ]; then
        printf "${YELLOW}Operacja anulowana${NC}\n"
        exit 0
    fi
}

create_partitions() {
    printf "${BLUE}Tworzenie nowej tabeli partycji...${NC}\n"
    
    dd if=/dev/zero of="$SELECTED_DISK" bs=1M count=10 2>/dev/null || true
    
    parted -s "$SELECTED_DISK" mklabel gpt
    parted -s "$SELECTED_DISK" mkpart primary fat32 1MiB 513MiB
    parted -s "$SELECTED_DISK" set 1 esp on
    parted -s "$SELECTED_DISK" mkpart primary 513MiB 100%
    
    case "$SELECTED_DISK" in
        */mmcblk[0-9]|*/nvme[0-9]n1)
            EFI_PARTITION="${SELECTED_DISK}p1"
            ROOT_PARTITION="${SELECTED_DISK}p2"
            ;;
        *)
            EFI_PARTITION="${SELECTED_DISK}1"
            ROOT_PARTITION="${SELECTED_DISK}2"
            ;;
    esac
    
    sleep 3
    partprobe "$SELECTED_DISK" 2>/dev/null || true
    sleep 2
}

format_partitions() {
    printf "${BLUE}Formatowanie partycji...${NC}\n"
    mkfs.fat -F32 -n "EFI" "$EFI_PARTITION"
    mkfs.f2fs -f -l "chimera-root" "$ROOT_PARTITION"
}

mount_partitions() {
    printf "${BLUE}Montowanie partycji...${NC}\n"
    
    mkdir -p "$INSTALL_ROOT"
    mount "$ROOT_PARTITION" "$INSTALL_ROOT"
    chmod 755 "$INSTALL_ROOT"
    
    mkdir -p "$INSTALL_ROOT/boot"
    mount "$EFI_PARTITION" "$INSTALL_ROOT/boot"
    chmod 700 "$INSTALL_ROOT/boot"
}

select_installation_type() {
    show_header
    printf "${WHITE}WYBOR TYPU INSTALACJI:${NC}\n\n"
    printf "1) Instalacja lokalna\n"
    printf "2) Instalacja sieciowa\n\n"
    
    while true; do
        printf "Wybierz (1-2): "
        read choice
        case "$choice" in
            1) INSTALLATION_TYPE="local"; break;;
            2) INSTALLATION_TYPE="network"; break;;
        esac
    done
}

install_system() {
    printf "${BLUE}Instalacja systemu...${NC}\n"
    
    if [ "$INSTALLATION_TYPE" = "local" ]; then
        chimera-bootstrap -l -f "$INSTALL_ROOT"
    else
        chimera-bootstrap -f "$INSTALL_ROOT"
    fi
}

configure_system() {
    printf "${BLUE}Konfiguracja systemu...${NC}\n"
    
    chimera-chroot "$INSTALL_ROOT" /bin/sh -c "apk update && apk upgrade --available"
    
    if [ "$INSTALLATION_TYPE" = "local" ]; then
        chimera-chroot "$INSTALL_ROOT" /bin/sh -c "apk del base-live" || true
    fi
    
    chimera-chroot "$INSTALL_ROOT" /bin/sh -c "apk add linux-lts"
    
    # Generate fstab
    ROOT_UUID=$(lsblk -no UUID "$ROOT_PARTITION" 2>/dev/null)
    EFI_UUID=$(lsblk -no UUID "$EFI_PARTITION" 2>/dev/null)
    
    cat > "$INSTALL_ROOT/etc/fstab" << EOF
UUID=$ROOT_UUID / f2fs defaults 0 1
UUID=$EFI_UUID /boot vfat defaults,umask=0077,fmask=0177,dmask=0077 0 2
EOF
    
    printf "Ustaw haslo root:\n"
    chimera-chroot "$INSTALL_ROOT" passwd root
    
    printf "Podaj nazwe uzytkownika: "
    read username
    if [ -n "$username" ]; then
        chimera-chroot "$INSTALL_ROOT" /bin/sh -c "useradd '$username'"
        chimera-chroot "$INSTALL_ROOT" passwd "$username"
    fi
    
    chimera-chroot "$INSTALL_ROOT" /bin/sh -c "update-initramfs -c -k all"
}

install_bootloader() {
    printf "${BLUE}Instalacja systemd-boot...${NC}\n"
    
    chimera-chroot "$INSTALL_ROOT" /bin/sh -c "apk add systemd-boot"
    chimera-chroot "$INSTALL_ROOT" /bin/sh -c "bootctl install"
    
    cat > "$INSTALL_ROOT/boot/loader/loader.conf" << 'EOF'
default chimera.conf
timeout 5
console-mode max
editor no
EOF
    
    chimera-chroot "$INSTALL_ROOT" /bin/sh -c "gen-systemd-boot"
}

show_summary() {
    show_header
    printf "${GREEN}INSTALACJA ZAKONCZONA${NC}\n\n"
    printf "Dysk: %s\n" "$SELECTED_DISK"
    printf "EFI: %s -> /boot\n" "$EFI_PARTITION"
    printf "Root: %s -> /\n" "$ROOT_PARTITION"
    printf "\nNacisnij Enter..."
    read dummy
}

cleanup() {
    umount -R "$INSTALL_ROOT" 2>/dev/null || true
    rm -f "/tmp/chimera_disks.$$" 2>/dev/null || true
}

main() {
    check_root
    check_uefi
    check_chimera_tools
    
    show_requirements
    detect_disks
    select_disk
    show_current_layout
    confirm_disk_wipe
    create_partitions
    format_partitions
    mount_partitions
    select_installation_type
    install_system
    configure_system
    install_bootloader
    show_summary
    
    cleanup
}

main "$@"
