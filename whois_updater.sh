#!/usr/bin/env bash
# =============================================================================
# Script Name : whois_updater.sh
# Description : Sync Whois "descr" field with Billing DB switch names.
# Usage       : ./whois_updater.sh <renamed_switch_name>
# Author      : syr4ok (Andrii)
# Version     : 1.0.1r
# =============================================================================

# --- Configuration Loader ---
CONFIG_FILE="$(dirname "$0")/whois_updater.conf"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "Error: Configuration file not found. Create whois_updater.conf from example."
    exit 1
fi

# --- Environment & Tools ---
DATE_NOW=$(date +%Y%m%d)
PSQL_PATH=$(which psql)
MAIL_PATH=$(which mail)
WHOIS_PATH=$(which whois)

# Ensure target switch name is provided
RENAMED_SWITCH_NAME=$1
if [ -z "$RENAMED_SWITCH_NAME" ]; then
    echo "Usage: $0 <new_switch_name>"
    exit 1
fi

# Logging setup
LOG_FILE="${LOG_DIR}/whois_updater.${DATE_NOW}.log"
LOG_SEP="========================================================="
mkdir -p "$LOG_DIR"

log_message() {
    local level="$1"
    local msg="$2"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [${level}] ${msg}" >> "${LOG_FILE}"
}

# --- Dependencies Check ---
for tool in "$PSQL_PATH" "$MAIL_PATH" "$WHOIS_PATH"; do
    if [ -z "$tool" ]; then
        log_message "ERROR" "Missing dependency. Check if psql, mail, and whois are installed."
        exit 1
    fi
done

log_message "INFO" "Script STARTED for switch: ${RENAMED_SWITCH_NAME}"

# --- Data Acquisition ---
log_message "INFO" "Querying IP list from PostgreSQL..."
IP_LIST=$($PSQL_PATH -t -U "$PSQL_USER" -d "$PSQL_DB" -c \
"SELECT ip FROM equipment_ports WHERE equipment_id = (SELECT id FROM equipment WHERE name='${RENAMED_SWITCH_NAME}') AND ip <> ''" 2>>"${LOG_FILE}")

if [ -z "$IP_LIST" ]; then
    log_message "WARN" "No IP addresses found for switch ${RENAMED_SWITCH_NAME}. Exiting."
    exit 0
fi

# --- Processing Cycle ---
for ip in $IP_LIST; do
    ip=$(echo "$ip" | tr -d '[:space:]')
    log_message "INFO" "Processing IP: ${ip}"

    # Fetch current Whois record
    CURRENT_DATA=$($WHOIS_PATH -r -h "$WHOIS_SERVER" "$ip" 2>>"${LOG_FILE}")
    if [ -z "$CURRENT_DATA" ]; then
        log_message "ERROR" "Empty Whois response for ${ip}. Skipping."
        continue
    fi

    # Parse 'descr' field
    OLD_DESCR_LINE=$(printf "%s\n" "$CURRENT_DATA" | awk 'BEGIN{IGNORECASE=1} /^descr:/ {print; exit}')
    if [ -z "$OLD_DESCR_LINE" ]; then
        log_message "WARN" "No 'descr' field found for ${ip}. Skipping."
        continue
    fi

    # Extract switch name from current description
    DESCR_VALUE=$(printf "%s" "${OLD_DESCR_LINE#*:}" | sed 's/^[[:space:]]*//')
    OLD_SWITCH_NAME=$(printf "%s\n" "$DESCR_VALUE" | grep -oE '(des[0-9][A-Za-z0-9-]*|dgs[A-Za-z0-9-]*|dlink[A-Za-z0-9-]*|cat[A-Za-z0-9-]*|zte[A-Za-z0-9-]*|dir[A-Za-z0-9-]*|ubi[A-Za-z0-9-]*)' | tail -1)

    if [ -z "$OLD_SWITCH_NAME" ]; then
        log_message "WARN" "Could not identify old switch pattern in: $DESCR_VALUE. Skipping."
        continue
    fi

    # Generate new description using Perl for safe regex handling
    NEW_DESCR=$(o="$OLD_SWITCH_NAME" n="$RENAMED_SWITCH_NAME" perl -pe 'BEGIN{$o=$ENV{o};$n=$ENV{n}} s/\Q$o\E/$n/g' <<<"$DESCR_VALUE")
    log_message "INFO" "Updating: [${OLD_SWITCH_NAME}] -> [${RENAMED_SWITCH_NAME}]"

    # --- Email Construction ---
    # Using 'grep -m 1' for efficiency
    MAIL_BODY=$(cat <<EOF
inetnum:  $(printf "%s\n" "$CURRENT_DATA" | grep -m 1 "inetnum:" | awk '{print $2, "-", $4}')
netname:  $(printf "%s\n" "$CURRENT_DATA" | grep -m 1 "netname:" | awk '{print $2}')
descr:    ${NEW_DESCR}
country:  $(printf "%s\n" "$CURRENT_DATA" | grep -m 1 "country:" | awk '{print $2}')
admin-c:  $(printf "%s\n" "$CURRENT_DATA" | grep -m 1 "admin-c:" | awk '{print $2}')
tech-c:   $(printf "%s\n" "$CURRENT_DATA" | grep -m 1 "tech-c:" | awk '{print $2}')
source:   $(printf "%s\n" "$CURRENT_DATA" | grep -m 1 "source:" | awk '{print $2}')
changed:  ${CHANGED_EMAIL}
password: ${WHOIS_PASS}
EOF
)

    # --- Delivery ---
    if echo "$MAIL_BODY" | $MAIL_PATH -s "Whois Update: ${ip}" "$MAIL_RECIPIENT"; then
        log_message "INFO" "Email sent successfully for ${ip}."
    else
        log_message "ERROR" "Failed to send email for ${ip}."
    fi

    sleep 2 # Anti-spam delay
done

log_message "INFO" "Script FINISHED successfully."
echo -e "$LOG_SEP" >> "$LOG_FILE"
exit 0
