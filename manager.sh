#!/usr/bin/env bash
# Khalifeh Tunnel Manager

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# Paths
BASE_DIR="/opt/khalifeh"
PROFILES_DIR="$BASE_DIR/profiles"
LOG_DIR="$BASE_DIR/logs"
PYTHON_SCRIPT="$BASE_DIR/khalifeh.py"

# Functions
list_profiles() {
    echo ""
    if [ -z "$(ls -A $PROFILES_DIR 2>/dev/null)" ]; then
        echo -e "${YELLOW}No profiles found. Create one first.${NC}"
        return 1
    fi
    
    local i=1
    for f in $PROFILES_DIR/*.conf; do
        if [ -f "$f" ]; then
            local name=$(grep "^name=" "$f" | cut -d'=' -f2)
            local mode=$(grep "^mode=" "$f" | cut -d'=' -f2)
            if pgrep -f "khalifeh.py.*$f" > /dev/null; then
                echo -e "  ${GREEN}[RUNNING]${NC} $i) $name ($mode)"
            else
                echo -e "  ${YELLOW}[STOPPED]${NC} $i) $name ($mode)"
            fi
            ((i++))
        fi
    done
    return 0
}

create_profile() {
    echo ""
    echo -e "${CYAN}Create New Profile${NC}"
    echo "-------------------"
    
    read -p "Profile name: " name
    if [ -z "$name" ]; then
        echo -e "${RED}Name required!${NC}"
        return
    fi
    
    echo ""
    echo "1) Server Mode (Iran)"
    echo "2) Client Mode (EU)"
    read -p "Choose mode (1/2): " mode_choice
    
    local filename="$PROFILES_DIR/$(echo "$name" | tr ' ' '_').conf"
    
    if [ "$mode_choice" == "1" ]; then
        read -p "Bridge port [7000]: " bridge
        bridge=${bridge:-7000}
        read -p "Sync port [7001]: " sync
        sync=${sync:-7001}
        read -p "Auto sync? (y/n) [y]: " auto
        auto=${auto:-y}
        
        if [ "$auto" == "n" ]; then
            read -p "Ports (comma separated, e.g., 80,443): " ports
        else
            ports=""
        fi
        
        cat > "$filename" << EOF
name=$name
mode=server
bridge_port=$bridge
sync_port=$sync
auto_sync=$auto
ports=$ports
exclude_ports=22,53,80,443,2096,9876,11111
EOF
    else
        read -p "Iran server IP: " iran_ip
        if [ -z "$iran_ip" ]; then
            echo -e "${RED}IP required!${NC}"
            return
        fi
        read -p "Bridge port [7000]: " bridge
        bridge=${bridge:-7000}
        read -p "Sync port [7001]: " sync
        sync=${sync:-7001}
        
        cat > "$filename" << EOF
name=$name
mode=client
iran_ip=$iran_ip
bridge_port=$bridge
sync_port=$sync
exclude_ports=22,53,80,443,2096,9876,11111
EOF
    fi
    
    echo -e "${GREEN}Profile '$name' created!${NC}"
}

edit_profile() {
    local profile=$1
    local file="$PROFILES_DIR/$profile"
    
    if [ ! -f "$file" ]; then
        echo -e "${RED}Profile not found!${NC}"
        return
    fi
    
    nano "$file"
    echo -e "${GREEN}Profile updated!${NC}"
}

delete_profile() {
    local profile=$1
    local file="$PROFILES_DIR/$profile"
    
    if [ ! -f "$file" ]; then
        echo -e "${RED}Profile not found!${NC}"
        return
    fi
    
    # Stop if running
    pkill -f "khalifeh.py.*$file" 2>/dev/null || true
    
    rm -f "$file"
    echo -e "${GREEN}Profile deleted!${NC}"
}

run_profile() {
    local profile=$1
    local file="$PROFILES_DIR/$profile"
    
    if [ ! -f "$file" ]; then
        echo -e "${RED}Profile not found!${NC}"
        return
    fi
    
    # Stop existing instance for this profile
    pkill -f "khalifeh.py.*$file" 2>/dev/null || true
    sleep 1
    
    # Run in background with screen
    screen -dmS "khalifeh_$profile" bash -c "python3 $PYTHON_SCRIPT --profile $file 2>&1 | tee $LOG_DIR/${profile}.log"
    
    echo -e "${GREEN}Profile started!${NC}"
    echo "View logs: screen -r khalifeh_$profile"
}

stop_profile() {
    local profile=$1
    pkill -f "khalifeh.py.*$profile" 2>/dev/null || true
    echo -e "${GREEN}Profile stopped!${NC}"
}

show_logs() {
    local profile=$1
    if [ -f "$LOG_DIR/${profile}.log" ]; then
        tail -f "$LOG_DIR/${profile}.log"
    else
        echo -e "${YELLOW}No logs found${NC}"
    fi
}

manage_exclude_ports() {
    echo ""
    echo -e "${CYAN}Manage Excluded Ports (Global)${NC}"
    echo "--------------------------------"
    
    local exclude_file="$BASE_DIR/exclude_ports.txt"
    if [ ! -f "$exclude_file" ]; then
        echo "22,53,80,443,2096,9876,11111" > "$exclude_file"
    fi
    
    local current=$(cat "$exclude_file")
    echo -e "Current excluded ports: ${GREEN}$current${NC}"
    echo ""
    echo "1) Add port"
    echo "2) Remove port"
    echo "3) Back"
    read -p "Choose: " excl_choice
    
    if [ "$excl_choice" == "1" ]; then
        read -p "Port to add: " new_port
        if [[ "$new_port" =~ ^[0-9]+$ ]]; then
            if echo "$current" | grep -q "$new_port"; then
                echo -e "${YELLOW}Port already excluded${NC}"
            else
                echo "$current,$new_port" > "$exclude_file"
                echo -e "${GREEN}Port $new_port added${NC}"
            fi
        fi
    elif [ "$excl_choice" == "2" ]; then
        read -p "Port to remove: " del_port
        local new_list=$(echo "$current" | sed "s/,$del_port//g" | sed "s/$del_port,//g" | sed "s/$del_port//g")
        echo "$new_list" > "$exclude_file"
        echo -e "${GREEN}Port $del_port removed${NC}"
    fi
}

# Main menu
while true; do
    clear
    echo ""
    echo "========================================="
    echo "   Khalifeh Tunnel Manager v2.0"
    echo "========================================="
    echo ""
    echo "  PROFILES:"
    echo "  ---------"
    
    if [ -z "$(ls -A $PROFILES_DIR 2>/dev/null)" ]; then
        echo -e "  ${YELLOW}No profiles yet${NC}"
    else
        local i=1
        declare -a PROFILE_LIST
        PROFILE_LIST=()
        for f in $PROFILES_DIR/*.conf; do
            if [ -f "$f" ]; then
                local name=$(grep "^name=" "$f" | cut -d'=' -f2)
                local mode=$(grep "^mode=" "$f" | cut -d'=' -f2)
                local status="STOPPED"
                if pgrep -f "khalifeh.py.*$f" > /dev/null; then
                    status="RUNNING"
                    echo -e "  ${GREEN}[$status]${NC} $i) $name ($mode)"
                else
                    echo -e "  ${YELLOW}[$status]${NC} $i) $name ($mode)"
                fi
                PROFILE_LIST+=("$(basename "$f")")
                ((i++))
            fi
        done
    fi
    
    echo ""
    echo "  OPTIONS:"
    echo "  --------"
    echo "  N) Create new profile"
    echo "  E) Edit profile"
    echo "  D) Delete profile"
    echo "  R) Run profile"
    echo "  S) Stop profile"
    echo "  L) View logs"
    echo "  X) Manage excluded ports"
    echo "  U) Uninstall"
    echo "  Q) Quit"
    echo ""
    read -p "  Choose: " choice
    
    case $choice in
        [0-9]*)
            if [ "$choice" -ge 1 ] && [ "$choice" -le ${#PROFILE_LIST[@]} ]; then
                local idx=$((choice-1))
                local prof_file="${PROFILE_LIST[$idx]}"
                echo ""
                echo "1) Run"
                echo "2) Stop"
                echo "3) Edit"
                echo "4) Delete"
                echo "5) Logs"
                read -p "Action: " action
                case $action in
                    1) run_profile "$prof_file" ;;
                    2) stop_profile "$prof_file" ;;
                    3) edit_profile "$prof_file" ;;
                    4) delete_profile "$prof_file" ;;
                    5) show_logs "$prof_file" ;;
                esac
            fi
            ;;
        [Nn]) create_profile ;;
        [Ee]) 
            if [ ${#PROFILE_LIST[@]} -gt 0 ]; then
                read -p "Profile number: " pnum
                if [ "$pnum" -ge 1 ] && [ "$pnum" -le ${#PROFILE_LIST[@]} ]; then
                    edit_profile "${PROFILE_LIST[$((pnum-1))]}"
                fi
            else
                echo -e "${RED}No profiles${NC}"
                sleep 1
            fi
            ;;
        [Dd])
            if [ ${#PROFILE_LIST[@]} -gt 0 ]; then
                read -p "Profile number: " pnum
                if [ "$pnum" -ge 1 ] && [ "$pnum" -le ${#PROFILE_LIST[@]} ]; then
                    delete_profile "${PROFILE_LIST[$((pnum-1))]}"
                fi
            else
                echo -e "${RED}No profiles${NC}"
                sleep 1
            fi
            ;;
        [Rr])
            if [ ${#PROFILE_LIST[@]} -gt 0 ]; then
                read -p "Profile number: " pnum
                if [ "$pnum" -ge 1 ] && [ "$pnum" -le ${#PROFILE_LIST[@]} ]; then
                    run_profile "${PROFILE_LIST[$((pnum-1))]}"
                fi
            else
                echo -e "${RED}No profiles${NC}"
                sleep 1
            fi
            ;;
        [Ss])
            if [ ${#PROFILE_LIST[@]} -gt 0 ]; then
                read -p "Profile number: " pnum
                if [ "$pnum" -ge 1 ] && [ "$pnum" -le ${#PROFILE_LIST[@]} ]; then
                    stop_profile "${PROFILE_LIST[$((pnum-1))]}"
                fi
            else
                echo -e "${RED}No profiles${NC}"
                sleep 1
            fi
            ;;
        [Ll])
            if [ ${#PROFILE_LIST[@]} -gt 0 ]; then
                read -p "Profile number: " pnum
                if [ "$pnum" -ge 1 ] && [ "$pnum" -le ${#PROFILE_LIST[@]} ]; then
                    show_logs "${PROFILE_LIST[$((pnum-1))]}"
                fi
            else
                echo -e "${RED}No profiles${NC}"
                sleep 1
            fi
            ;;
        [Xx]) manage_exclude_ports ;;
        [Uu])
            read -p "Uninstall Khalifeh Tunnel? (y/n): " confirm
            if [ "$confirm" == "y" ]; then
                pkill -f khalifeh.py 2>/dev/null || true
                rm -rf $BASE_DIR
                rm -f /usr/local/bin/khalifeh
                echo -e "${GREEN}Uninstalled${NC}"
                exit 0
            fi
            ;;
        [Qq]) exit 0 ;;
        *) echo -e "${RED}Invalid choice${NC}"; sleep 1 ;;
    esac
done