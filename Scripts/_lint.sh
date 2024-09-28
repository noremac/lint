#!/usr/bin/env bash

set -e
set -o pipefail

exitStatus=0
onCI=0
inXcode=0

if [ "$1" == "-ci" ]; then
    onCI=1
fi

if [ -n "$XCODE_VERSION_MINOR" ]; then
    inXcode=1
fi

ERROR_START=
WARNING_START=
MESSAGE_END=

if [ $inXcode == 1 ]; then
    ERROR_START="error: "
    WARNING_START="warning: "
    MESSAGE_END=""
else
    ERROR_START="\033[0;31m"
    WARNING_START="\033[0;32m"
    MESSAGE_END="\033[0m"
fi

function echoError() {
    echo -e "${ERROR_START}${1}${MESSAGE_END}"
}

function echoWarning() {
    echo -e "${WARNING_START}${1}${MESSAGE_END}"
}

function latestTag() {
    git ls-remote --tags "https://github.com/$1" 2>/dev/null | grep -v "\^{}" | grep -v "pull" | grep -v "beta" | grep -v "rc" | awk -F / '{print $3}' | sort -rV | head -n 1
}

function updateToLatest() {
    # safe to assume
    scriptPath="$(git rev-parse --show-toplevel)/Scripts"
    latestTag nicklockwood/SwiftFormat > "$scriptPath/swiftformat-version"
    latestTag realm/SwiftLint > "$scriptPath/swiftlint-version"
}

if [ "$1" == "update" ]; then
    updateToLatest
    exit 0
fi

expectedSwiftformatVersion=$(cat "$scriptPath/swiftformat-version")
expectedSwiftlintVersion=$(cat "$scriptPath/swiftlint-version")
binPath="$scriptPath/.bin"
swiftformatPath="$scriptPath/.bin/swiftformat"
swiftlintPath="$scriptPath/.bin/swiftlint"

function checkForUpdates() {
    if latestSwiftformatVersion=$(latestTag nicklockwood/SwiftFormat); then
        if [ "$latestSwiftformatVersion" != "$expectedSwiftformatVersion" ]; then
            echoWarning "There is a new SwiftFormat available: $latestSwiftformatVersion. Consider running \"Scripts/_lint.sh update\" or manually updating Scripts/swiftformat-version."
        fi
    fi

    if latestSwiftlintVersion=$(latestTag realm/SwiftLint); then
        if [ "$latestSwiftlintVersion" != "$expectedSwiftlintVersion" ]; then
            echoWarning "There is a new SwiftLint available: $latestSwiftlintVersion. Consider running \"Scripts/_lint.sh update\" or manually updating Scripts/swiftlint-version."
        fi
    fi

    if latestLintHash=$(curl -s https://raw.githubusercontent.com/noremac/lint/main/Scripts/_lint.sh | md5); then
        localLintHash=$(cat ${scriptPath}/_lint.sh | md5)
        if [ "$latestLintHash" != "$localLintHash" ]; then
            echoError "Your lint script is out-of-date. Please run Scripts/bootstrap.sh."
            exit 1
        fi
    fi
}

function installSwiftformat() {
    echoWarning "Installing swiftformat $expectedSwiftformatVersion..."
    downloadPath="${TMPDIR}$(uuidgen)"
    mkdir -p "$downloadPath/swiftformat/swiftformat"
    curl -s -o "$downloadPath"/swiftformat/swiftformat.zip -L "https://github.com/nicklockwood/SwiftFormat/releases/download/$expectedSwiftformatVersion/swiftformat.zip"
    unzip -q "$downloadPath"/swiftformat/swiftformat.zip -d "$downloadPath"/swiftformat/swiftformat
    mv -f "$downloadPath"/swiftformat/swiftformat/swiftformat "$swiftformatPath"
}

function installSwiftlint() {
    echoWarning "Installing swiftlint $expectedSwiftlintVersion..."
    downloadPath="${TMPDIR}$(uuidgen)"
    mkdir -p "$downloadPath/swiftlint/swiftlint"
    curl -s -o "$downloadPath"/swiftlint/swiftlint.zip -L "https://github.com/realm/SwiftLint/releases/download/$expectedSwiftlintVersion/portable_swiftlint.zip"
    unzip -q "$downloadPath"/swiftlint/swiftlint.zip -d "$downloadPath"/swiftlint/swiftlint
    mv -f "$downloadPath"/swiftlint/swiftlint/swiftlint "$swiftlintPath"
}

function configureEnvironment() {
    if [ ! -d "$binPath" ]; then
        mkdir -p "$binPath"
    fi

    # check if the bin path is in the gitignore
    gitignorePath="$(git rev-parse --show-toplevel)/.gitignore"

    if ! grep "Scripts/.bin" "$gitignorePath" > /dev/null; then
        echo "Scripts/.bin" >> "$gitignorePath"
        echoError "Please commit the updated .gitignore file so that swiftformat and swiflint binaries are not checked in."
    fi

    if [ ! -f "$swiftformatPath" ]; then
        installSwiftformat
    else
        swiftformatVersion=$("$swiftformatPath" --version)

        if [ "$swiftformatVersion" != "$expectedSwiftformatVersion" ]; then
            installSwiftformat
        fi
    fi

    if [ ! -f "$swiftlintPath" ]; then
        installSwiftlint
    else
        swiftlintVersion=$("$swiftlintPath" --version)

        if [ "$swiftlintVersion" != "$expectedSwiftlintVersion" ]; then
            installSwiftlint
        fi
    fi

    if [ $exitStatus != 0 ]; then
        exit $exitStatus
    fi
}

function lint() {
    if [ $onCI == 1 ]; then
        if ! "$swiftformatPath" . --lint; then
            exitStatus=1
        fi

        echo "Running SwiftLint..."
        if ! "$swiftlintPath" lint --quiet --strict; then
            echo "SwiftLint issues have been detected. Please correct them and commit."
            exitStatus=1
        fi
    elif [ $inXcode == 1 ]; then
       "$swiftlintPath" lint --quiet
    else
        echo -n "Running SwiftFormat..."
        if ! "$swiftformatPath" . --lint &> /dev/null; then
            "$swiftformatPath" . &> /dev/null
            echo ""
            echoError "SwiftFormat changes have been made. Please review and commit."
            exitStatus=1
        else
            echo " ✅"
        fi

        echo -n "Running SwiftLint..."
        if ! "$swiftlintPath" lint --quiet --strict; then
            echo ""
            echoError "SwiftLint issues have been detected. Please correct them and commit."
            exitStatus=1
        else
            echo "   ✅"
        fi
    fi
}

if [ $onCI == 0 ] && [ $inXcode == 0 ]; then
    checkForUpdates
fi
configureEnvironment
lint

exit $exitStatus

