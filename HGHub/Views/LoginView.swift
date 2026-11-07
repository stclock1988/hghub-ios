// HGHub iOS — Login / register (map §4).
// Username 4–20 chars [A-Za-z0-9_] (register); password 6–20 chars.
// The server validates the rules; the client only checks the fields
// are non-empty and the two passwords match.

import SwiftUI

struct LoginView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var auth: AuthStore

    @State private var mode = 0 // 0 = 登录, 1 = 注册
    @State private var username = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var email = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Picker("方式", selection: $mode) {
                    Text("登录").tag(0)
                    Text("注册").tag(1)
                }
                .pickerStyle(.segmented)

                Section {
                    TextField("用户名", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("密码", text: $password)
                    if mode == 1 {
                        SecureField("确认密码", text: $confirmPassword)
                        TextField("邮箱（可选）", text: $email)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.emailAddress)
                    }
                } footer: {
                    if mode == 1 {
                        Text("用户名 4–20 位（字母、数字、下划线）；密码 6–20 位，须含字母和数字。")
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .font(.subheadline)
                    }
                }

                Section {
                    Button(mode == 0 ? "登录" : "注册") {
                        Task { await submit() }
                    }
                    .disabled(!canSubmit || isWorking)
                }
            }
            .navigationTitle(mode == 0 ? "登录" : "注册")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    private var canSubmit: Bool {
        guard !username.isEmpty, !password.isEmpty else { return false }
        if mode == 1, password != confirmPassword { return false }
        return true
    }

    private func submit() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            if mode == 0 {
                try await auth.login(username: username, password: password)
            } else {
                try await auth.register(
                    username: username, password: password,
                    confirmPassword: confirmPassword,
                    email: email.isEmpty ? nil : email
                )
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
