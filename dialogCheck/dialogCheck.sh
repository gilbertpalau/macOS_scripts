#!/bin/zsh --no-rcs
# shellcheck shell=bash
#
# dialogCheck - checks for / installs swiftDialog

# Confirm script is running as root
if [[ $(id -u) -ne 0 ]]; then
    echo "This script must be run as root; exiting."
    exit 1
fi

scriptVersion="v1.1"
scriptLog="/var/log/dialogCheck.log"
dialogBinary="/usr/local/bin/dialog"

# Team ID swiftDialog packages are signed with. Confirm this against a known-good
# release before relying on it (e.g. `spctl -a -vv -t install /path/to/Dialog.pkg`
# against a package you've verified out of band).
expectedDialogTeamID="PWA5E9TQ59"

function updateScriptLog() {
    echo -e "$(date +%Y-%m-%d\ %H:%M:%S) - ${1}" | tee -a "${scriptLog}"
}

function fail() {
    updateScriptLog "ERROR: ${1}"
    # dialog itself may not be installed yet, so fall back to a native alert
    if [[ -x "${dialogBinary}" ]]; then
        "${dialogBinary}" --title "dialogCheck: Error" \
            --message "${1}" \
            --button1text "Close" \
            --icon caution
    else
        osascript -e "display alert \"dialogCheck: Error\" message \"${1}\"" >/dev/null 2>&1
    fi
    exit 1
}

if [[ ! -d "$(dirname "${scriptLog}")" ]]; then
    mkdir -p "$(dirname "${scriptLog}")"
fi

if [[ ! -f "${scriptLog}" ]]; then
    touch "${scriptLog}"
    updateScriptLog "*** Created log file via script ***"
fi

updateScriptLog "\n\n###\n# dialogCheck - SwiftDialog Installer (${scriptVersion})\n###\n"

# dialogCheck was originally written by Adam Codega - https://github.com/acodega/swiftDialogScripts/blob/main/dialogCheckFunction.sh
function dialogCheck() {

    if [[ -x "${dialogBinary}" ]]; then
        updateScriptLog "swiftDialog $(${dialogBinary} --version) found; proceeding..."
        return 0
    fi

    updateScriptLog "swiftDialog not found; installing..."

    dialogURL=$(curl -sL "https://api.github.com/repos/swiftDialog/swiftDialog/releases/latest" \
        | awk -F '"' '/browser_download_url/ && /\.pkg/ { print $4; exit }')

    if [[ -z "${dialogURL}" ]]; then
        fail "Could not determine swiftDialog download URL (GitHub API request may have failed or been rate-limited)."
    fi

    updateScriptLog "Downloading Dialog from URL: ${dialogURL}"

    tempDirectory=$(mktemp -d)

    if ! curl -sL --fail "${dialogURL}" -o "${tempDirectory}/Dialog.pkg"; then
        rm -rf "${tempDirectory}"
        fail "Failed to download swiftDialog package from ${dialogURL}."
    fi

    # Verify the *downloaded* package's signing Team ID before installing it.
    teamID=$(spctl -a -vv -t install "${tempDirectory}/Dialog.pkg" 2>&1 \
        | awk -F '(' '/origin=/ { print $2 }' | tr -d ')')

    if [[ -z "${teamID}" || "${teamID}" != "${expectedDialogTeamID}" ]]; then
        rm -rf "${tempDirectory}"
        fail "Downloaded Dialog package Team ID ('${teamID}') does not match expected Team ID ('${expectedDialogTeamID}'). Exiting."
    fi

    updateScriptLog "Team ID verified (${teamID}); installing package..."

    if ! /usr/sbin/installer -pkg "${tempDirectory}/Dialog.pkg" -target /; then
        rm -rf "${tempDirectory}"
        fail "swiftDialog installer command failed."
    fi

    if [[ ! -x "${dialogBinary}" ]]; then
        rm -rf "${tempDirectory}"
        fail "swiftDialog installation did not produce ${dialogBinary}."
    fi

    rm -rf "${tempDirectory}"
    updateScriptLog "swiftDialog $(${dialogBinary} --version) installed successfully."
}

dialogCheck

updateScriptLog "dialogCheck complete; exiting 0."

exit 0
