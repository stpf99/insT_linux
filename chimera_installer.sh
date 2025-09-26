#!/bin/bash

# Chimera Linux x86_64 UEFI Complete Installer
# Supports /dev/sdX and /dev/emmcX drives
# Uses ncurses for interface

set -e

# Colors and formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Global variables
SELECTED_DISK=""
EFI_PARTITION=""
ROOT_PARTITION=""
INSTALL_ROOT="/media/root"
INSTALLATION_TYPE=""

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Ten installer musi być uruchomiony jako root${NC}"
        exit 1
    fi
}

# Check if system is UEFI
check_uefi() {
    if [[ ! -d "/sys/firmware/efi" ]]; then
        echo -e "${RED}System nie jest uruchomiony w trybie UEFI${NC}"
        echo -e "${YELLOW}Ten installer wymaga systemu UEFI${NC}"
        exit 1
    fi
}

# Check if chimera-bootstrap exists
check_chimera_tools() {
    if ! command -v chimera-bootstrap &> /dev/null; then
        echo -e "${RED}chimera-bootstrap nie znaleziony${NC}"
        echo -e "${YELLOW}Uruchom ten installer z Chimera Linux live ISO lub zainstalowanego systemu${NC}"
        exit 1
    fi
}

# Display header
show_header() {
    clear
    echo -e "${CYAN}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║          Chimera Linux UEFI Complete Installer       ║${NC}"
    echo -e "${CYAN}║                    x86_64 Edition                    ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════╝${NC}"
    echo
}

# Show partitioning requirements
show_requirements() {
    show_header
    echo -e "${WHITE}WYMAGANIA PARTYCJONOWANIA UEFI + systemd-boot:${NC}"
    echo
    echo -e "${CYAN}Wymagane partycje:${NC}"
    echo -e "  ${GREEN}1. EFI System Partition (ESP)${NC}"
    echo -e "     • Typ: EFI System (c12a7328-f81f-11d2-ba4b-00a0c93ec93b)"
    echo -e "     • Rozmiar: minimum 200MB (zalecane 512MB)"
    echo -e "     • System plików: FAT32"
    echo -e "     • Punkt montowania: /boot (wspólny z ESP)"
    echo
    echo -e "  ${GREEN}2. Root filesystem${NC}"
    echo -e "     • Typ: Linux filesystem (0fc63daf-8483-4772-8e79-3d69d8477de4)"
    echo -e "     • Rozmiar: minimum 14GB"
    echo -e "     • System plików: f2fs (zalecane) lub ext4"
    echo
    echo -e "${CYAN}Konfiguracja systemd-boot:${NC}"
    echo -e "  • ESP musi być zamontowany jako /boot"
    echo -e "  • Nie wymaga oddzielnej partycji /boot"
    echo -e "  • Tabela partycji: GPT"
    echo
    echo -e "${YELLOW}Ten installer wykona kompletną instalację Chimera Linux${NC}"
    echo
    read -p "Naciśnij Enter aby kontynuować..."
}

# Detect available disks
detect_disks() {
    echo -e "${BLUE}Wykrywanie dostępnych dysków...${NC}"
    
    # Find all block devices that could be system disks
    DISKS=()
    
    # Check for SATA/SCSI disks (/dev/sdX)
    for disk in /dev/sd[a-z]; do
        if [[ -b "$disk" ]]; then
            SIZE=$(lsblk -dno SIZE "$disk" 2>/dev/null || echo "nieznany")
            MODEL=$(lsblk -dno MODEL "$disk" 2>/dev/null || echo "nieznany")
            DISKS+=("$disk|SATA/SCSI|$SIZE|$MODEL")
        fi
    done
    
    # Check for eMMC disks (/dev/mmcblkX)
    for disk in /dev/mmcblk[0-9]; do
        if [[ -b "$disk" ]]; then
            SIZE=$(lsblk -dno SIZE "$disk" 2>/dev/null || echo "nieznany")
            MODEL=$(lsblk -dno MODEL "$disk" 2>/dev/null || echo "eMMC")
            DISKS+=("$disk|eMMC|$SIZE|$MODEL")
        fi
    done
    
    # Check for NVMe disks (/dev/nvmeXn1)
    for disk in /dev/nvme[0-9]n1; do
        if [[ -b "$disk" ]]; then
            SIZE=$(lsblk -dno SIZE "$disk" 2>/dev/null || echo "nieznany")
            MODEL=$(lsblk -dno MODEL "$disk" 2>/dev/null || echo "NVMe")
            DISKS+=("$disk|NVMe|$SIZE|$MODEL")
        fi
    done
    
    if [[ ${#DISKS[@]} -eq 0 ]]; then
        echo -e "${RED}Nie znaleziono żadnych dysków${NC}"
        exit 1
    fi
}

# Select disk for installation
select_disk() {
    show_header
    echo -e "${WHITE}WYKRYTE DYSKI:${NC}"
    echo
    
    for i in "${!DISKS[@]}"; do
        IFS='|' read -r disk type size model <<< "${DISKS[$i]}"
        printf "%2d) %-12s %-10s %-8s %s\n" $((i+1)) "$disk" "$type" "$size" "$model"
    done
    
    echo
    while true; do
        read -p "Wybierz dysk (1-${#DISKS[@]}): " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [[ $choice -ge 1 ]] && [[ $choice -le ${#DISKS[@]} ]]; then
            IFS='|' read -r SELECTED_DISK _ _ _ <<< "${DISKS[$((choice-1))]}"
            break
        else
            echo -e "${RED}Nieprawidłowy wybór. Spróbuj ponownie.${NC}"
        fi
    done
    
    echo -e "${GREEN}Wybrano dysk: $SELECTED_DISK${NC}"
}

# Show current disk layout
show_current_layout() {
    show_header
    echo -e "${WHITE}AKTUALNY UKŁAD PARTYCJI - $SELECTED_DISK:${NC}"
    echo
    
    if lsblk "$SELECTED_DISK" >/dev/null 2>&1; then
        lsblk -f "$SELECTED_DISK"
        echo
        
        # Check partition table type
        PTABLE=$(parted "$SELECTED_DISK" print 2>/dev/null | grep "Partition Table:" | awk '{print $3}' || echo "nieznany")
        echo -e "${CYAN}Typ tabeli partycji: $PTABLE${NC}"
        echo
    else
        echo -e "${YELLOW}Dysk nie ma jeszcze partycji${NC}"
        echo
    fi
}

# Check if current layout is suitable for Chimera Linux
check_suitable_layout() {
    local efi_found=false
    local root_found=false
    local efi_size=0
    local root_size=0
    
    # Determine partition naming scheme
    local part_prefix=""
    if [[ "$SELECTED_DISK" =~ mmcblk[0-9] ]] || [[ "$SELECTED_DISK" =~ nvme[0-9]n1 ]]; then
        part_prefix="${SELECTED_DISK}p"
    else
        part_prefix="$SELECTED_DISK"
    fi
    
    # Check for EFI partition
    for part in "${part_prefix}"*; do
        if [[ -b "$part" ]]; then
            local part_type=$(lsblk -dno PARTTYPE "$part" 2>/dev/null || echo "")
            local part_size_bytes=$(lsblk -dno SIZE --bytes "$part" 2>/dev/null || echo "0")
            local part_size_mb=$((part_size_bytes / 1024 / 1024))
            
            # Check if it's EFI System Partition (c12a7328-f81f-11d2-ba4b-00a0c93ec93b)
            if [[ "$part_type" =~ ^c12a7328 ]]; then
                efi_found=true
                efi_size=$part_size_mb
                EFI_PARTITION="$part"
                break
            fi
        fi
    done
    
    # Check for suitable root partition (any Linux partition with >14GB)
    for part in "${part_prefix}"*; do
        if [[ -b "$part" ]] && [[ "$part" != "$EFI_PARTITION" ]]; then
            local part_type=$(lsblk -dno PARTTYPE "$part" 2>/dev/null || echo "")
            local part_size_bytes=$(lsblk -dno SIZE --bytes "$part" 2>/dev/null || echo "0")
            local part_size_gb=$((part_size_bytes / 1024 / 1024 / 1024))
            
            # Check if it's Linux filesystem (0fc63daf-8483-4772-8e79-3d69d8477de4)
            if [[ "$part_type" =~ ^0fc63daf ]] && [[ $part_size_gb -ge 14 ]]; then
                root_found=true
                root_size=$part_size_gb
                ROOT_PARTITION="$part"
                break
            fi
        fi
    done
    
    if [[ "$efi_found" == true ]] && [[ "$root_found" == true ]] && [[ $efi_size -ge 200 ]]; then
        echo -e "${GREEN}Znaleziono odpowiedni układ partycji:${NC}"
        echo -e "  EFI: $EFI_PARTITION (${efi_size}MB)"
        echo -e "  Root: $ROOT_PARTITION (${root_size}GB)"
        echo
        return 0
    else
        echo -e "${YELLOW}Aktualny układ nie spełnia wymagań:${NC}"
        if [[ "$efi_found" != true ]]; then
            echo -e "  • Brak partycji EFI System"
        elif [[ $efi_size -lt 200 ]]; then
            echo -e "  • Partycja EFI za mała (${efi_size}MB < 200MB)"
        fi
        if [[ "$root_found" != true ]]; then
            echo -e "  • Brak odpowiedniej partycji root (>14GB)"
        fi
        echo
        return 1
    fi
}

# Ask user about using current layout
ask_use_current() {
    while true; do
        read -p "Czy chcesz użyć aktualnego układu partycji? (t/N): " choice
        case $choice in
            [Tt]* ) return 0;;
            [Nn]* | "" ) return 1;;
            * ) echo "Odpowiedz t (tak) lub n (nie).";;
        esac
    done
}

# Confirm disk wipe
confirm_disk_wipe() {
    echo -e "${RED}UWAGA: Ta operacja usunie WSZYSTKIE dane na dysku $SELECTED_DISK${NC}"
    echo -e "${YELLOW}Czy na pewno chcesz kontynuować?${NC}"
    echo
    read -p "Wpisz 'TAK' aby potwierdzić: " confirmation
    if [[ "$confirmation" != "TAK" ]]; then
        echo -e "${YELLOW}Operacja anulowana${NC}"
        exit 0
    fi
}

# Create new partition layout
create_partitions() {
    echo -e "${BLUE}Tworzenie nowej tabeli partycji...${NC}"
    
    # Create GPT partition table
    parted -s "$SELECTED_DISK" mklabel gpt
    
    # Create EFI System Partition (512MB)
    echo -e "${BLUE}Tworzenie partycji EFI (512MB)...${NC}"
    parted -s "$SELECTED_DISK" mkpart primary fat32 1MiB 513MiB
    parted -s "$SELECTED_DISK" set 1 esp on
    
    # Create root partition (remaining space)
    echo -e "${BLUE}Tworzenie partycji root...${NC}"
    parted -s "$SELECTED_DISK" mkpart primary 513MiB 100%
    
    # Set partition variables
    if [[ "$SELECTED_DISK" =~ mmcblk[0-9] ]] || [[ "$SELECTED_DISK" =~ nvme[0-9]n1 ]]; then
        EFI_PARTITION="${SELECTED_DISK}p1"
        ROOT_PARTITION="${SELECTED_DISK}p2"
    else
        EFI_PARTITION="${SELECTED_DISK}1"
        ROOT_PARTITION="${SELECTED_DISK}2"
    fi
    
    # Wait for kernel to recognize new partitions
    sleep 2
    partprobe "$SELECTED_DISK"
    sleep 2
}

# Format partitions
format_partitions() {
    echo -e "${BLUE}Formatowanie partycji...${NC}"
    
    # Format EFI partition as FAT32
    echo -e "${BLUE}Formatowanie partycji EFI jako FAT32...${NC}"
    mkfs.fat -F32 -n "EFI" "$EFI_PARTITION"
    
    # Format root partition as f2fs
    echo -e "${BLUE}Formatowanie partycji root jako f2fs...${NC}"
    mkfs.f2fs -f -l "chimera-root" "$ROOT_PARTITION"
}

# Mount partitions
mount_partitions() {
    echo -e "${BLUE}Montowanie partycji...${NC}"
    
    # Create mount point and mount root partition
    mkdir -p "$INSTALL_ROOT"
    mount "$ROOT_PARTITION" "$INSTALL_ROOT"
    
    # Set proper permissions for root filesystem
    chmod 755 "$INSTALL_ROOT"
    
    # Create and mount EFI partition as /boot (systemd-boot requirement)
    mkdir -p "$INSTALL_ROOT/boot"
    mount "$EFI_PARTITION" "$INSTALL_ROOT/boot"
    
    echo -e "${GREEN}Partycje zamontowane w $INSTALL_ROOT${NC}"
}

# Select installation type
select_installation_type() {
    show_header
    echo -e "${WHITE}WYBÓR TYPU INSTALACJI:${NC}"
    echo
    echo -e "1) ${GREEN}Instalacja lokalna${NC} - kopiuje aktualny system live"
    echo -e "2) ${GREEN}Instalacja sieciowa${NC} - pobiera najnowsze pakiety z repozytorium"
    echo
    echo -e "${CYAN}Instalacja lokalna:${NC} szybsza, używa aktualnego systemu live"
    echo -e "${CYAN}Instalacja sieciowa:${NC} zawsze najnowsze pakiety, wymaga internetu"
    echo
    
    while true; do
        read -p "Wybierz typ instalacji (1-2): " choice
        case $choice in
            1) INSTALLATION_TYPE="local"; break;;
            2) INSTALLATION_TYPE="network"; break;;
            *) echo -e "${RED}Nieprawidłowy wybór. Wybierz 1 lub 2.${NC}";;
        esac
    done
    
    echo -e "${GREEN}Wybrano: $([ "$INSTALLATION_TYPE" = "local" ] && echo "instalacja lokalna" || echo "instalacja sieciowa")${NC}"
}

# Perform system installation
install_system() {
    show_header
    echo -e "${WHITE}INSTALACJA CHIMERA LINUX...${NC}"
    echo
    
    if [[ "$INSTALLATION_TYPE" = "local" ]]; then
        echo -e "${BLUE}Wykonywanie instalacji lokalnej...${NC}"
        chimera-bootstrap -l "$INSTALL_ROOT"
    else
        echo -e "${BLUE}Wykonywanie instalacji sieciowej...${NC}"
        chimera-bootstrap "$INSTALL_ROOT"
    fi
    
    echo -e "${GREEN}Instalacja systemu zakończona${NC}"
}

# Configure system in chroot
configure_system() {
    show_header
    echo -e "${WHITE}KONFIGURACJA SYSTEMU...${NC}"
    echo
    
    # Update system
    echo -e "${BLUE}Aktualizacja systemu...${NC}"
    chimera-chroot "$INSTALL_ROOT" /bin/sh -c "
        apk update
        apk upgrade --available || apk fix && apk upgrade --available
    "
    
    # Remove base-live if local installation
    if [[ "$INSTALLATION_TYPE" = "local" ]]; then
        echo -e "${BLUE}Usuwanie pakietu base-live...${NC}"
        chimera-chroot "$INSTALL_ROOT" /bin/sh -c "apk del base-live" || true
    fi
    
    # Install kernel
    echo -e "${BLUE}Instalacja kernela...${NC}"
    chimera-chroot "$INSTALL_ROOT" /bin/sh -c "apk add linux-lts"
    
    # Generate fstab
    echo -e "${BLUE}Generowanie /etc/fstab...${NC}"
    genfstab "$INSTALL_ROOT" >> "$INSTALL_ROOT/etc/fstab"
    
    # Set root password
    echo -e "${BLUE}Ustawianie hasła root...${NC}"
    echo -e "${YELLOW}Ustaw hasło dla konta root:${NC}"
    chimera-chroot "$INSTALL_ROOT" passwd root
    
    # Create initramfs
    echo -e "${BLUE}Tworzenie initramfs...${NC}"
    chimera-chroot "$INSTALL_ROOT" /bin/sh -c "update-initramfs -c -k all"
    
    echo -e "${GREEN}Konfiguracja systemu zakończona${NC}"
}

# Install and configure systemd-boot
install_bootloader() {
    show_header
    echo -e "${WHITE}INSTALACJA SYSTEMD-BOOT...${NC}"
    echo
    
    # Install systemd-boot package
    echo -e "${BLUE}Instalacja pakietu systemd-boot...${NC}"
    chimera-chroot "$INSTALL_ROOT" /bin/sh -c "apk add systemd-boot"
    
    # Install bootloader
    echo -e "${BLUE}Instalacja bootloadera...${NC}"
    chimera-chroot "$INSTALL_ROOT" /bin/sh -c "bootctl install"
    
    # Configure loader
    echo -e "${BLUE}Konfiguracja bootloadera...${NC}"
    cat > "$INSTALL_ROOT/boot/loader/loader.conf" << EOF
default chimera.conf
timeout 5
console-mode max
editor no
EOF
    
    # Generate boot entries
    echo -e "${BLUE}Generowanie wpisów bootowania...${NC}"
    chimera-chroot "$INSTALL_ROOT" /bin/sh -c "gen-systemd-boot"
    
    echo -e "${GREEN}systemd-boot zainstalowany i skonfigurowany${NC}"
}

# Show installation summary
show_summary() {
    show_header
    echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║             INSTALACJA ZAKOŃCZONA POMYŚLNIE          ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
    echo
    echo -e "${WHITE}PODSUMOWANIE INSTALACJI:${NC}"
    echo -e "  • Dysk: $SELECTED_DISK"
    echo -e "  • EFI: $EFI_PARTITION -> /boot"
    echo -e "  • Root: $ROOT_PARTITION -> /"
    echo -e "  • Typ instalacji: $([ "$INSTALLATION_TYPE" = "local" ] && echo "lokalna" || echo "sieciowa")"
    echo -e "  • Bootloader: systemd-boot"
    echo -e "  • System plików: f2fs (root), FAT32 (EFI)"
    echo
    echo -e "${WHITE}NASTĘPNE KROKI:${NC}"
    echo -e "  1. Wyloguj się z chroot (jeśli jesteś w nim)"
    echo -e "  2. Odmontuj partycje: umount -R $INSTALL_ROOT"
    echo -e "  3. Uruchom ponownie system"
    echo -e "  4. Usuń nośnik instalacyjny i uruchom z dysku"
    echo -e "  5. Zaloguj się jako root z ustawionym hasłem"
    echo
    echo -e "${CYAN}Dokumentacja konfiguracji:${NC}"
    echo -e "  https://chimera-linux.org/docs/configuration/post-installation"
    echo
    read -p "Naciśnij Enter aby zakończyć..."
}

# Cleanup on exit
cleanup() {
    echo -e "${YELLOW}Odmontowywanie partycji...${NC}"
    umount -R "$INSTALL_ROOT" 2>/dev/null || true
}

# Main function
main() {
    check_root
    check_uefi
    check_chimera_tools
    
    show_requirements
    
    detect_disks
    select_disk
    
    show_current_layout
    
    if check_suitable_layout; then
        if ask_use_current; then
            echo -e "${GREEN}Używanie aktualnego układu partycji${NC}"
            mount_partitions
        else
            confirm_disk_wipe
            create_partitions
            format_partitions
            mount_partitions
        fi
    else
        confirm_disk_wipe
        create_partitions
        format_partitions
        mount_partitions
    fi
    
    select_installation_type
    install_system
    configure_system
    install_bootloader
    
    show_summary
}

# Trap to cleanup on exit
trap cleanup EXIT

# Run main function
main "$@"