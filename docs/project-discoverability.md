# Bangumi Flutter 检索与公开入口

核查日期：2026-11-02（Asia/Taipei）。

## 已核实

- Android 包名为 `com.bgm.irena`，来源为本仓库 `android/app/build.gradle.kts` 的 `applicationId`。
- 本地独立仓库的 origin 为 <https://github.com/Androdevell/bangumi-flutter>，可公开访问；它与外层 `xiaoyvyv/bangumi` 仓库不是同一个远端。
- 公开下载入口为 <https://github.com/Androdevell/bangumi-flutter/releases/latest>。
- 本次精确检索 `"com.bgm.irena"`、`"Irena" "Bangumi"` 未获得匹配该应用的结果；这仅描述本次搜索服务的结果，不能据此认定所有搜索引擎都未收录。
- 核查时公开 README 标题为 Bangumi Flutter，未写出 Android 包名；About 为英文描述。按包名或 Irena 检索与按仓库名检索可能得到不同结果。

## 本次文档修改

README 首屏增加“番组计划 / bgm.tv”、Android 与 Windows、核心用途以及准确包名，同时直接链接源码与最新版。没有更改应用显示名、包名、签名或发行版本。上述内容随本次文档提交发布；远端内容更新不代表 Google 已重新抓取或收录。

## 可直接使用的仓库元信息

GitHub About 建议：

> Bangumi Flutter：番组计划 / bgm.tv 第三方客户端，支持 Android 与 Windows、追番进度、收藏同步和社区浏览。Android package: com.bgm.irena.

Topics 建议（只填写实际相关的主题）：

`bangumi`、`bgm`、`flutter`、`dart`、`android`、`windows`、`anime`、`anime-tracker`、`bangumi-client`。

固定对外介绍与下载地址，避免只发送 APK 文件或只有包名。社区介绍可以使用下文，但请由维护者核对后自行发布：

> Bangumi Flutter 是一款面向 Android 11+ 和 Windows 的非官方番组计划（Bangumi / bgm.tv）客户端，提供每日放送、作品检索、追番与章节进度、收藏同步、时间线和小组社区功能。Android 包名为 com.bgm.irena。源码与下载：https://github.com/Androdevell/bangumi-flutter

## 如何判断改善是否生效

发布 README 与元信息后，先确认公开页面能看到上述文字，再分别检索 `"com.bgm.irena"`、`Bangumi Flutter Androdevell`、`番组计划 Flutter Windows`。收录时间与排名由搜索服务决定，不能承诺立刻生效；不要用堆砌无关关键词或伪造下载量替代准确介绍。

参考：[GitHub Topics 官方说明](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/classifying-your-repository-with-topics)。

## Google 专项核查

用户提供了 Google 实际搜索截图：`site:github.com/Androdevell/bangumi-flutter` 显示无匹配结果。这是该查询当时无搜索展示的直接证据，应优先继续核查发现与索引；仍不能仅凭 site: 结果断定完全未收录，也不能据此承诺任何排名。

用户确认实际使用的搜索引擎为 Google，关键词为 `bangumi flutter`。本轮直接打开 Google 搜索页失败：检索工具不可访问 Google SERP，内置浏览器连接超时，Chrome 自动化后端不可用。因此，先前普通搜索工具的返回结果不能当作 Google 的实时结果或排名证据。

公开仓库页面本轮 HTTP 响应为 200；未检测到 X-Robots-Tag 或 robots meta 中的 noindex。这个结果只适用于本轮请求，不代表 Googlebot 一定能抓取或 Google 一定会收录。

下一步在用户实际使用的 Google 环境中核对：

1. 搜索 `site:github.com/Androdevell/bangumi-flutter`。若出现该仓库，是部分收录线索；若没出现，仍不能直接认定未收录，因为 site: 结果不保证完整。
2. 再搜索 `"bangumi-flutter" "Androdevell"`，观察精确名称是否可见。
3. 若精确检索可见而 `bangumi flutter` 不可见，优先按通用词的相关性与排名问题处理；如果精确检索也不可见，应继续核查发现与索引情况，不能只保证等几天就会出现。

仓库首页已有 Bangumi Flutter 标题，不能仅把问题归因于缺少这两个词。README、About 和 Topics 的改进可提高信息清晰度，但不能保证 Google 排名。Google Search Console 的 URL 检查需要已验证的站点权限；不要把“能编辑 GitHub 仓库”等同于“能验证 github.com 的站点权限”。如果后续建立可验证的项目介绍站点，再针对该站点进行 URL 检查和提交。

官方依据：[Google site: 运算符的限制](https://developers.google.com/search/docs/monitor-debug/search-operators/all-search-site)、[重新抓取与权限要求](https://developers.google.com/search/docs/crawling-indexing/ask-google-to-recrawl)。

### 优先处理顺序

1. 本次提交包含 README 改动；发布后先确认公开仓库能看到新内容，再观察搜索展示变化。
2. 在 GitHub About 中采用上面的准确描述，Topics 补充 bangumi、flutter、dart、android、windows 等实际相关主题。这有助于项目分类与理解，不构成 Google 收录保证。
3. 在自己的公开主页或真实开发介绍中，使用“Bangumi Flutter · 番组计划客户端”作为链接文字指向仓库。社区发布文案已在本文准备，维护者确认后自行发布，不自动向第三方发帖。
4. 若希望获得可验证的索引诊断入口，再建立项目介绍站点（GitHub Pages 或自有域名），通过 Google Search Console 验证该站点、检查具体 URL 并请求索引。介绍页应提供真实截图、用途、平台、源码和下载入口，不伪造评价或堆砌关键词；站点索引与 GitHub 仓库索引需要分别看待。

本轮针对公开仓库 HTML 再次检查：HTTP 200，标题包含 Bangumi 和 Flutter，未发现 noindex。未找到能在当前项目源码中直接修复的“禁止搜索引擎索引”开关；不能把 Google 的抓取、索引与排名决定描述为已经修复的应用 bug。
