# Relay protocol v1

状态：后端已实现，正式 Swift 客户端尚未接入。所有时间均为 Unix 毫秒整数；所有接口需要 HTTPS，WebSocket 使用 WSS。下面路径均相对于服务地址。

## 设备身份和请求签名

每台设备在本地生成独立的 Ed25519 签名密钥和 X25519 加密密钥。原始公钥为 32 字节，接口使用 64 位小写十六进制；私钥不发给服务端。设备 ID 是原始 Ed25519 公钥的 SHA-256，小写十六进制。

除 `GET /healthz` 外，每个 HTTP 请求及 WebSocket 握手都需要：

| Header | 内容 |
| --- | --- |
| `X-Gatto-Key` | Ed25519 原始公钥，小写十六进制 |
| `X-Gatto-Time` | 当前 Unix 毫秒，13 位十进制字符串 |
| `X-Gatto-Nonce` | 每次请求新生成的 16 随机字节，小写十六进制 |
| `X-Gatto-Signature` | 对下列 UTF-8 字节的 Ed25519 签名，64 字节，小写十六进制 |

签名原文的字段用一个 LF 分隔，**末尾也有 LF**：

```text
GATTO/1
HTTP_METHOD
/exact/request/path
public_key_hex
timestamp_ms
nonce_hex
sha256_hex_of_exact_body_bytes
```

方法使用大写，路径必须与实际发送路径逐字节一致，不接受 query。GET、DELETE、WebSocket 握手签名空正文；无正文时不发送 JSON Content-Type。JSON 请求必须对实际发送的 UTF-8 字节签名，不重新排序字段或改变空格。服务器允许正负 60 秒时钟误差，在该请求可能有效的整个时间范围内持久化拒绝重复 nonce，重启不清空。

重试使用新 nonce 和时间重新签名；业务 ID 和原始业务内容保持不变。不要把认证头写入日志。

## 配对

1. 电脑本地生成 UUID `id` 和 32 随机字节的无填充 base64url `token`。电脑公钥必须位于服务端登记名单。
2. 电脑 `POST /v1/pairings`，正文 `{ id, token, encryptionKey }`。返回 `{ id, expiresAt, hostId }`，邀请有效期 5 分钟。同一 ID、内容在有效期内重试不会重新创建或延长有效期。
3. 二维码由电脑生成，包含协议版本、可信服务地址、`id`、`token`、电脑签名公钥和加密公钥。二维码不是服务端返回的任意网页链接；手机应验证服务地址和 TLS。
4. 手机 `POST /v1/pairings/:id/claim`，正文 `{ token, encryptionKey }`，使用手机签名。仅允许第一个手机领取；同一手机相同密钥重试可复用。返回 `claimed` 和电脑公钥，手机与二维码内公钥逐项核对。
5. 电脑 `GET /v1/pairings/:id` 查看领取设备公钥。客户端应在两端展示由双方签名公钥、加密公钥及配对 ID 派生的同一校验指纹，让用户核对。尚未实现正式核对 UI。
6. 用户在电脑确认后，电脑 `POST /v1/pairings/:id/approve`，正文 `{ mobileId, repositories: ["repo-one"] }`。绑定明确手机 ID，不能批准另一个领取者；同样的批准请求可重试。仓库 ID 是电脑生成的不透明标识，不发送本地目录路径。
7. 手机读取配对状态，只有 `approved` 才允许收发消息。加密公钥一旦登记，不允许用同一个签名身份静默更换。

任一端可 `DELETE /v1/pairings/:id` 撤销该关系。撤销会清除待收密文，禁止该关系后续收发；最后一个配对被撤销时关闭设备连接。不能撤回已经交给设备的消息，因此电脑执行端还必须检查自己的撤销状态和任务许可。

`GET /v1/pairings/:id` 只对参与双方可见，包含主机／手机身份、状态、邀请截止时间和获准仓库。`expiresAt` 是邀请期限，批准后不作为配对的自动到期时间。

## 加密信封

`POST /v1/messages` 正文：

```json
{
  "version": 1,
  "id": "客户端生成的 UUID",
  "pairingId": "已批准配对的 UUID",
  "senderId": "发送设备 ID",
  "recipientId": "同一配对的另一台设备 ID",
  "repositoryId": "repo-one",
  "expiresAt": 1790000000000,
  "sealed": "base64(nonce || ciphertext || tag)"
}
```

上面的 UUID／ID／sealed 为说明字段，不是可直接发送的测试数据。加密格式：

1. X25519：本端加密私钥与已经核对并固定的对端加密公钥导出共享密钥。
2. HKDF-SHA256：输入为共享密钥，salt 为配对 UUID 的 UTF-8 字节，info 为 `GATTO-KEY/1\n<senderId>\n<recipientId>\n`，输出 32 字节。两个方向使用不同密钥。
3. AES-256-GCM：每条消息使用安全随机源产生 12 字节 nonce；认证 tag 为 16 字节。AAD 为下列 LF 分隔的 UTF-8 字节，末尾 LF：

```text
GATTO-BOX/1
message_id
pairing_id
sender_id
recipient_id
repository_id
expires_at_ms
```

4. `sealed` = nonce（12 字节）+ ciphertext + tag（16 字节），标准带填充 base64。接收端先核对身份、范围、期限，再认证解密，失败不执行。

加密信封最大 64 KiB，包括 nonce 和 tag；HTTP 请求体最大 96 KiB。代码文件、大日志和附件后续需另行定义分块或传输协议，当前不能发送任意大小文件。

## 收件、去重和确认

- 成功发送返回 `{ id, state: "queued", duplicate: false }`，表示密文已经提交到数据库事务。
- 幂等键为 `(senderId, id)`。相同信封重试返回现有状态，不能重新入队；相同 ID 不同内容返回 `409 message_id_conflict`。
- `GET /v1/messages` 返回本设备最多 32 条未过期、未确认信封，按入队顺序。再次调用仍返回未确认项，没有自动消费。
- 接收端先将任务与收件状态持久化，再 `POST /v1/messages/ack`，正文 `{ receipts: [{ senderId, id }] }`。ACK 仅能确认自己的收件，重复 ACK 不报错。
- ACK 后服务端清除密文，保留去重信息。到期消息不再投递，清理任务清除密文；去重记录保留到消息到期后 24 小时。原信封此后已经超出可接受期限，不能作为有效重试再次投递。
- 接收方若收到同一任务的新信封，仍须按任务 ID 和批准的仓库状态去重。传输层不是“命令恰好执行一次”的保证。
- 单配对最多 128 条待确认消息，全局 4096 条；包括去重记录在内最多 20,000 条。满额返回 429，不丢弃已经接受的有效消息。
- 消息期限必须晚于服务器当前时间且不超过 10 分钟。服务器时钟为参考；客户端不自动重新签发过期写入任务。

## WebSocket 与在线状态

以同样的签名认证头连接 `GET /v1/socket`，签名正文为空。凭据不放 URL。握手前完成签名、重放和配对检查。

服务端事件：

| type | 字段／含义 |
| --- | --- |
| `ready` | `protocol: 1, serverTime`；连接就绪 |
| `messages.available` | 调用签名 GET 收件接口；事件本身不是密文投递或任务成功结果 |
| `presence` | `deviceId, online, at`；同一已批准配对的设备上下线 |
| `pairing.changed` | `pairingId`；电脑已有连接时通知新的领取请求，首个配对需 HTTP 读取状态 |
| `pairing.revoked` | `pairingId`；该配对失效 |

WebSocket 是通知通道，不接受任务／ACK 正文，写操作统一走签名 HTTP。每 15 秒 ping，一轮没有 pong 则终止连接。同一设备新连接替换旧连接（4001）；无剩余配对关闭（4003）。队列仍在，重连后主动读取收件箱，不依赖通知必达。客户端重连应使用退避和随机抖动。

`GET /v1/devices` 返回已配对设备的 `id, online, lastSeen` 和服务器时间。`online` 只表示有当前连接，不表示任务执行成功。重启后所有设备先视为离线，最后在线时间保留，不能恢复成假在线。

## 错误与部署限制

错误正文统一为 `{ error: "stable_code" }`，不回显正文、SQL 或凭据。

- 400：字段、时间或正文不正确。
- 401：签名不正确、时间过期或 nonce 重放。
- 403／404：未登记、未批准或无访问权限；不要自动提升权限重试。
- 409：领取冲突、身份变化或幂等内容冲突；重新读取真实配对状态。
- 429：限流或队列满，带 `Retry-After: 60`；处理已有收件后退避重试。
- 503：存储或容量不可用；不要把失败提示当成写入成功。

默认每 IP 每分钟 180 次、每签名身份 240 次、全局 3000 次 HTTP 请求，固定窗口；最多 512 个 TCP 连接。数据库最多 2000 个设备、2000 个配对，单电脑最多 20 个未撤销配对。这个单实例实现尚未经过公网负载测试；不是无限扩容的账号平台。
