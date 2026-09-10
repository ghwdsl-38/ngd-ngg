# Bond 主接口版本验证

构建时间：2026-09-10。Go 1.25.14，Linux amd64，CGO_ENABLED=0，`-trimpath -ldflags '-s -w'`。

发布文件：`../topology-agent-linux-amd64`。
SHA-256：`2932130b7dd7828cbeca4d675d5db08b13b60d77d835b997ba850071b0dcc23c`。
已核对 ELF64/x86-64、无 PT_INTERP 动态解释器、校验文件匹配。

修改范围：拓扑 Agent 的 Bond 主接口选择、Linux 接收实现拆分、默认 120 秒监听窗口、同接口多远端端口排序；原 PRC/Algorithm 代码未修改。非 Linux 平台仅支持运行解析、接口 fixture 和元数据测试，真实收包明确返回需要 Linux。

验证结果：

- `unit-tests.log`：拓扑单测通过，包括主接口选择、显式 Slave、sysfs/proc 回退、两个 Leaf 报文解析、去重及顺序稳定性。
- `group-summary.json`：Group1、2、3、4、5、7 全部通过。
- Group7 新增 `bond-master-active-backup` 和 `bond-master-load-balance`，两者均在同一个 bond0 上模拟两个 Leaf，原 PRC/Algorithm 成功生成包含 10 Node 的 Active NGG。
- 完整组日志：`../../go_test_suites/results/local-20260910-160439-607/`。
- Group7 完整输入、快照和 NGG：`../../go_test_suites/group7_bond_topology_flow/results/20260910-160528.957059400/`。
- Windows envtest 使用本地测试入口已有的 controller-runtime 退出兼容副本；结束后没有 envtest 残留进程。

本机为 Windows，没有运行发布的 Linux 二进制或实际网卡收包。现场仍需在目标 Linux 节点使用 `--interfaces=bond0` 验证 `unix.Bind`、两个 Leaf 的 `LEAF FOUND` 及最终 `RESULT source=LLDP`。

旧二进制及其校验值保存在 `../previous/0b3d9fad64b9/`。构建信息见 `build-info.txt`，源码校验列表见 `source-sha256.json`。
