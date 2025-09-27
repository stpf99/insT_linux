#!/bin/sh

# Chimera Linux x86_64 UEFI Complete Installer
# Supports /dev/sdX and /dev/emmcX drives
# POSIX shell compatible

set -e

# Colors and formatting (using POSIX escape sequences)
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

# Check if running as root
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        printf "${RED}Ten installer musi być uruchomiony jako root${NC}\n"
        exit 1
    fi
}

# Check if system is UEFI
check_uefi() {
    if [ ! -d "/sys/firmware/efi" ]; then
        printf "${RED}System nie jest uruchomiony w trybie UEFI${NC}\n"
        printf "${YELLOW}Ten installer wymaga systemu UEFI${NC}\n"
        exit 1
    fi
}

# Check if chimera-bootstrap exists
check_chimera_tools() {
    printf "${BLUE}Sprawdzanie wymaganych narzędzi...${NC}\n"
    
    # Check chimera-bootstrap
    if ! command -v chimera-bootstrap > /dev/null 2>&1; then
        printf "${RED}chimera-bootstrap nie znaleziony${NC}\n"
        printf "${YELLOW}Uruchom ten installer z Chimera Linux live ISO lub zainstalowanego systemu${NC}\n"
        exit 1
    fi
    
    # Check parted
    if ! command -v parted > /dev/null 2>&1; then
        printf "${RED}parted nie znaleziony${NC}\n"
        printf "${YELLOW}Instalacja wymaganych narzędzi...${NC}\n"
        if command -v apk > /dev/null 2>&1; then
            if apk add parted util-linux; then
                printf "${GREEN}Narzędzia zainstalowane${NC}\n"
            else
                printf "${RED}Nie można zainstalować parted. Zainstaluj ręcznie: apk add parted util-linux${NC}\n"
                exit 1
            fi
        else
            printf "${RED}Zainstaluj parted ręcznie przed uruchomieniem installera${NC}\n"
            exit 1
        fi
    fi
    
    # Check other required tools
    for tool in mkfs.fat mkfs.f2fs lsblk; do
        if ! command -v "$tool" > /dev/null 2>&1; then
            printf "${YELLOW}Brak narzędzia: %s${NC}\n" "$tool"
            if command -v apk > /dev/null 2>&1; then
                case "$tool" in
                    mkfs.fat) 
                        apk add dosfstools;;
                    mkfs.f2fs) 
                        apk add f2fs-tools;;
                    lsblk) 
                        apk add util-linux;;
                esac
            else
                printf "${RED}Zainstaluj wymagane narzędzia przed uruchomieniem${NC}\n"
                exit 1
            fi
        fi
    done
    
    printf "${GREEN}Wszystkie wymagane narzędzia są dostępne${NC}\n"
}

# Display header
show_header() {
    clear
    printf "${CYAN}╔══════════════════════════════════════════════════════╗${NC}\n"
    printf "${CYAN}║          Chimera Linux UEFI Complete Installer       ║${NC}\n"
    printf "${CYAN}║                    x86_64 Edition                    ║${NC}\n"
    printf "${CYAN}╚══════════════════════════════════════════════════════╝${NC}\n"
    printf "\n"
}

# Show partitioning requirements
show_requirements() {
    show_header
    printf "${WHITE}WYMAGANIA PARTYCJONOWANIA UEFI + systemd-boot:${NC}\n"
    printf "\n"
    printf "${CYAN}Wymagane partycje:${NC}\n"
    printf "  ${GREEN}1. EFI System Partition (ESP)${NC}\n"
    printf "     • Typ: EFI System (c12a7328-f81f-11d2-ba4b-00a0c93ec93b)\n"
    printf "     • Rozmiar: minimum 200MB (zalecane 512MB)\n"
    printf "     • System plików: FAT32\n"
    printf "     • Punkt montowania: /boot (wspólny z ESP)\n"
    printf "\n"
    printf "  ${GREEN}2. Root filesystem${NC}\n"
    printf "     • Typ: Linux filesystem (0fc63daf-8483-4772-8e79-3d69d8477de4)\n"
    printf "     • Rozmiar: minimum 14GB\n"
    printf "     • System plików: f2fs (zalecane) lub ext4\n"
    printf "\n"
    printf "${CYAN}Konfiguracja systemd-boot:${NC}\n"
    printf "  • ESP musi być zamontowany jako /boot\n"
    printf "  • Nie wymaga oddzielnej partycji /boot\n"
    printf "  • Tabela partycji: GPT\n"
    printf "\n"
    printf "${YELLOW}Ten installer wykona kompletną instalację Chimera Linux${NC}\n"
    printf "\n"
    printf "Naciśnij Enter aby kontynuować..."
    read dummy
}

# Detect available disks
detect_disks() {
    printf "${BLUE}Wykrywanie dostępnych dysków...${NC}\n"
    
    # Create temporary file to store disk list
    DISK_LIST_FILE="/tmp/chimera_disks.$$"
    > "$DISK_LIST_FILE"
    
    # Check for SATA/SCSI disks (/dev/sdX)
    for disk in /dev/sd[a-z]; do
        if [ -b "$disk" ]; then
            SIZE=$(lsblk -dno SIZE "$disk" 2>/dev/null || printf "nieznany")
            MODEL=$(lsblk -dno MODEL "$disk" 2>/dev/null || printf "nieznany")
            printf "%s|SATA/SCSI|%s|%s\n" "$disk" "$SIZE" "$MODEL" >> "$DISK_LIST_FILE"
        fi
    done
    
    # Check for eMMC disks (/dev/mmcblkX)
    for disk in /dev/mmcblk[0-9]; do
        if [ -b "$disk" ]; then
            SIZE=$(lsblk -dno SIZE "$disk" 2>/dev/null || printf "nieznany")
            MODEL=$(lsblk -dno MODEL "$disk" 2>/dev/null || printf "eMMC")
            printf "%s|eMMC|%s|%s\n" "$disk" "$SIZE" "$MODEL" >> "$DISK_LIST_FILE"
        fi
    done
    
    # Check for NVMe disks (/dev/nvmeXn1)
    for disk in /dev/nvme[0-9]n1; do
        if [ -b "$disk" ]; then
            SIZE=$(lsblk -dno SIZE "$disk" 2>/dev/null || printf "nieznany")
            MODEL=$(lsblk -dno MODEL "$disk" 2>/dev/null || printf "NVMe")
            printf "%s|NVMe|%s|%s\n" "$disk" "$SIZE" "$MODEL" >> "$DISK_LIST_FILE"
        fi
    done
    
    if [ ! -s "$DISK_LIST_FILE" ]; then
        printf "${RED}Nie znaleziono żadnych dysków${NC}\n"
        rm -f "$DISK_LIST_FILE"
        exit 1
    fi
}

# Select disk for installation
select_disk() {
    show_header
    printf "${WHITE}WYKRYTE DYSKI:${NC}\n"
    printf "\n"
    
    # Display disks with numbers
    i=1
    while IFS='|' read -r disk type size model; do
        printf "%2d) %-12s %-10s %-8s %s\n" "$i" "$disk" "$type" "$size" "$model"
        i=$((i + 1))
    done < "$DISK_LIST_FILE"
    
    total_disks=$((i - 1))
    printf "\n"
    
    while true; do
        printf "Wybierz dysk (1-%d): " "$total_disks"
        read choice
        
        # Check if choice is a number
        case "$choice" in
            ''|*[!0-9]*) 
                printf "${RED}Nieprawidłowy wybór. Spróbuj ponownie.${NC}\n"
                continue
                ;;
        esac
        
        if [ "$choice" -ge 1 ] && [ "$choice" -le "$total_disks" ]; then
            # Get selected disk
            SELECTED_DISK=$(sed -n "${choice}p" "$DISK_LIST_FILE" | cut -d'|' -f1)
            break
        else
            printf "${RED}Nieprawidłowy wybór. Spróbuj ponownie.${NC}\n"
        fi
    done
    
    printf "${GREEN}Wybrano dysk: %s${NC}\n" "$SELECTED_DISK"
    rm -f "$DISK_LIST_FILE"
}

# Show current disk layout
show_current_layout() {
    show_header
    printf "${WHITE}AKTUALNY UKŁAD PARTYCJI - %s:${NC}\n" "$SELECTED_DISK"
    printf "\n"
    
    if lsblk "$SELECTED_DISK" > /dev/null 2>&1; then
        lsblk -f "$SELECTED_DISK"
        printf "\n"
        
        # Check partition table type
        PTABLE=$(parted "$SELECTED_DISK" print 2>/dev/null | grep "Partition Table:" | awk '{print $3}' || printf "nieznany")
        printf "${CYAN}Typ tabeli partycji: %s${NC}\n" "$PTABLE"
        printf "\n"
    else
        printf "${YELLOW}Dysk nie ma jeszcze partycji${NC}\n"
        printf "\n"
    fi
}

# Check if current layout is suitable for Chimera Linux
check_suitable_layout() {
    efi_found=false
    root_found=false
    efi_size=0
    root_size=0
    
    # Determine partition naming scheme
    case "$SELECTED_DISK" in
        */mmcblk[0-9]|*/nvme[0-9]n1)
            part_prefix="${SELECTED_DISK}p"
            ;;
        *)
            part_prefix="$SELECTED_DISK"
            ;;
    esac
    
    # Check for EFI partition
    for part in "${part_prefix}"*; do
        if [ -b "$part" ]; then
            part_type=$(lsblk -dno PARTTYPE "$part" 2>/dev/null || printf "")
            part_size_bytes=$(lsblk -dno SIZE --bytes "$part" 2>/dev/null || printf "0")
            part_size_mb=$((part_size_bytes / 1024 / 1024))
            
            # Check if it's EFI System Partition (c12a7328-f81f-11d2-ba4b-00a0c93ec93b)
            case "$part_type" in
                c12a7328*)
                    efi_found=true
                    efi_size=$part_size_mb
                    EFI_PARTITION="$part"
                    break
                    ;;
            esac
        fi
    done
    
    # Check for suitable root partition (any Linux partition with >14GB)
    for part in "${part_prefix}"*; do
        if [ -b "$part" ] && [ "$part" != "$EFI_PARTITION" ]; then
            part_type=$(lsblk -dno PARTTYPE "$part" 2>/dev/null || printf "")
            part_size_bytes=$(lsblk -dno SIZE --bytes "$part" 2>/dev/null || printf "0")
            part_size_gb=$((part_size_bytes / 1024 / 1024 / 1024))
            
            # Check if it's Linux filesystem (0fc63daf-8483-4772-8e79-3d69d8477de4)
            case "$part_type" in
                0fc63daf*)
                    if [ "$part_size_gb" -ge 14 ]; then
                        root_found=true
                        root_size=$part_size_gb
                        ROOT_PARTITION="$part"
                        break
                    fi
                    ;;
            esac
        fi
    done
    
    if [ "$efi_found" = true ] && [ "$root_found" = true ] && [ "$efi_size" -ge 200 ]; then
        printf "${GREEN}Znaleziono odpowiedni układ partycji:${NC}\n"
        printf "  EFI: %s (%dMB)\n" "$EFI_PARTITION" "$efi_size"
        printf "  Root: %s (%dGB)\n" "$ROOT_PARTITION" "$root_size"
        printf "\n"
        return 0
    else
        printf "${YELLOW}Aktualny układ nie spełnia wymagań:${NC}\n"
        if [ "$efi_found" != true ]; then
            printf "  • Brak partycji EFI System\n"
        elif [ "$efi_size" -lt 200 ]; then
            printf "  • Partycja EFI za mała (%dMB < 200MB)\n" "$efi_size"
        fi
        if [ "$root_found" != true ]; then
            printf "  • Brak odpowiedniej partycji root (>14GB)\n"
        fi
        printf "\n"
        return 1
    fi
}

# Ask user about using current layout
ask_use_current() {
    while true; do
        printf "Czy chcesz użyć aktualnego układu partycji? (t/N): "
        read choice
        case "$choice" in
            [Tt]*) return 0;;
            [Nn]*|"") return 1;;
            *) printf "Odpowiedz t (tak) lub n (nie).\n";;
        esac
    done
}

# Confirm disk wipe
confirm_disk_wipe() {
    printf "${RED}UWAGA: Ta operacja usunie WSZYSTKIE dane na dysku %s${NC}\n" "$SELECTED_DISK"
    printf "${YELLOW}Czy na pewno chcesz kontynuować?${NC}\n"
    printf "\n"
    printf "Wpisz 'TAK' aby potwierdzić: "
    read confirmation
    if [ "$confirmation" != "TAK" ]; then
        printf "${YELLOW}Operacja anulowana${NC}\n"
        exit 0
    fi
}

# Create new partition layout
create_partitions() {
    printf "${BLUE}Tworzenie nowej tabeli partycji...${NC}\n"
    
    # Unmount any mounted partitions on this disk first
    for part in "${SELECTED_DISK}"*; do
        if [ -b "$part" ] && mountpoint -q "$part" 2>/dev/null; then
            printf "${YELLOW}Odmontowywanie %s...${NC}\n" "$part"
            umount "$part" 2>/dev/null || true
        fi
    done
    
    # Wipe first sectors to ensure clean slate
    printf "${BLUE}Czyszczenie początku dysku...${NC}\n"
    dd if=/dev/zero of="$SELECTED_DISK" bs=1M count=10 2>/dev/null || true
    
    # Create GPT partition table
    printf "${BLUE}Tworzenie tabeli partycji GPT...${NC}\n"
    parted -s "$SELECTED_DISK" mklabel gpt
    
    # Create EFI System Partition (512MB)
    printf "${BLUE}Tworzenie partycji EFI (512MB)...${NC}\n"
    parted -s "$SELECTED_DISK" mkpart primary fat32 1MiB 513MiB
    parted -s "$SELECTED_DISK" set 1 esp on
    
    # Create root partition (remaining space)
    printf "${BLUE}Tworzenie partycji root...${NC}\n"
    parted -s "$SELECTED_DISK" mkpart primary 513MiB 100%
    
    # Set partition variables
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
    
    # Wait for kernel to recognize new partitions
    printf "${BLUE}Oczekiwanie na rozpoznanie partycji...${NC}\n"
    sleep 3
    partprobe "$SELECTED_DISK" 2>/dev/null || true
    sleep 2
    
    # Verify partitions were created
    if [ ! -b "$EFI_PARTITION" ] || [ ! -b "$ROOT_PARTITION" ]; then
        printf "${RED}Błąd: Partycje nie zostały utworzone poprawnie${NC}\n"
        printf "Spróbuj ponownie lub sprawdź dysk ręcznie\n"
        exit 1
    fi
    
    printf "${GREEN}Partycje utworzone pomyślnie${NC}\n"
}

# Format partitions
format_partitions() {
    printf "${BLUE}Formatowanie partycji...${NC}\n"
    
    # Format EFI partition as FAT32
    printf "${BLUE}Formatowanie partycji EFI jako FAT32...${NC}\n"
    mkfs.fat -F32 -n "EFI" "$EFI_PARTITION"
    
    # Format root partition as f2fs
    printf "${BLUE}Formatowanie partycji root jako f2fs...${NC}\n"
    mkfs.f2fs -f -l "chimera-root" "$ROOT_PARTITION"
}

# Mount partitions
mount_partitions() {
    printf "${BLUE}Montowanie partycji...${NC}\n"
    
    # Unmount partitions if already mounted
    umount "$INSTALL_ROOT/boot" 2>/dev/null || true
    umount "$INSTALL_ROOT" 2>/dev/null || true
    
    # Create mount point and mount root partition
    mkdir -p "$INSTALL_ROOT"
    mount "$ROOT_PARTITION" "$INSTALL_ROOT"
    
    # Set proper permissions for root filesystem
    chmod 755 "$INSTALL_ROOT"
    
    # Clean the mounted filesystem completely (except lost+found)
    printf "${BLUE}Czyszczenie systemu plików...${NC}\n"
    if [ "$(ls -A "$INSTALL_ROOT" 2>/dev/null)" ]; then
        # Remove everything except lost+found
        find "$INSTALL_ROOT" -mindepth 1 -maxdepth 1 ! -name 'lost+found' -exec rm -rf {} \; 2>/dev/null || true
        # Also clean any hidden files/directories except lost+found
        find "$INSTALL_ROOT" -mindepth 1 -maxdepth 1 -name '.*' ! -name 'lost+found' -exec rm -rf {} \; 2>/dev/null || true
    fi
    
    # Create and mount EFI partition as /boot (systemd-boot requirement)
    mkdir -p "$INSTALL_ROOT/boot"
    mount "$EFI_PARTITION" "$INSTALL_ROOT/boot"
    
    # Clean EFI partition if needed (but preserve EFI directory structure if exists)
    if [ "$(ls -A "$INSTALL_ROOT/boot" 2>/dev/null | grep -v '^EFI

# Select installation type
select_installation_type() {
    show_header
    printf "${WHITE}WYBÓR TYPU INSTALACJI:${NC}\n"
    printf "\n"
    printf "1) ${GREEN}Instalacja lokalna${NC} - kopiuje aktualny system live\n"
    printf "2) ${GREEN}Instalacja sieciowa${NC} - pobiera najnowsze pakiety z repozytorium\n"
    printf "\n"
    printf "${CYAN}Instalacja lokalna:${NC} szybsza, używa aktualnego systemu live\n"
    printf "${CYAN}Instalacja sieciowa:${NC} zawsze najnowsze pakiety, wymaga internetu\n"
    printf "\n"
    
    while true; do
        printf "Wybierz typ instalacji (1-2): "
        read choice
        case "$choice" in
            1) INSTALLATION_TYPE="local"; break;;
            2) INSTALLATION_TYPE="network"; break;;
            *) printf "${RED}Nieprawidłowy wybór. Wybierz 1 lub 2.${NC}\n";;
        esac
    done
    
    if [ "$INSTALLATION_TYPE" = "local" ]; then
        printf "${GREEN}Wybrano: instalacja lokalna${NC}\n"
    else
        printf "${GREEN}Wybrano: instalacja sieciowa${NC}\n"
    fi
}

# Perform system installation
install_system() {
    show_header
    printf "${WHITE}INSTALACJA CHIMERA LINUX...${NC}\n"
    printf "\n"
    
    # Always clean thoroughly and use force flag for existing partitions
    printf "${BLUE}Przygotowanie do instalacji...${NC}\n"
    
    # Remove everything from root except boot and lost+found
    find "$INSTALL_ROOT" -mindepth 1 -maxdepth 1 ! -name 'boot' ! -name 'lost+found' -exec rm -rf {} \; 2>/dev/null || true
    find "$INSTALL_ROOT" -mindepth 1 -maxdepth 1 -name '.*' ! -name 'lost+found' -exec rm -rf {} \; 2>/dev/null || true
    
    # Clean boot directory but preserve EFI structure
    if [ -d "$INSTALL_ROOT/boot" ]; then
        find "$INSTALL_ROOT/boot" -mindepth 1 -maxdepth 1 ! -name 'EFI' -exec rm -rf {} \; 2>/dev/null || true
    fi
    
    # Sync to ensure all operations are completed
    sync
    
    printf "${GREEN}Katalog przygotowany do instalacji${NC}\n"
    
    # Always use force flag when using existing partitions
    if [ "$INSTALLATION_TYPE" = "local" ]; then
        printf "${BLUE}Wykonywanie instalacji lokalnej (z flagą force)...${NC}\n"
        chimera-bootstrap -l -f "$INSTALL_ROOT"
    else
        printf "${BLUE}Wykonywanie instalacji sieciowej (z flagą force)...${NC}\n"
        chimera-bootstrap -f "$INSTALL_ROOT"
    fi
    
    printf "${GREEN}Instalacja systemu zakończona${NC}\n"
}

# Configure system in chroot
configure_system() {
    show_header
    printf "${WHITE}KONFIGURACJA SYSTEMU...${NC}\n"
    printf "\n"
    
    # Update system
    printf "${BLUE}Aktualizacja systemu...${NC}\n"
    chimera-chroot "$INSTALL_ROOT" /bin/sh -c 'apk update'
    if ! chimera-chroot "$INSTALL_ROOT" /bin/sh -c 'apk upgrade --available'; then
        chimera-chroot "$INSTALL_ROOT" /bin/sh -c 'apk fix'
        chimera-chroot "$INSTALL_ROOT" /bin/sh -c 'apk upgrade --available'
    fi
    
    # Remove base-live if local installation
    if [ "$INSTALLATION_TYPE" = "local" ]; then
        printf "${BLUE}Usuwanie pakietu base-live...${NC}\n"
        chimera-chroot "$INSTALL_ROOT" /bin/sh -c "apk del base-live" || true
    fi
    
    # Install kernel
    printf "${BLUE}Instalacja kernela...${NC}\n"
    chimera-chroot "$INSTALL_ROOT" /bin/sh -c "apk add linux-lts"
    
    # Generate fstab
    printf "${BLUE}Generowanie /etc/fstab...${NC}\n"
    genfstab "$INSTALL_ROOT" > "$INSTALL_ROOT/etc/fstab.new"
    
    # Clean up fstab - remove problematic options and fix read-only issues
    printf "${BLUE}Czyszczenie i poprawianie fstab...${NC}\n"
    {
        printf "# Chimera Linux fstab - generated by installer\n"
        printf "# <file system> <mount point> <type> <options> <dump> <pass>\n"
        
        # Add root partition
        ROOT_UUID=$(lsblk -no UUID "$ROOT_PARTITION" 2>/dev/null || echo "")
        if [ -n "$ROOT_UUID" ]; then
            printf "UUID=%s / f2fs defaults 0 1\n" "$ROOT_UUID"
        else
            printf "%s / f2fs defaults 0 1\n" "$ROOT_PARTITION"
        fi
        
        # Add EFI partition
        EFI_UUID=$(lsblk -no UUID "$EFI_PARTITION" 2>/dev/null || echo "")
        if [ -n "$EFI_UUID" ]; then
            printf "UUID=%s /boot vfat defaults,umask=0077 0 2\n" "$EFI_UUID"
        else
            printf "%s /boot vfat defaults,umask=0077 0 2\n" "$EFI_PARTITION"
        fi
        
    } > "$INSTALL_ROOT/etc/fstab"
    
    # Remove temporary fstab
    rm -f "$INSTALL_ROOT/etc/fstab.new"
    
    # Set root password
    printf "${BLUE}Ustawianie hasła root...${NC}\n"
    printf "${YELLOW}Ustaw hasło dla konta root:${NC}\n"
    chimera-chroot "$INSTALL_ROOT" passwd root
    
    # Create regular user
    printf "${BLUE}Tworzenie konta użytkownika...${NC}\n"
    printf "Podaj nazwę użytkownika: "
    read username
    
    if [ -n "$username" ]; then
        printf "${BLUE}Tworzenie użytkownika: %s${NC}\n" "$username"
        if ! chimera-chroot "$INSTALL_ROOT" /bin/sh -c "adduser -s /bin/sh '$username'"; then
            chimera-chroot "$INSTALL_ROOT" /bin/sh -c "adduser -D -s /bin/sh '$username'"
        fi
        
        # Add user to basic groups (audio, video, netdev)
        if ! chimera-chroot "$INSTALL_ROOT" /bin/sh -c "addgroup '$username' audio 2>/dev/null"; then
            chimera-chroot "$INSTALL_ROOT" /bin/sh -c "adduser '$username' audio 2>/dev/null" || true
        fi
        
        if ! chimera-chroot "$INSTALL_ROOT" /bin/sh -c "addgroup '$username' video 2>/dev/null"; then
            chimera-chroot "$INSTALL_ROOT" /bin/sh -c "adduser '$username' video 2>/dev/null" || true
        fi
        
        if ! chimera-chroot "$INSTALL_ROOT" /bin/sh -c "addgroup '$username' netdev 2>/dev/null"; then
            chimera-chroot "$INSTALL_ROOT" /bin/sh -c "adduser '$username' netdev 2>/dev/null" || true
        fi
        
        printf "${YELLOW}Ustaw hasło dla użytkownika %s:${NC}\n" "$username"
        chimera-chroot "$INSTALL_ROOT" passwd "$username"
        
        printf "${GREEN}Użytkownik %s utworzony${NC}\n" "$username"
        printf "${YELLOW}Uwaga: Użytkownik nie ma uprawnień sudo - tylko konto root${NC}\n"
    else
        printf "${YELLOW}Pominięto tworzenie użytkownika${NC}\n"
    fi
    
    # Create initramfs
    printf "${BLUE}Tworzenie initramfs...${NC}\n"
    chimera-chroot "$INSTALL_ROOT" /bin/sh -c "update-initramfs -c -k all"
    
    printf "${GREEN}Konfiguracja systemu zakończona${NC}\n"
}

# Install and configure systemd-boot
install_bootloader() {
    show_header
    printf "${WHITE}INSTALACJA SYSTEMD-BOOT...${NC}\n"
    printf "\n"
    
    # Install systemd-boot package
    printf "${BLUE}Instalacja pakietu systemd-boot...${NC}\n"
    chimera-chroot "$INSTALL_ROOT" /bin/sh -c "apk add systemd-boot"
    
    # Install bootloader
    printf "${BLUE}Instalacja bootloadera...${NC}\n"
    chimera-chroot "$INSTALL_ROOT" /bin/sh -c "bootctl install"
    
    # Configure loader
    printf "${BLUE}Konfiguracja bootloadera...${NC}\n"
    cat > "$INSTALL_ROOT/boot/loader/loader.conf" << 'EOF'
default chimera.conf
timeout 5
console-mode max
editor no
EOF
    
    # Generate boot entries
    printf "${BLUE}Generowanie wpisów bootowania...${NC}\n"
    chimera-chroot "$INSTALL_ROOT" /bin/sh -c "gen-systemd-boot"
    
    printf "${GREEN}systemd-boot zainstalowany i skonfigurowany${NC}\n"
}

# Show installation summary
show_summary() {
    show_header
    printf "${GREEN}╔══════════════════════════════════════════════════════╗${NC}\n"
    printf "${GREEN}║             INSTALACJA ZAKOŃCZONA POMYŚLNIE          ║${NC}\n"
    printf "${GREEN}╚══════════════════════════════════════════════════════╝${NC}\n"
    printf "\n"
    printf "${WHITE}PODSUMOWANIE INSTALACJI:${NC}\n"
    printf "  • Dysk: %s\n" "$SELECTED_DISK"
    printf "  • EFI: %s -> /boot\n" "$EFI_PARTITION"
    printf "  • Root: %s -> /\n" "$ROOT_PARTITION"
    if [ "$INSTALLATION_TYPE" = "local" ]; then
        printf "  • Typ instalacji: lokalna\n"
    else
        printf "  • Typ instalacji: sieciowa\n"
    fi
    printf "  • Bootloader: systemd-boot\n"
    printf "  • System plików: f2fs (root), FAT32 (EFI)\n"
    printf "\n"
    printf "${WHITE}NASTĘPNE KROKI:${NC}\n"
    printf "  1. Wyloguj się z chroot (jeśli jesteś w nim)\n"
    printf "  2. Odmontuj partycje: umount -R %s\n" "$INSTALL_ROOT"
    printf "  3. Uruchom ponownie system\n"
    printf "  4. Usuń nośnik instalacyjny i uruchom z dysku\n"
    printf "  5. Zaloguj się jako root lub utworzony użytkownik\n"
    printf "  6. Sprawdź czy system się uruchamia poprawnie\n"
    printf "\n"
    printf "${CYAN}Dokumentacja konfiguracji:${NC}\n"
    printf "  https://chimera-linux.org/docs/configuration/post-installation\n"
    printf "\n"
    printf "Naciśnij Enter aby zakończyć..."
    read dummy
}

# Cleanup on exit
cleanup() {
    printf "${YELLOW}Odmontowywanie partycji...${NC}\n"
    umount -R "$INSTALL_ROOT" 2>/dev/null || true
    rm -f "/tmp/chimera_disks.$$" 2>/dev/null || true
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
            printf "${GREEN}Używanie aktualnego układu partycji${NC}\n"
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
main "$@" | grep -v '^System Volume Information

# Select installation type
select_installation_type() {
    show_header
    printf "${WHITE}WYBÓR TYPU INSTALACJI:${NC}\n"
    printf "\n"
    printf "1) ${GREEN}Instalacja lokalna${NC} - kopiuje aktualny system live\n"
    printf "2) ${GREEN}Instalacja sieciowa${NC} - pobiera najnowsze pakiety z repozytorium\n"
    printf "\n"
    printf "${CYAN}Instalacja lokalna:${NC} szybsza, używa aktualnego systemu live\n"
    printf "${CYAN}Instalacja sieciowa:${NC} zawsze najnowsze pakiety, wymaga internetu\n"
    printf "\n"
    
    while true; do
        printf "Wybierz typ instalacji (1-2): "
        read choice
        case "$choice" in
            1) INSTALLATION_TYPE="local"; break;;
            2) INSTALLATION_TYPE="network"; break;;
            *) printf "${RED}Nieprawidłowy wybór. Wybierz 1 lub 2.${NC}\n";;
        esac
    done
    
    if [ "$INSTALLATION_TYPE" = "local" ]; then
        printf "${GREEN}Wybrano: instalacja lokalna${NC}\n"
    else
        printf "${GREEN}Wybrano: instalacja sieciowa${NC}\n"
    fi
}

# Perform system installation
install_system() {
    show_header
    printf "${WHITE}INSTALACJA CHIMERA LINUX...${NC}\n"
    printf "\n"
    
    # Check if target directory has any files that would block installation
    if [ "$(find "$INSTALL_ROOT" -mindepth 1 -maxdepth 1 ! -name 'boot' ! -name 'lost+found' 2>/dev/null | wc -l)" -gt 0 ]; then
        printf "${YELLOW}Katalog instalacji zawiera pliki. Używanie flagi -f...${NC}\n"
        FORCE_FLAG="-f"
    else
        FORCE_FLAG=""
    fi
    
    if [ "$INSTALLATION_TYPE" = "local" ]; then
        printf "${BLUE}Wykonywanie instalacji lokalnej...${NC}\n"
        chimera-bootstrap -l $FORCE_FLAG "$INSTALL_ROOT"
    else
        printf "${BLUE}Wykonywanie instalacji sieciowej...${NC}\n"
        chimera-bootstrap $FORCE_FLAG "$INSTALL_ROOT"
    fi
    
    printf "${GREEN}Instalacja systemu zakończona${NC}\n"
}

# Configure system in chroot
configure_system() {
    show_header
    printf "${WHITE}KONFIGURACJA SYSTEMU...${NC}\n"
    printf "\n"
    
    # Update system
    printf "${BLUE}Aktualizacja systemu...${NC}\n"
    chimera-chroot "$INSTALL_ROOT" /bin/sh -c "
        apk update
        apk upgrade --available || (apk fix && apk upgrade --available)
    "
    
    # Remove base-live if local installation
    if [ "$INSTALLATION_TYPE" = "local" ]; then
        printf "${BLUE}Usuwanie pakietu base-live...${NC}\n"
        chimera-chroot "$INSTALL_ROOT" /bin/sh -c "apk del base-live" || true
    fi
    
    # Install kernel
    printf "${BLUE}Instalacja kernela...${NC}\n"
    chimera-chroot "$INSTALL_ROOT" /bin/sh -c "apk add linux-lts"
    
    # Generate fstab
    printf "${BLUE}Generowanie /etc/fstab...${NC}\n"
    genfstab "$INSTALL_ROOT" > "$INSTALL_ROOT/etc/fstab.new"
    
    # Clean up fstab - remove problematic options and fix read-only issues
    printf "${BLUE}Czyszczenie i poprawianie fstab...${NC}\n"
    {
        printf "# Chimera Linux fstab - generated by installer\n"
        printf "# <file system> <mount point> <type> <options> <dump> <pass>\n"
        
        # Add root partition
        ROOT_UUID=$(lsblk -no UUID "$ROOT_PARTITION" 2>/dev/null || echo "")
        if [ -n "$ROOT_UUID" ]; then
            printf "UUID=%s / f2fs defaults 0 1\n" "$ROOT_UUID"
        else
            printf "%s / f2fs defaults 0 1\n" "$ROOT_PARTITION"
        fi
        
        # Add EFI partition
        EFI_UUID=$(lsblk -no UUID "$EFI_PARTITION" 2>/dev/null || echo "")
        if [ -n "$EFI_UUID" ]; then
            printf "UUID=%s /boot vfat defaults,umask=0077 0 2\n" "$EFI_UUID"
        else
            printf "%s /boot vfat defaults,umask=0077 0 2\n" "$EFI_PARTITION"
        fi
        
    } > "$INSTALL_ROOT/etc/fstab"
    
    # Remove temporary fstab
    rm -f "$INSTALL_ROOT/etc/fstab.new"
    
    # Set root password
    printf "${BLUE}Ustawianie hasła root...${NC}\n"
    printf "${YELLOW}Ustaw hasło dla konta root:${NC}\n"
    chimera-chroot "$INSTALL_ROOT" passwd root
    
    # Create regular user
    printf "${BLUE}Tworzenie konta użytkownika...${NC}\n"
    printf "Podaj nazwę użytkownika: "
    read username
    
    if [ -n "$username" ]; then
        printf "${BLUE}Tworzenie użytkownika: %s${NC}\n" "$username"
        chimera-chroot "$INSTALL_ROOT" /bin/sh -c "
            adduser -s /bin/sh '$username' || adduser -D -s /bin/sh '$username'
            addgroup '$username' wheel 2>/dev/null || adduser '$username' wheel 2>/dev/null || true
            addgroup '$username' audio 2>/dev/null || adduser '$username' audio 2>/dev/null || true
            addgroup '$username' video 2>/dev/null || adduser '$username' video 2>/dev/null || true
            addgroup '$username' netdev 2>/dev/null || adduser '$username' netdev 2>/dev/null || true
        "
        
        printf "${YELLOW}Ustaw hasło dla użytkownika %s:${NC}\n" "$username"
        chimera-chroot "$INSTALL_ROOT" passwd "$username"
        
        # Configure sudo/doas for wheel group
        printf "${BLUE}Konfiguracja sudo dla grupy wheel...${NC}\n"
        if chimera-chroot "$INSTALL_ROOT" /bin/sh -c "command -v doas" > /dev/null 2>&1; then
            # Use doas if available
            printf "permit :wheel\n" > "$INSTALL_ROOT/etc/doas.conf"
            chmod 644 "$INSTALL_ROOT/etc/doas.conf"
        elif chimera-chroot "$INSTALL_ROOT" /bin/sh -c "command -v sudo" > /dev/null 2>&1; then
            # Enable sudo for wheel group
            chimera-chroot "$INSTALL_ROOT" /bin/sh -c "
                sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers 2>/dev/null || 
                echo '%wheel ALL=(ALL:ALL) ALL' >> /etc/sudoers
            "
        fi
        
        printf "${GREEN}Użytkownik %s utworzony i dodany do grupy wheel${NC}\n" "$username"
    else
        printf "${YELLOW}Pominięto tworzenie użytkownika${NC}\n"
    fi
    
    # Create initramfs
    printf "${BLUE}Tworzenie initramfs...${NC}\n"
    chimera-chroot "$INSTALL_ROOT" /bin/sh -c "update-initramfs -c -k all"
    
    printf "${GREEN}Konfiguracja systemu zakończona${NC}\n"
}

# Install and configure systemd-boot
install_bootloader() {
    show_header
    printf "${WHITE}INSTALACJA SYSTEMD-BOOT...${NC}\n"
    printf "\n"
    
    # Install systemd-boot package
    printf "${BLUE}Instalacja pakietu systemd-boot...${NC}\n"
    chimera-chroot "$INSTALL_ROOT" /bin/sh -c "apk add systemd-boot"
    
    # Install bootloader
    printf "${BLUE}Instalacja bootloadera...${NC}\n"
    chimera-chroot "$INSTALL_ROOT" /bin/sh -c "bootctl install"
    
    # Configure loader
    printf "${BLUE}Konfiguracja bootloadera...${NC}\n"
    cat > "$INSTALL_ROOT/boot/loader/loader.conf" << 'EOF'
default chimera.conf
timeout 5
console-mode max
editor no
EOF
    
    # Generate boot entries
    printf "${BLUE}Generowanie wpisów bootowania...${NC}\n"
    chimera-chroot "$INSTALL_ROOT" /bin/sh -c "gen-systemd-boot"
    
    printf "${GREEN}systemd-boot zainstalowany i skonfigurowany${NC}\n"
}

# Show installation summary
show_summary() {
    show_header
    printf "${GREEN}╔══════════════════════════════════════════════════════╗${NC}\n"
    printf "${GREEN}║             INSTALACJA ZAKOŃCZONA POMYŚLNIE          ║${NC}\n"
    printf "${GREEN}╚══════════════════════════════════════════════════════╝${NC}\n"
    printf "\n"
    printf "${WHITE}PODSUMOWANIE INSTALACJI:${NC}\n"
    printf "  • Dysk: %s\n" "$SELECTED_DISK"
    printf "  • EFI: %s -> /boot\n" "$EFI_PARTITION"
    printf "  • Root: %s -> /\n" "$ROOT_PARTITION"
    if [ "$INSTALLATION_TYPE" = "local" ]; then
        printf "  • Typ instalacji: lokalna\n"
    else
        printf "  • Typ instalacji: sieciowa\n"
    fi
    printf "  • Bootloader: systemd-boot\n"
    printf "  • System plików: f2fs (root), FAT32 (EFI)\n"
    printf "\n"
    printf "${WHITE}NASTĘPNE KROKI:${NC}\n"
    printf "  1. Wyloguj się z chroot (jeśli jesteś w nim)\n"
    printf "  2. Odmontuj partycje: umount -R %s\n" "$INSTALL_ROOT"
    printf "  3. Uruchom ponownie system\n"
    printf "  4. Usuń nośnik instalacyjny i uruchom z dysku\n"
    printf "  5. Zaloguj się jako root lub utworzony użytkownik\n"
    printf "  6. Sprawdź czy system się uruchamia poprawnie\n"
    printf "\n"
    printf "${CYAN}Dokumentacja konfiguracji:${NC}\n"
    printf "  https://chimera-linux.org/docs/configuration/post-installation\n"
    printf "\n"
    printf "Naciśnij Enter aby zakończyć..."
    read dummy
}

# Cleanup on exit
cleanup() {
    printf "${YELLOW}Odmontowywanie partycji...${NC}\n"
    umount -R "$INSTALL_ROOT" 2>/dev/null || true
    rm -f "/tmp/chimera_disks.$$" 2>/dev/null || true
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
            printf "${GREEN}Używanie aktualnego układu partycji${NC}\n"
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
main "$@")" ]; then
        printf "${BLUE}Czyszczenie partycji EFI...${NC}\n"
        # Remove everything except EFI directory and Windows stuff
        find "$INSTALL_ROOT/boot" -mindepth 1 -maxdepth 1 ! -name 'EFI' ! -name 'System*' -exec rm -rf {} \; 2>/dev/null || true
    fi
    
    printf "${GREEN}Partycje zamontowane i wyczyszczone w %s${NC}\n" "$INSTALL_ROOT"
}

# Select installation type
select_installation_type() {
    show_header
    printf "${WHITE}WYBÓR TYPU INSTALACJI:${NC}\n"
    printf "\n"
    printf "1) ${GREEN}Instalacja lokalna${NC} - kopiuje aktualny system live\n"
    printf "2) ${GREEN}Instalacja sieciowa${NC} - pobiera najnowsze pakiety z repozytorium\n"
    printf "\n"
    printf "${CYAN}Instalacja lokalna:${NC} szybsza, używa aktualnego systemu live\n"
    printf "${CYAN}Instalacja sieciowa:${NC} zawsze najnowsze pakiety, wymaga internetu\n"
    printf "\n"
    
    while true; do
        printf "Wybierz typ instalacji (1-2): "
        read choice
        case "$choice" in
            1) INSTALLATION_TYPE="local"; break;;
            2) INSTALLATION_TYPE="network"; break;;
            *) printf "${RED}Nieprawidłowy wybór. Wybierz 1 lub 2.${NC}\n";;
        esac
    done
    
    if [ "$INSTALLATION_TYPE" = "local" ]; then
        printf "${GREEN}Wybrano: instalacja lokalna${NC}\n"
    else
        printf "${GREEN}Wybrano: instalacja sieciowa${NC}\n"
    fi
}

# Perform system installation
install_system() {
    show_header
    printf "${WHITE}INSTALACJA CHIMERA LINUX...${NC}\n"
    printf "\n"
    
    # Check if target directory has any files that would block installation
    if [ "$(find "$INSTALL_ROOT" -mindepth 1 -maxdepth 1 ! -name 'boot' ! -name 'lost+found' 2>/dev/null | wc -l)" -gt 0 ]; then
        printf "${YELLOW}Katalog instalacji zawiera pliki. Używanie flagi -f...${NC}\n"
        FORCE_FLAG="-f"
    else
        FORCE_FLAG=""
    fi
    
    if [ "$INSTALLATION_TYPE" = "local" ]; then
        printf "${BLUE}Wykonywanie instalacji lokalnej...${NC}\n"
        chimera-bootstrap -l $FORCE_FLAG "$INSTALL_ROOT"
    else
        printf "${BLUE}Wykonywanie instalacji sieciowej...${NC}\n"
        chimera-bootstrap $FORCE_FLAG "$INSTALL_ROOT"
    fi
    
    printf "${GREEN}Instalacja systemu zakończona${NC}\n"
}

# Configure system in chroot
configure_system() {
    show_header
    printf "${WHITE}KONFIGURACJA SYSTEMU...${NC}\n"
    printf "\n"
    
    # Update system
    printf "${BLUE}Aktualizacja systemu...${NC}\n"
    chimera-chroot "$INSTALL_ROOT" /bin/sh -c "
        apk update
        apk upgrade --available || (apk fix && apk upgrade --available)
    "
    
    # Remove base-live if local installation
    if [ "$INSTALLATION_TYPE" = "local" ]; then
        printf "${BLUE}Usuwanie pakietu base-live...${NC}\n"
        chimera-chroot "$INSTALL_ROOT" /bin/sh -c "apk del base-live" || true
    fi
    
    # Install kernel
    printf "${BLUE}Instalacja kernela...${NC}\n"
    chimera-chroot "$INSTALL_ROOT" /bin/sh -c "apk add linux-lts"
    
    # Generate fstab
    printf "${BLUE}Generowanie /etc/fstab...${NC}\n"
    genfstab "$INSTALL_ROOT" > "$INSTALL_ROOT/etc/fstab.new"
    
    # Clean up fstab - remove problematic options and fix read-only issues
    printf "${BLUE}Czyszczenie i poprawianie fstab...${NC}\n"
    {
        printf "# Chimera Linux fstab - generated by installer\n"
        printf "# <file system> <mount point> <type> <options> <dump> <pass>\n"
        
        # Add root partition
        ROOT_UUID=$(lsblk -no UUID "$ROOT_PARTITION" 2>/dev/null || echo "")
        if [ -n "$ROOT_UUID" ]; then
            printf "UUID=%s / f2fs defaults 0 1\n" "$ROOT_UUID"
        else
            printf "%s / f2fs defaults 0 1\n" "$ROOT_PARTITION"
        fi
        
        # Add EFI partition
        EFI_UUID=$(lsblk -no UUID "$EFI_PARTITION" 2>/dev/null || echo "")
        if [ -n "$EFI_UUID" ]; then
            printf "UUID=%s /boot vfat defaults,umask=0077 0 2\n" "$EFI_UUID"
        else
            printf "%s /boot vfat defaults,umask=0077 0 2\n" "$EFI_PARTITION"
        fi
        
    } > "$INSTALL_ROOT/etc/fstab"
    
    # Remove temporary fstab
    rm -f "$INSTALL_ROOT/etc/fstab.new"
    
    # Set root password
    printf "${BLUE}Ustawianie hasła root...${NC}\n"
    printf "${YELLOW}Ustaw hasło dla konta root:${NC}\n"
    chimera-chroot "$INSTALL_ROOT" passwd root
    
    # Create regular user
    printf "${BLUE}Tworzenie konta użytkownika...${NC}\n"
    printf "Podaj nazwę użytkownika: "
    read username
    
    if [ -n "$username" ]; then
        printf "${BLUE}Tworzenie użytkownika: %s${NC}\n" "$username"
        chimera-chroot "$INSTALL_ROOT" /bin/sh -c "
            adduser -s /bin/sh '$username' || adduser -D -s /bin/sh '$username'
            addgroup '$username' wheel 2>/dev/null || adduser '$username' wheel 2>/dev/null || true
            addgroup '$username' audio 2>/dev/null || adduser '$username' audio 2>/dev/null || true
            addgroup '$username' video 2>/dev/null || adduser '$username' video 2>/dev/null || true
            addgroup '$username' netdev 2>/dev/null || adduser '$username' netdev 2>/dev/null || true
        "
        
        printf "${YELLOW}Ustaw hasło dla użytkownika %s:${NC}\n" "$username"
        chimera-chroot "$INSTALL_ROOT" passwd "$username"
        
        # Configure sudo/doas for wheel group
        printf "${BLUE}Konfiguracja sudo dla grupy wheel...${NC}\n"
        if chimera-chroot "$INSTALL_ROOT" /bin/sh -c "command -v doas" > /dev/null 2>&1; then
            # Use doas if available
            printf "permit :wheel\n" > "$INSTALL_ROOT/etc/doas.conf"
            chmod 644 "$INSTALL_ROOT/etc/doas.conf"
        elif chimera-chroot "$INSTALL_ROOT" /bin/sh -c "command -v sudo" > /dev/null 2>&1; then
            # Enable sudo for wheel group
            chimera-chroot "$INSTALL_ROOT" /bin/sh -c "
                sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers 2>/dev/null || 
                echo '%wheel ALL=(ALL:ALL) ALL' >> /etc/sudoers
            "
        fi
        
        printf "${GREEN}Użytkownik %s utworzony i dodany do grupy wheel${NC}\n" "$username"
    else
        printf "${YELLOW}Pominięto tworzenie użytkownika${NC}\n"
    fi
    
    # Create initramfs
    printf "${BLUE}Tworzenie initramfs...${NC}\n"
    chimera-chroot "$INSTALL_ROOT" /bin/sh -c "update-initramfs -c -k all"
    
    printf "${GREEN}Konfiguracja systemu zakończona${NC}\n"
}

# Install and configure systemd-boot
install_bootloader() {
    show_header
    printf "${WHITE}INSTALACJA SYSTEMD-BOOT...${NC}\n"
    printf "\n"
    
    # Install systemd-boot package
    printf "${BLUE}Instalacja pakietu systemd-boot...${NC}\n"
    chimera-chroot "$INSTALL_ROOT" /bin/sh -c "apk add systemd-boot"
    
    # Install bootloader
    printf "${BLUE}Instalacja bootloadera...${NC}\n"
    chimera-chroot "$INSTALL_ROOT" /bin/sh -c "bootctl install"
    
    # Configure loader
    printf "${BLUE}Konfiguracja bootloadera...${NC}\n"
    cat > "$INSTALL_ROOT/boot/loader/loader.conf" << 'EOF'
default chimera.conf
timeout 5
console-mode max
editor no
EOF
    
    # Generate boot entries
    printf "${BLUE}Generowanie wpisów bootowania...${NC}\n"
    chimera-chroot "$INSTALL_ROOT" /bin/sh -c "gen-systemd-boot"
    
    printf "${GREEN}systemd-boot zainstalowany i skonfigurowany${NC}\n"
}

# Show installation summary
show_summary() {
    show_header
    printf "${GREEN}╔══════════════════════════════════════════════════════╗${NC}\n"
    printf "${GREEN}║             INSTALACJA ZAKOŃCZONA POMYŚLNIE          ║${NC}\n"
    printf "${GREEN}╚══════════════════════════════════════════════════════╝${NC}\n"
    printf "\n"
    printf "${WHITE}PODSUMOWANIE INSTALACJI:${NC}\n"
    printf "  • Dysk: %s\n" "$SELECTED_DISK"
    printf "  • EFI: %s -> /boot\n" "$EFI_PARTITION"
    printf "  • Root: %s -> /\n" "$ROOT_PARTITION"
    if [ "$INSTALLATION_TYPE" = "local" ]; then
        printf "  • Typ instalacji: lokalna\n"
    else
        printf "  • Typ instalacji: sieciowa\n"
    fi
    printf "  • Bootloader: systemd-boot\n"
    printf "  • System plików: f2fs (root), FAT32 (EFI)\n"
    printf "\n"
    printf "${WHITE}NASTĘPNE KROKI:${NC}\n"
    printf "  1. Wyloguj się z chroot (jeśli jesteś w nim)\n"
    printf "  2. Odmontuj partycje: umount -R %s\n" "$INSTALL_ROOT"
    printf "  3. Uruchom ponownie system\n"
    printf "  4. Usuń nośnik instalacyjny i uruchom z dysku\n"
    printf "  5. Zaloguj się jako root lub utworzony użytkownik\n"
    printf "  6. Sprawdź czy system się uruchamia poprawnie\n"
    printf "\n"
    printf "${CYAN}Dokumentacja konfiguracji:${NC}\n"
    printf "  https://chimera-linux.org/docs/configuration/post-installation\n"
    printf "\n"
    printf "Naciśnij Enter aby zakończyć..."
    read dummy
}

# Cleanup on exit
cleanup() {
    printf "${YELLOW}Odmontowywanie partycji...${NC}\n"
    umount -R "$INSTALL_ROOT" 2>/dev/null || true
    rm -f "/tmp/chimera_disks.$$" 2>/dev/null || true
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
            printf "${GREEN}Używanie aktualnego układu partycji${NC}\n"
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
