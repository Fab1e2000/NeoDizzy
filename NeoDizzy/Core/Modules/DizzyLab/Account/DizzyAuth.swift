import Foundation

/// 用网页的登录表单登录（流程见 docs/SITE_API.md「账号」）。密码只放进这一次请求，不保存。
nonisolated struct DizzyAuth: Sendable {
    let client: DizzyHTTPClient

    init(client: DizzyHTTPClient = .shared) {
        self.client = client
    }

    /// 成功后 `client.credentials` 里是会话 Cookie 和 token；失败时清空。
    func login(username: String, password: String) async throws -> Account {
        client.credentials.clear()
        do {
            return try await performLogin(username: username, password: password)
        } catch {
            client.credentials.clear()
            throw error
        }
    }

    private func performLogin(username: String, password: String) async throws -> Account {
        // 1. 登录页：拿到 csrftoken Cookie 和表单里的 csrfmiddlewaretoken。
        let loginPage = try await client.html(path: "/albums/login/")
        let csrf = try LoginPageParser.csrfToken(loginPage)

        // 2. 提交表单。成功时网站设置 sessionid，返回 200 而不是跳转，所以要看 Cookie。
        let response = try await client.postForm(
            path: "/albums/login/",
            fields: [
                ("csrfmiddlewaretoken", csrf),
                ("next", ""),
                ("username", username),
                ("password", password),
            ],
            referer: DizzyURL.login.absoluteString
        )
        guard client.credentials.hasCookie(named: "sessionid") else {
            let reason = LoginPageParser.errorMessage(response)
            debugLog("登录失败：\(reason ?? "页面上没有找到原因")，仍在登录页=\(LoginPageParser.isLoginForm(response))")
            throw DizzyError.loginFailed(reason ?? String(localized: "昵称、邮箱或密码不正确"))
        }

        // 3. 首页导航栏里的「个人信息」链接给出用户 ID。
        guard let home = try LoggedInHomeParser.parse(try await client.html(path: "/")) else {
            debugLog("登录后首页没有用户链接")
            throw DizzyError.loginFailed(String(localized: "登录没有成功，请稍后再试"))
        }

        // 4. 已购专辑页：以本人身份登录时页面里有 token，同时拿到昵称和头像。
        let profile = try await DizzyPages(client: client).profileMusic(userID: home.userID)
        guard let token = profile.token else {
            debugLog("已购专辑页里没有 token")
            throw DizzyError.loginFailed(String(localized: "登录没有成功，请稍后再试"))
        }
        client.credentials.setToken(token)

        return Account(
            userID: home.userID,
            nickname: profile.nickname ?? String(localized: "DizzyLab 用户"),
            avatarURL: profile.avatarURL ?? home.avatarURL
        )
    }

    /// 退出登录：让网站结束这个会话。失败也没关系，本地凭据照样清掉。
    func logout() async {
        _ = try? await client.data(path: "/albums/logout")
        client.credentials.clear()
    }
}
