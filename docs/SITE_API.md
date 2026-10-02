# DizzyLab 网站接口梳理

2026-09-26 通过浏览网站页面、查看页面脚本和登录后的网络请求整理，**不是官方文档**，随时可能变化。示例均为公开专辑；文中不出现任何真实凭证。

## 概况

- 网站是 Django 服务端渲染，页面脚本通过少量 JSON 接口加载列表。
- 两套凭证：
  - **会话 Cookie**（`sessionid`，另有 `csrftoken`）：网页页面、POST 操作使用。
  - **API token**（40 位十六进制）：`/apis/*` 只认 URL 里的 `&token=`，**会话 Cookie 对它无效**。登录后在 `/u/<id>/music/` 的 HTML 里以 `var token = '…'` 出现。
  - 实测**只带 token、不带任何 Cookie** 调 `/apis/*` 完全可用；token 错误时返回 HTML 错误页而不是 JSON。
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
| `GET /apis/getfeed/?l=&r=&sort=&token=` | 已关注社团的新作动态，需要 token。`l`/`r` 按社团分组计数（网页每页 6 组），`sort=ad`。返回 `canshowmore` 和 `labels[]`，**没有 `total_count`** |
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

特典入口（2026-09-30 在 ALCD0003 已购页面确认）：

```
/albums/download_gift/<discid>/?k=<signature>&v=2
```

App 单独解析此同源、专辑 ID 匹配且签名非空的入口，开始和重试前重新获取。
特典复用后台 ZIP 下载与安全解压，保存到专辑目录的 `特典/`，不参与曲目匹配。
先下载特典时预建专辑目录，之后下载音频会保留特典；本地专辑使用其实际目录。
新功能已用人工构造的非音频内容测试保存流程；真实特典 ZIP 的端到端下载仍需设备验收。


已购专辑的专辑页（需会话 Cookie）有「已有数字版，下载」下拉菜单：

```
/albums/download/?d=<discid>&tp=128|MP3|FLAC&k=<base64>&v=0
```

- `tp`：`128`（MP3 128 kbps）、`MP3`（320 kbps）、`FLAC`；菜单文字附带文件大小，如「FLAC (Level-5) - 145MB」。
- `k` 解码后为「过期时间戳:签名」，有效期约 1 小时，需在下载前现取。
- 下载结果为 ZIP 压缩包（文件名编码与目录结构待 M3 实测）。

M3 实现会在启动和重试时重新读取此菜单，只接受同源且专辑 ID、格式和签名参数完整的下载链接。下载到临时目录后先校验 ZIP，再解压、匹配曲号并写入所选文件夹。本轮没有可用的已登录网页会话，真实下载包的文件名编码与结构仍未核实；编码和目录兼容性测试使用人工构造的 ZIP，不把它们作为网站现状的证据。

后续真机验证：2026-09-26 使用 App 会话成功下载 ALCD0001 的 FLAC ZIP，解压、匹配并导入 5 首曲目。本次样本已验证实际下载流程，不代表所有作品均使用相同 ZIP 编码或目录结构。

### `getfeed` 字段

`labels[]` 每项是一个社团：`labelid`、`title`（社团名）、`labelcover`、`add_date`（ISO 8601），以及这批新作 `discs[]`。
新作只有 `id`、`title`、`cover`、`price`、`tags`、`description`、`onlyhavegift`、`add_date`、`release_date`，**没有在售状态**。

## 账号

- **登录**：`GET /albums/login/` 取 `csrftoken` Cookie 和表单里的 `csrfmiddlewaretoken`；`POST /albums/login/`（带同源 `Referer`），字段 `csrfmiddlewaretoken`、`next`、`username`（昵称或邮箱）、`password`。无验证码。
  - 成功时设置 `sessionid` Cookie，**响应是 200 而不是跳转**，所以要看 Cookie 或重新请求首页来判断是否登录成功。
  - 失败时返回的仍是登录页，页面上有 Bootstrap 提示框，文字是「抱歉！登录信息错误」（末尾是 × 关闭按钮）。
- **token 不随退出登录失效**：`/albums/logout` 只结束网页会话，之后 token 调 `/apis/*` 仍然有效，是长期凭据。
  - 另有阿里云 WAF 的 `acw_tc` Cookie（30 分钟），随请求带上即可。
- **登录后导航**：首页导航栏的下拉菜单 `.dropdown-menu` 里有 `a.dropdown-item`：`/u/<id>`（个人信息）、`/feed/`（我的关注）、`/albums/purchases/`（全部订单）、`/albums/msgbox/`（收件箱）、`/albums/logout`（退出登录）。菜单按钮 `#dropdownMenu2` 里是头像（`!labellittle` 样式），没有昵称。
- **用户页**（HTML）：`/u/<id>/music`（已购）、`/review`（repo）、`/following`（关注的社团）、`/likes`（点赞过的专辑）、`/deflate`、`/options`。页头左列是头像原图，右列 `h1` 是昵称、`h2` 是「dizzylab的第 N 位用户，加入于…」。
- **已购专辑** `/u/<id>/music/?page=<n>[&q=<关键词>]`：
  - **不登录也能看到**任何用户的已购列表；只有以本人身份登录时，页面脚本里才有 `var token = '…'`，卡片底部才有「购买于 YYYY-MM-DD」。
  - 专辑卡片在 `#discs` 里：封面链接 `a[href="/d/<id>"]` 内有 `.album_cover img[data-src]`，Hi-Res 专辑另有 `static/hires.jpg` 角标；卡片底部 `[onclick="updateplayer('<id>')"]` 的 `title` 是专辑名，`h4 a[href^="/l/"]` 是社团。
  - 分页在 `#profile-music-pagination`，和其他列表一样有「下一页」按钮。
- **会话是否有效**：带会话 Cookie 请求本人的已购专辑页，看页面里有没有 token。
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

### M4 只读核验与实现约束

2026-09-26 再次核验普通 ALCD0001、优惠 KSEP-001、免费 fx4、兑换 ALCD0003，以及已登录的 ALCD0001 页面：

- 首次购买表单为 `#modalcheckout #yourprice`，最低价取 `min`，默认金额取 `value`；同面板脚本 `discprice` 是折后价。优惠示例原价 40、现价与最低价 18。
- 已购追加支持为 `#modalcheckoutboost #yourprice_boost`，当前最低 1 元、默认 10 元。该表单没有发布累计 BOOST 百分比，不用专辑原价猜算。
- 免费页面最低价与基价均为 0。兑换页面依然嵌入看似有效的隐藏付款表单，因此需同时验证可见购买入口；含收货字段的实体商品不在 M4 范围。
- 附言是 `#ordercommit` / `#ordercommit_boost`，`maxlength=100`。所有查询值按 URL 参数分别编码，金额按整数分保存。
- 数字已付订单为 `/albums/purchases/`，追加 BOOST 为 `/albums/purchases/boost/`，必须分别取快照。页面当前账号从导航确认，活动页签标明类型，卡片含专辑链接、价格、购买日期和订单号。
- 观察到单张订单号包含账号、专辑和上海时区的秒级创建时间；历史购物车订单使用另一种编号。历史和未知编号计入基线，但不能仅凭“新出现”判定支付成功。
- 后续已用真实付款记录确认非空 BOOST 卡片：价格字段与数字订单一致，订单编号为 `dizz_boost_<账号>_<专辑>_<yyyy-MM-dd-HH-mm-ss>_<后缀>`；普通单张购买没有 `boost_` 字段。类型错误的编号不能作为到账证据。原待核验记录经此修复后已在真机核验成功。
- 支付宝 H5 页面返回网站与返回 App 是两种路由。NeoDizzy 接收 `neodizzy-pay://safepay`，只为已识别 SafePay 信封设置 `fromAppUrlScheme`，或替换已存在的外层 `MQPSourceAppScheme`。不改写签名订单里的 `return_url`；未知格式保留原始跳转，可能仍需手动返回 App。实际支付宝支付后的完整自动回跳尚待验收。测试不访问 `checkout_alipay`，不会创建订单。

## 社区

| 操作 | 请求 |
| --- | --- |
| 点赞 / 取消点赞专辑 | `POST /albums/ilikethisornot/`，字段 `discid`、`csrfmiddlewaretoken` |
| 发短评 | `POST /albums/postdisccomment/` |
| 删自己的短评 | `POST /albums/deletemycomment/` |
| 长评点赞 | `/ilikethisreviewornot/` |
| 随便听听 | `POST /getatrack/`，字段 `csrfmiddlewaretoken`；返回 `discid`、`thisurl`、`thistrack`、`disctitle`、`disclabel`、`disccover`、`taglist` 等 |
| 关注 / 取关社团 | `GET /l/<社团名>/?ilikeit` / `?dislike`（需会话 Cookie） |

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

### M5 再核验（2026-09-26）

- 短评读取：`GET /albums/getdisccomment/?discid=&l=&r=`，每页 6 条。平行数组为 `disc_comment`、`user_names`、`user_url`、`avatar_url`、`prebuyer`、`redeemit`，另有 `canshowmore`。用户链接可能使用 `/albums/u/<id>`。
- 发短评字段为 `discid`、`comment`、`csrfmiddlewaretoken`；删自己的短评只需 `discid` 和 CSRF，不使用他人的评论 ID。当前页面的 `#comment_txt_box` 与 `deletemycomment()` 控件用于判断可发 / 可删；上限按页面提示为 140 字。写入结果通过重新取专辑页确认。
- 关注按钮 `button[name=likeit-on]` 对应 `?ilikeit`，已关注 `likeit-off` 对应 `?dislike`。旧记录的 `?like` 不正确。只接受这两个同页参数，操作前校验登录用户，操作后重新读取状态。
- repo 列表每页 3 条；`review_id`、`review_title`、`review_desc`、`user_id`、`user_name`、`user_avatar`、`add_date` 均为平行数组。拒绝不等长数组，避免把正文归到错误作者。
- `/review/<id>/` 正文在 `#reviewlikes` 按钮的父按钮组所在 `.card-body`，标题为其中 `h3`、正文为 `p.truncate-limit`；CSS 名字包含 truncate 但 HTML 是完整正文。图片原生显示，回复保留网站入口。
- 用户页四个页签分别为 `music` / `review` / `following` / `likes`，用 `page` 翻页。浏览他人已购列表不会据此授予当前用户播放或下载权限。
- 随机曲目包含 `thisauther`、`rndnum`、`full`、`gotourl` 等字段；播放曲号从已校验的 streaming URL 文件名取得，`thistrack` 的曲号前缀从显示标题移除。
- 真机已完成上述读取、解析和页面显示检查。发短评、删短评、点赞和关注的网络写入用 mock 验证；没有在真实账户上自动执行这些操作，仍待用户验收。
