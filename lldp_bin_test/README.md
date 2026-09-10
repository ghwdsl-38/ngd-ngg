# LLDP Topology Agent 二进制测试包

本目录中的二进制由当前项目源码构建：

```text
D:\project\ngd-ngg\topology_agent
```

本次构建包含 Bond 主接口采集修改，PRC 和 Algorithm 代码未修改。

## 文件

| 文件 | 用途 |
|---|---|
| `topology-agent-linux-amd64` | Linux x86-64 静态二进制 |
| `topology-agent-linux-amd64.sha256` | SHA-256 校验值 |
| `README.md` | 运行说明 |

## 最简运行方式

将二进制和 LLDP 专用 Kubeconfig 复制到目标 Kubernetes Worker，然后执行：

```bash
chmod 0755 topology-agent-linux-amd64

sudo ./topology-agent-linux-amd64 \
  --interfaces=bond0 \
  --node-name=<Kubernetes中的Node名称> \
  --kubeconfig=/绝对路径/lldp-agent.kubeconfig
```

上面命令将直接绑定 bond0；节点身份参数为：

- `--node-name`：必须与 Kubernetes Node 的 `metadata.name` 完全一致；
- `--kubeconfig`：LLDP Agent 使用的 Kubeconfig 绝对路径。

`--interfaces=bond0` 直接绑定主接口，收集该接口可见的全部 Leaf 邻居。未传参数时默认 `auto`，选择有效 Bond 主接口及独立物理网卡。默认单轮监听 120 秒，完成采集和打标后退出。显式 `--timeout` 会覆盖默认值，现有部署清单的 65s 如需延长应改为 120s。

Bond 下的 Slave 和状态会写入日志，但不会猜测邻居对应哪个 Slave。`leaf-links` 使用 `interface=bond0`，`active=false` 表示未确认物理活动链路；两个 Leaf 保存在原有 `leaf-switch-ids` Annotation。

需要每3分钟循环执行时，显式增加：

```bash
--interval=3m
```

周期模式持续运行，按 `Ctrl+C` 停止。

## 运行条件

- 目标系统为 Linux `x86_64`；
- 使用 root 运行，或为进程提供 `CAP_NET_RAW`；
- 交换机端已发送 LLDP 报文；
- Kubeconfig 能访问 Kubernetes API Server；
- Kubeconfig 身份至少具有目标 Node 的 `get`、`patch` 权限。

权限可提前验证：

```bash
kubectl --kubeconfig=/绝对路径/lldp-agent.kubeconfig auth can-i get nodes
kubectl --kubeconfig=/绝对路径/lldp-agent.kubeconfig auth can-i patch nodes
kubectl --kubeconfig=/绝对路径/lldp-agent.kubeconfig get node <Node名称>
```

## 成功判定

日志中应依次看到 Kubernetes 配置加载、接口选择、LLDP 邻居发现、Node Get 和 Node Patch，最终出现类似：

```text
[LLDP-AGENT] RESULT node=<Node名称> source=LLDP ...
```

查看写入结果：

```bash
kubectl --kubeconfig=/绝对路径/lldp-agent.kubeconfig get node <Node名称> \
  -L topology.demo.ngg.io/leaf-set-id,topology.demo.ngg.io/leaf-count,topology.demo.ngg.io/leaf-switch
```

## 校验与参数查看

```bash
sha256sum -c topology-agent-linux-amd64.sha256
./topology-agent-linux-amd64 --help
```

本次构建校验：`2932130b7dd7828cbeca4d675d5db08b13b60d77d835b997ba850071b0dcc23c`。
