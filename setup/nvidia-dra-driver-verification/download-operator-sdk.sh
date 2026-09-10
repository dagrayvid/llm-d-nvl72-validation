#!/usr/bin/env bash


if [ -f "$(dirname "$0")/operator-sdk" ]; then
    echo "operator-sdk has been already downloaded"
else
    echo "Downloading operator-sdk"
    ARCH=$(case $(uname -m) in x86_64) echo -n amd64 ;; aarch64) echo -n arm64 ;; *) echo -n $(uname -m) ;; esac)
    OS=$(uname | awk '{print tolower($0)}')
    OPERATOR_SDK_DL_URL=https://github.com/operator-framework/operator-sdk/releases/download/v1.41.1
    curl -LO ${OPERATOR_SDK_DL_URL}/operator-sdk_${OS}_${ARCH}
    chmod +x operator-sdk_${OS}_${ARCH}
    mv operator-sdk_${OS}_${ARCH} operator-sdk
fi

"$(dirname "$0")/operator-sdk" version