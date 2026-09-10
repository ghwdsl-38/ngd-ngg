# 新旧 LLDP 二进制对比（2026-09-10）

已比较当前发布二进制和根目录的旧 `lldp-node-labeler`。已确认存在行为差异，但缺少目标 Linux 节点的新旧启动命令和日志，不能认定故障根因，也未修改或替换发布二进制。

## 文件身份与方法

| 项目 | 旧版 | 新版 |
|---|---|---|
| 文件 | `../../lldp-node-labeler` | `../topology-agent-linux-amd64` |
| Go module | `lldp-physical-test` | `demo.ngg/topology-agent` |
| Go toolchain | 1.24.13 | 1.25.13 |
| 编译目标 | Linux amd64，CGO=0 | Linux amd64，CGO=0 |
| 特殊构建 tag | `node_labeler` | 未记录 |
| SHA-256 | `289a65a6e0d5b9445df032dc920173c2147aa281f43f3b486053d8de7ddaf2f6` | `0b3d9fad64b9177a1c8d8cf231b1eaefb9f0cc3b1bee2f7f0b172e449bc678f0` |

新版散列与发布校验文件一致。两版去掉了普通符号表，因此使用 Go pclntab、debug/gosym 和 Go 工具链自带的 x86 指令解码器恢复函数范围、源码行号和关键指令；这不是恢复出的完整旧源码。辅助工具位于 `.cache/lldp-inspect/`，本目录保存提取证据。

## 已确认的差异

| 项目 | 旧版 | 新版 | 影响 |
|---|---|---|---|
| 接口参数 | `--interface`，默认 `auto` | `--interfaces`，默认 `auto`，可被 `LLDP_INTERFACES` 环境变量覆盖 | 不能原样照搬命令；新版继承的环境变量也可能改变实际范围 |
| 默认监听时间 | **120 秒** | **65 秒** | 相同运行次数并非相同观察窗口；先统一为 120 秒比较 |
| 显式指定 `bond0` | 按字面接口获取 ifindex 并 Bind | 按 Bond 策略展开到 Slave，不绑定主接口，过滤 Slave ifindex | 两者抓包接口语义不同，这是优先排查项 |
| 显式物理网卡 | 按字面接口 Bind | 单个显式物理接口 Bind | 适合选同一物理网卡进行对照 |
| Node metadata | 默认 `lldp.network.local/*`，旧版可设 label-prefix | `topology.demo.ngg.io/*` | 查看旧前缀不能判断新版是否探测成功 |
| 多 Leaf 表达 | 旧版保留外部邻居、输出其 metadata | 新版把 Chassis/Leaf 规范化，并检查同一 Chassis 名称冲突、不同 Chassis 同名冲突 | 可在已收到报文后拒绝生成拓扑；需看具体错误 |
| 单值 leaf-switch | 旧版 metadata 体系不同 | 仅当恰好一个 Leaf 且名称可作为 Kubernetes Label 时生成 | 双 Leaf 或特殊名称时应查看 Annotation，不能只看该 Label |
| 独立探测 | 有 `--dry-run`，帮助说明为不调用 Kubernetes | 当前没有 dry-run，先加载 Kubernetes 配置，再采集、打标 | 旧版 dry-run 成功与新版认证/打标成功不是同一验收范围 |

旧默认超时证据：`old-options.asm.txt` 中 `0x69fe9d` 加载 `0x1bf08eb000` 纳秒，即 120 秒。旧显式绑定路径见 `old-receive.asm.txt` 的 `0x695927` 起条件分支与 `0x695af2` Bind 调用；新版 Bond 展开日志和代码路径见 `new-select.asm.txt`。

## 已核对的相同点

- 两版 Socket 实参均为 `AF_PACKET=17`、`SOCK_RAW=3`、网络字节序 `0xcc88`，对应 EtherType `0x88cc`。旧调用位于 `0x695820`，新调用位于 `0x1039c60`。
- 两版自动模式均不 Bind，并按已选接口过滤；两版都有排除本机发出报文的分支。
- 物理网卡判断均检查 sysfs `device`、Ethernet `type=1`，并排除 `wireless`/`phy80211`。
- 自动 Bond 选择均区分 active-backup 与其他模式，并检查链路/MII 状态。
- 两版均排除 SystemName 与本机 hostname 相似的邻居。

这些相同点不等于全部实现完全一致。旧程序目前只有二进制，当前仓库文档声称“对齐 lldp-new-3”不能代替逐项行为验证。

## 优先排查 Bond ifindex

如果新版日志出现：

```text
IGNORE frame interface=bond0 ... reason=not-selected-by-link-physical-bond-policy
```

则说明实际已收到报文，但该入口不在 Slave 候选集合中。Linux Bond 接收路径存在将 `skb->dev` 设置为 Bond 主接口的处理，因而显式主接口与 Slave 过滤是有实际影响的差异。此处是依据代码提出的排查假设，不能在没有目标内核版本和日志时认定已发生。参考 [Linux Bond 接收实现](https://github.com/torvalds/linux/blob/master/drivers/net/bonding/bond_main.c)。

不要直接把所有 Bond 主接口报文当作任意一个 Slave 的物理邻居，否则会丢失真实端口归属，尤其影响双 Leaf/Bond 拓扑。

## 在目标节点上对照

先提供原来成功的旧命令和当前失败的新命令。统一超时，并指定同一个实际物理网卡（替换示例 `ens1f0`、Node 名和 kubeconfig 路径）：

```bash
sudo ./lldp-node-labeler \
  --interface=ens1f0 --timeout=120s --count=0 --dry-run \
  2>&1 | tee old-lldp.log

sudo ./topology-agent-linux-amd64 \
  --interfaces=ens1f0 --timeout=120s --count=0 \
  --node-name=<Node名称> --kubeconfig=<绝对路径> \
  2>&1 | tee new-lldp.log
```

注意新版命令成功后会更新 Node metadata；旧版上述命令为只探测。不要用 `bond0` 与 Slave 分别运行后误认为比较了同一接口。

可先收集不包含认证凭据的主机信息：

```bash
uname -r
ip -br link
cat /proc/net/bonding/bond0
```

### 日志定位

| 新版现象 | 所处阶段 |
|---|---|
| `unknown flag` | 新旧参数名不兼容，尚未探测 |
| Kubernetes 配置加载错误 | 尚未开始探测 |
| `no eligible ... interface` | 接口发现/筛选阶段 |
| `open LLDP raw socket` 错误 | Socket 创建阶段 |
| `IGNORE ... not-selected-by-link-physical-bond-policy` | 已收到报文，但入口被过滤 |
| `RECEIVE` 后 `invalid-LLDP` | 报文解析阶段 |
| `LEAF FOUND` 后 Chassis/Leaf 冲突错误 | 已探测到邻居，规范化失败 |
| `METADATA BUILT` 后 Kubernetes 错误 | 已探测到邻居，持久化失败 |
| `RESULT ... source=LLDP` | 探测与写入完成，应查看新前缀及 Annotation |

完整 Leaf 名称位于 `topology.demo.ngg.io/leaf-switch-ids` Annotation，物理链路位于 `topology.demo.ngg.io/leaf-links` Annotation。

此前 Group7 的 PASS 覆盖模拟 sysfs/Bond/LLDP 事实到 NGG 的链路，未覆盖目标 Linux 主机的 raw socket 收包，不能证明本次二进制已能接收真实交换机 LLDP。
