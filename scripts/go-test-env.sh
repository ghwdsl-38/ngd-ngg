#!/usr/bin/env sh
# 本文件只配置本项目的本地Go Test/Delve缓存；Go和Delve使用本机PATH中的版本。
NGG_PROJECT_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
export GOMODCACHE="${NGG_PROJECT_ROOT}/.cache/go-mod"
export GOCACHE="${NGG_PROJECT_ROOT}/.cache/go-build"
export KUBEBUILDER_ASSETS="${NGG_PROJECT_ROOT}/.cache/envtest/1.35.5"
export GOMAXPROCS="2"
unset NGG_PROJECT_ROOT
