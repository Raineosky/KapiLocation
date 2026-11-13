import SwiftUI

struct PairOnDeviceView: View {
    enum Mode {
        /// Settings sheet — Close toolbar, dismiss on Done.
        case sheet
        /// First-run setup — no toolbar; calls `onFinished` after success.
        case embedded
    }

    @EnvironmentObject private var pairing: PairingStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var host = PairOnDeviceService()

    var mode: Mode = .sheet
    var onFinished: (() -> Void)?

    var body: some View {
        Group {
            if mode == .sheet {
                NavigationStack {
                    scrollContent
                        .background(Color.black.ignoresSafeArea())
                        .navigationTitle("在這支 iPhone 上配對")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("關閉") {
                                    host.resetToIdle()
                                    dismiss()
                                }
                            }
                        }
                }
            } else {
                scrollContent
            }
        }
        .onChange(of: host.phase) { _, phase in
            if case .succeeded = phase {
                pairing.refresh()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, host.isBusy {
                _ = host.pin
            }
        }
    }

    private var scrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if mode == .sheet {
                    header
                } else {
                    embeddedIntro
                }

                steps

                statusCard

                if mode == .sheet {
                    tipCard
                }

                actions
            }
            .padding(mode == .embedded ? 16 : 20)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("不需要電腦")
                .font(.title2.weight(.bold))
            Text("卡皮定位會在本機啟動配對。iOS 從開發者模式連線後，程式會顯示六位數代碼。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var embeddedIntro: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("請依照以下步驟操作")
                .font(.headline)
            Text("請保持卡皮定位開啟；稍後到系統設定完成配對。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 12) {
            step(1, "點選「開始配對」，並允許區域網路及定位權限。")
            step(2, "允許通知，配對碼即可顯示於系統設定上方。")
            step(3, "打開「設定 › 隱私權與安全性 › 開發者模式 › 與卡皮定位配對」。")
            step(4, "先輸入 iPhone 解鎖密碼，再於下一個提示輸入六位數配對碼。")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .locusGlass(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.black)
                .frame(width: 22, height: 22)
                .background(LocusTheme.accent, in: Circle())
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
    }

    private var tipCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("尚未顯示配對碼？", systemImage: "lightbulb.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(LocusTheme.accentSecondary)
            Text("在開發者模式確認配對時保持程式執行。若配對項目消失，請重新開始配對並再次進入開發者模式。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LocusTheme.accentSecondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private var statusCard: some View {
        VStack(spacing: 14) {
            switch host.phase {
            case .idle:
                Label("準備開始配對", systemImage: "antenna.radiowaves.left.and.right")
                    .foregroundStyle(.secondary)
            case .advertising:
                ProgressView()
                Text("正在等待系統設定…")
                    .font(.headline)
                Text("在開發者模式點選與卡皮定位配對。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            case .deviceConnected:
                ProgressView()
                Text("iPhone 已連線")
                    .font(.headline)
                Text("正在產生六位數配對碼…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .awaitingPIN(let pin):
                Text("請在系統設定輸入這組配對碼")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(pin)
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .tracking(10)
                    .monospacedDigit()
                    .foregroundStyle(LocusTheme.accent)
                    .textSelection(.enabled)
                Text("請先輸入解鎖密碼，再於第二個視窗輸入此配對碼。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            case .succeeded:
                Image(systemName: "checkmark.seal.fill")
                    .font(.largeTitle)
                    .foregroundStyle(LocusTheme.statusGood)
                Text("配對完成")
                    .font(.title3.weight(.bold))
                Text(mode == .embedded
                     ? "接下來設定 LocalDevVPN。"
                     : "RPPairing 已儲存。連接 LocalDevVPN 後即可瞬移。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            case .failed(let message):
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(LocusTheme.statusWarn)
                Text("配對失敗")
                    .font(.title3.weight(.bold))
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .locusGlass(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder
    private var actions: some View {
        switch host.phase {
        case .idle, .failed:
            Button {
                host.acknowledgeFailure()
                host.start(pairingStore: pairing)
            } label: {
                Text(host.phase == .idle ? "開始配對" : "再試一次")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Capsule().fill(LocusTheme.accent))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        case .succeeded:
            Button {
                if let onFinished {
                    onFinished()
                } else {
                    dismiss()
                }
            } label: {
                Text(mode == .embedded ? "繼續" : "完成")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Capsule().fill(LocusTheme.accent))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        case .advertising, .deviceConnected, .awaitingPIN:
            Text({
                switch host.phase {
                case .awaitingPIN: return "請在系統設定的第二個提示輸入上方配對碼。"
                case .deviceConnected: return "已連線，即將顯示配對碼。"
                default: return "等待 iOS 連線，請勿強制關閉卡皮定位。"
                }
            }())
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
        }
    }
}
