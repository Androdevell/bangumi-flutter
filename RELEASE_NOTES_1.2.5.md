# 1.2.5+2025

修复编辑个人资料时被拒绝为 `profileFormInvalid` 的兼容性问题，以及首次加载错误直接显示内部英文键名的问题。

- 对照已登录设置页的表单结构，并参考原项目从当前页面／已登录账号取 formhash 的方式：不再仅因隐藏字段为空就拒绝完整表单。
- 优先采用表单已有值，再使用当前页面同站校验链接或当前账号保存的值；拒绝外站、含凭据的地址和冲突值。资料字段不完整时仍禁止编辑，不会补空值覆盖资料。
- 明确区分网页登录失效、网页访问被拒绝／需要验证、限流、网络读取失败及缺少校验信息，提示覆盖中文、英文、日文。
- 保存后跳转必须同源；结果未知不自动重发，保存仍回读核对。

参考：[原项目资料解析](https://github.com/xiaoyvyv/bangumi/blob/main/shared/data/src/commonMain/kotlin/com/xiaoyv/bangumi/shared/data/parser/bgm/UserParser.kt)、[原项目 formhash 解析](https://github.com/xiaoyvyv/bangumi/blob/main/shared/core/src/commonMain/kotlin/com/xiaoyv/bangumi/shared/core/utils/Parser.kt)。

本次浏览器只读查看了设置页，没有点击保存、修改个人资料或读取 Cookie。自动化保存验证仅使用模拟服务，不代表已经替用户完成真实资料修改。

静态检查无问题；完整 Flutter 回归 241 项通过，6 项联网探针按配置跳过。新增测试覆盖空隐藏字段、当前会话补取、同源来源、字段不完整、登录过期、外站跳转、HTTP 错误分类和三语首次加载错误。

Android ARM64 的 versionCode 从 2024 升至 2025，沿用原签名及用户确认的旧 OAuth。Windows 请完整解压后运行 `windows-x64/bangumi_flutter.exe`。
