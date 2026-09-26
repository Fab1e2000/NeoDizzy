# DizzyLab 网站接口梳理

2026-09-26 通过浏览网站页面、查看页面脚本和登录后的网络请求整理，**不是官方文档**，随时可能变化。示例均为公开专辑；文中不出现任何真实凭证。

## 概况

- 网站是 Django 服务端渲染，页面脚本通过少量 JSON 接口加载列表。
- 两套凭证：
  - **会话 Cookie**（`sessionid`，另有 `csrftoken`）：网页页面、POST 操作使用。
  - **API token**（40 位十六进制）：`/apis/*` 只认 URL 里的 `&token=`，**会话 Cookie 对它无效**。登录后在 `/u/<id>/music/` 的 HTML 里以 `var token = '…'` 出现。
- POST 请求需要 `csrfmiddlewaretoken` 字段（或请求头）以及同源 `Referer`。
- `robots.txt` 禁止抓取 `/admin`、`/keys` 和带查询参数的地址；App 只在用户操作时按需请求，不做批量抓取。

## JSON 接口

| 接口 | 说明 |
| --- | --- |
| `GET /apis/getdiscs/?l=&r=&sort=&type=` | 专辑列表。`l`/`r` 为区间（网页每页 24），`type` 为 `album`（数字专辑）/`ep`（单曲 EP）/`dig`（下载商品），`sort` 网页默认 `ad`。返回 `total_count`、`canshowmore`、`discs[]` |
| `GET /apis/getthisdicsinfo/?discid=[&token=]` | 专辑详情与曲目。带 token 时 `ihavethis` 反映是否已购，已购专辑的曲目地址为完整版 |
| `GET /apis/getlabels/?l=&r=&sort=` | 社团列表，`total_count` 约 670 |
| `GET /apis/getfeed/?l=&r=&sort=&token=` | 已关注社团的新作动态 |
| `GET /albums/getthisdisclikes/?discid=` | 点赞数与我是否点过：`{likes, ilikethis}`，网页显示为 `likes × 2` dB |
| `GET /getreviews/?discid=&l=&r=` | repo 长评，按字段分列的数组 |
| `GET /getreviewlikesanddislikes/?id=` | 长评的赞 / 踩 |

### `getdiscs` 列表项字段

`id`、`title`、`label`、`labelid`、`labelcover`、`cover`、`price`、`ishires`、`tags[]`、`likes`、`onsell`、`ispreselling`、`onlyhavegift`、`ihavethis`。

价格显示规则（与网页一致）：`price <= 0` 为「免费」；`!onsell && !ispreselling` 为「兑换」；否则为 `¥ price`。

### `getthisdicsinfo` 字段

列表字段之外还有：`release_date`、`disc_description`、`disc_description_2`（曲目表与制作人员）、`label_description`、`hasgift`、`ilikeit`、`tracks[]`。

曲目：`discid`、`id`（专辑内序号，字符串 `"1"`、`"2"`…）、`title`、`authers`（逗号分隔的艺术家）、`album`、`coverurl`、`url`。**没有时长字段**（专辑页 HTML 的曲目标题里有，如 `(04:08)`）。

## 播放地址

```
https://streaming.dizzylab.net/<yyyyMMddHHmm>/<md5>/<discid>/preview/<n>.mp3
https://streaming.dizzylab.net/<yyyyMMddHHmm>/<md5>/<discid>/full/<n>.mp3
```

- 带时间签名，过期后需重新请求专辑详情。
- `preview` 为 36 秒试听片段（128 kbps MP3）；部分专辑未购买也提供 `full`。
- 支持 Range 请求，不校验 Referer。

## 下载

已购专辑的专辑页（需会话 Cookie）有「已有数字版，下载」下拉菜单：

```
/albums/download/?d=<discid>&tp=128|MP3|FLAC&k=<base64>&v=0
```

- `tp`：`128`（MP3 128 kbps）、`MP3`（320 kbps）、`FLAC`；菜单文字附带文件大小，如「FLAC (Level-5) - 145MB」。
- `k` 解码后为「过期时间戳:签名」，有效期约 1 小时，需在下载前现取。
- 下载结果为 ZIP 压缩包（文件名编码与目录结构待 M3 实测）。

## 账号

- **登录**：`GET /albums/login/` 取 `csrftoken` Cookie 和表单里的 `csrfmiddlewaretoken`；`POST /albums/login/`，字段 `csrfmiddlewaretoken`、`username`（用户名或邮箱）、`password`、`next`。无验证码。
- **登录后导航**：`/u/<id>`（个人信息）、`/feed/`（我的关注）、`/albums/purchases/`（全部订单）、`/albums/msgbox/`（收件箱）、`/albums/logout`。
- **用户页**（HTML）：`/u/<id>/music`（已购）、`/review`（repo）、`/following`（关注的社团）、`/likes`（点赞过的专辑）。
- **全部订单**只列出已付款订单。

## 购买

专辑页购买面板的脚本拼出以下地址（未登录时「现在购买」跳转登录页）：

```
/albums/checkout_alipay/?id=<discid>&q=1&type=dig&price=<元>&commit=<附言>
/albums/checkout_alipay/?id=<discid>&q=1&type=boost&price=<元>&commit=<附言>   # 已购专辑追加支持
```

- `price` 不得低于页面上 `#yourprice` 的 `min`；BOOST 百分比 = `price / 折后价 × 100`。
- 打开付款地址会立即创建订单（`dizz_<用户ID>_<discid>_<时间>_<随机串>`），然后按 User-Agent 跳转：
  - 桌面 UA → `excashier.alipay.com`（PC 收银台，只能扫码或登录账户付款，手机上不可用）
  - 手机 UA → `mclient.alipay.com/h5pay/landing`（H5 收银台，预期通过 `alipays://` 跳转支付宝 App，待真机验证）
- 未付款订单不会出现在「全部订单」里。

## 社区

| 操作 | 请求 |
| --- | --- |
| 点赞 / 取消点赞专辑 | `POST /albums/ilikethisornot/`，字段 `discid`、`csrfmiddlewaretoken` |
| 发短评 | `POST /albums/postdisccomment/` |
| 删自己的短评 | `POST /albums/deletemycomment/` |
| 长评点赞 | `/ilikethisreviewornot/` |
| 随便听听 | `POST /getatrack/`，字段 `csrfmiddlewaretoken`；返回 `discid`、`thisurl`、`thistrack`、`disctitle`、`disclabel`、`disccover`、`taglist` 等 |
| 关注 / 取关社团 | `GET /l/<社团名>/?like` / `?dislike`（需会话 Cookie） |

## HTML 页面

| 页面 | 地址 |
| --- | --- |
| 搜索 | `/search/?s=<关键词>` |
| 标签 | `/albums/tags/?tag=<标签>` |
| 排行榜 | `/rank/` |
| 社团页 | `/l/<社团名>/` |
| pack | `/pack/?pk=<id>` |
| 专辑页 | `/d/<discid>/`（已购时含完整版 `data-audio` 和下载菜单） |
