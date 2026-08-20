#!/bin/bash
set -e

(
    cd Resources/vim
    curl -L https://github.com/blinksh/vim/releases/download/v9.1.0187/runtime.zip > runtime.zip
    unzip runtime.zip && mv runtime/* ./ && rm runtime.zip
)

echo "done"
