# DizzyLab 网站接口梳理

2026-09-26 通过浏览网站页面、查看页面脚本和登录后的网络请求整理，**不是官方文档**，随时可能变化。示例均为公开专辑；文中不出现任何真实凭证。

## 概况

- 网站是 Django 服务端渲染，页面脚本通过少量 JSON 接口加载列表。
- 两套凭证：
  - **会话 Cookie**（`sessionid`，另有 `csrftoken`）：网页页面、POST 操作使用。
  - **API token**（40 位十六进制）：`/apis/*` 只认 URL 里的 `&token=`，**会话 Cookie 对它无效**。登录后在 `/u/<id>/music/` 的 HTML 里以 `var token = '…'` 出现。
- POST 请求需要 `csrfmiddlewaretoken` 字段（或请求头）以及同源 `Referer`。
- **出错时也返回 HTTP 200**：不存在的页面、不存在的专辑都返回标题为「出错了！」的 HTML 错误页，JSON 接口出错时返回的也是这个页面。不能只看状态码判断成功。
- `/apis/*` 返回的 `Content-Type` 是 `text/html`，内容其实是 JSON。
- `robots.txt` 禁止抓取 `/admin`、`/keys` 和带查询参数的地址；App 只在用户操作时按需请求，不做批量抓取。

## JSON 接口

| 接口 | 说明 |
| --- | --- |
| `GET /apis/getdiscs/?l=&r=&sort=&type=` | 专辑列表。`l`/`r` 为左闭右开区间（网页每页 24），`type` 为 `album`（数字专辑）/`ep`（单曲 EP）/`dig`（下载商品）。`sort` 网页固定用 `ad`，实测传其他值（`likes`、`hot`、`new` 等）结果完全一样。返回 `total_count`、`canshowmore`、`discs[]` |
| `GET /apis/getthisdicsinfo/?discid=[&token=]` | 专辑详情与曲目。带 token 时 `ihavethis` 反映是否已购，已购专辑的曲目地址为完整版 |
| `GET /apis/getlabels/?l=&r=&sort=` | 社团列表，`total_count` 约 670，字段见下 |
| `GET /apis/getfeed/?l=&r=&sort=&token=` | 已关注社团的新作动态 |
| `GET /albums/getthisdisclikes/?discid=` | 点赞数与我是否点过：`{likes, ilikethis}`，网页显示为 `likes × 2` dB |
| `GET /getreviews/?discid=&l=&r=` | repo 长评，按字段分列的数组 |
| `GET /getreviewlikesanddislikes/?id=` | 长评的赞 / 踩 |

### `getdiscs` 列表项字段

`id`、`title`、`label`、`labelid`、`labelcover`、`cover`、`price`、`ishires`、`tags[]`、`likes`、`onsell`、`ispreselling`、`onlyhavegift`、`ihavethis`。

价格显示规则（与网页一致）：`price <= 0` 为「免费」；`!onsell && !ispreselling` 为「兑换」；否则为 `¥ price`。

### `getthisdicsinfo` 字段

列表字段之外还有：`release_date`、`disc_description`、`disc_description_2`（曲目表与制作人员）、`label_description`、`hasgift`、`ilikeit`、`tracks[]`。

曲目：`discid`、`id`（专辑内序号，字符串 `"1"`、`"2"`…）、`title`、`authers`（逗号分隔的艺术家）、`album`、`coverurl`（原图，不带 `!cover`）、`url`。**没有时长字段**（专辑页 HTML 的曲目标题里有，如 `(04:08)`）。

两段介绍都是纯文本，换行符为 `\r\n`。

### `getlabels` 字段

`labelid`、`title`（社团名）、`labelcover`、`description`、`tags`，以及最近作品的几个平行数组：`discs`（专辑 ID）、`titles`、`covers`、`isgift`，按下标一一对应。`covers` 是相对 CDN 的路径（如 `cover/2026-1005.jpg`），补全为 `https://cdn.dizzylab.net/media/<路径>!cover`。

## 播放地址

```
https://streaming.dizzylab.net/<yyyyMMddHHmm>/<md5>/<discid>/preview/<n>.mp3
https://streaming.dizzylab.net/<yyyyMMddHHmm>/<md5>/<discid>/full/<n>.mp3
```

- 时间戳是**东八区的过期时间**，约为请求时间加 1 小时（16:41 请求得到 `…1741`）。过期后需重新请求专辑详情。
- `preview` 为试听片段，都是 128 kbps MP3，**长度各专辑不同**（实测 fx4 为 30 秒、HLRVOL4 为 76 秒），可以用 HEAD 拿到的文件大小换算时长。
- 部分专辑未购买也直接给 `full`（例如 CRD-02），网页上这些曲目同样不标「试听」、可以完整收听。
- 支持 Range 请求，不带 Referer 可以正常访问。

## 图片

- 封面、社团头像等在 `https://cdn.dizzylab.net/media/` 下，文件名常含中文。
- 地址后缀是 CDN 的图片样式：`!cover`（列表缩略图，约 180 KB）、`!labellittle`、`!avatarlittle`；不带后缀是原图。
- 有防盗链：不带 Referer 可以访问，带其他站点的 Referer 返回 403。
- 网页的 `<img>` 懒加载，真实地址在 `data-src`，`src` 是占位图 `static/holder_cover.jpg`。

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

列表页底部有「下一页」按钮时还有下一页，最后一页没有这个按钮。

| 页面 | 地址 | 内容 |
| --- | --- | --- |
| 首页 | `/` | `#deal`（限时优惠：截止日期、`<del>原价</del> 现价`）和 `#pack`（全部 pack，约 40 个）直接写在 HTML 里；专辑列表由脚本调 `getdiscs` 加载 |
| 搜索 | `/search/?s=<关键词>&page=<n>` | 第一页依次是「社团」「作品」「用户」三组，之后每页只有作品，每页 10 张 |
| 标签 | `/albums/tags/?tag=<标签>&page=<n>` | 每页 24 张，卡片只有封面和标题；页面上方是全站标签云（约 500 个） |
| 社团页 | `/l/<社团名>/` | 一次列出全部作品和 pack，**作品没有分页**；页面里的 `?page=` 翻的是关注者头像。页头有简介（`#labeldesp`、`#labeldesp2`，用 `<br>` 换行）、关注人数和成立日期 |
| pack | `/pack/?pk=<id>` | 包含的专辑、折扣说明，支付宝价格在付款链接的 `price` 参数里；付款链接的 `type` 为 `pack` |
| 专辑页 | `/d/<discid>/` | 曲目标题含时长：`1. 标题 - 艺术家 (02:35)`；已购时含完整版 `data-audio` 和下载菜单 |
| 排行榜 | `/ranking/` | 按用户排名的「支持者榜」，**不是专辑榜**。`/rank/` 是错误页，网站没有专辑排行榜 |
