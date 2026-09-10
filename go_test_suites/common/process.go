// Package common 提供四组Go Test共享的Fixture、Mock服务、envtest和结果工具。
package common

import (
	"os"
	"path/filepath"
	"runtime"

	algorithm "demo.ngg/algorithm-server/algorithm"
)

// ProjectRoot返回ngd-ngg-scheduling-demo绝对路径，不依赖测试启动目录。
func ProjectRoot() string {
	_, source, _, _ := runtime.Caller(0)
	return filepath.Clean(filepath.Join(filepath.Dir(source), "..", ".."))
}

// PythonWorkerConfig返回真实Algorithm Python模块的本地启动配置。
func PythonWorkerConfig(evidenceDir string) algorithm.WorkerConfig {
	executable := os.Getenv("PYTHON_EXECUTABLE")
	if executable == "" {
		executable = "python3"
	}
	return algorithm.WorkerConfig{
		Executable:  executable,
		Module:      "algorithm_worker.worker",
		PythonPath:  filepath.Join(ProjectRoot(), "algorithm_server", "python"),
		EvidenceDir: evidenceDir,
	}
}
