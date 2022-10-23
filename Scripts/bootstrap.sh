#!/usr/bin/env bash

set -e

basePath="$(git rev-parse --show-toplevel)"

if [ -h .git/hooks/pre-commit ]; then
    rm .git/hooks/pre-commit
fi

lintURL="https://raw.githubusercontent.com/noremac/lint/main/Scripts/_lint.sh"

if [ "$(curl -s -I -o /dev/null -w "%{http_code}" "$lintURL")" -ne 200 ]; then
    echo "Could not download the lint file. ❌"
    exit 1
else
    curl -s -o "${basePath}/Scripts/_lint.sh" "$lintURL"
    chmod 755 "${basePath}/Scripts/_lint.sh"
fi

if ln -sf ../../Scripts/pre-commit.sh .git/hooks/pre-commit; then
    echo "Successfully bootstrapped ✅"
fi

