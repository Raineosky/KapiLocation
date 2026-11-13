import SwiftUI

struct SpeedControlsSection: View {
    @EnvironmentObject private var session: SpoofSession
    @State private var speedInput = ""
    @State private var inputError: String?

    var body: some View {
        Section {
            Toggle("啟用自訂速度", isOn: $session.useCustomSpeed)
            if session.useCustomSpeed {
                HStack {
                    TextField("速度（km/h）", text: $speedInput)
                        .keyboardType(.decimalPad)
                        .onSubmit(saveSpeed)
                    Button("套用", action: saveSpeed)
                }
                if let inputError {
                    Text(inputError).font(.caption).foregroundStyle(.red)
                }
                Slider(value: $session.customSpeedKmh, in: 0.1...300, step: 0.1)
                    .accessibilityLabel("速度，公里每小時")
                HStack {
                    ForEach([3.0, 5.0, 10.0, 20.0, 60.0], id: \.self) { value in
                        Button(String(format: "%.0f", value)) {
                            session.customSpeedKmh = value
                            inputError = nil
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            LabeledContent("目前基準速度", value: session.speedLabel)
            Toggle("速度隨機波動 ±10%", isOn: $session.speedVariation)
        } header: {
            Text("移動速度")
        } footer: {
            Text("輸入 0.1～300 km/h 後按「套用」。路線移動即時採用新設定；搖桿未推到底時會按幅度減速。速度為模擬目標值，實際更新受連線延遲及 iOS 背景排程影響。")
        }
        .onAppear { syncInput() }
        .onChange(of: session.customSpeedKmh) { _, _ in syncInput() }
    }

    private func syncInput() { speedInput = String(format: "%.1f", session.customSpeedKmh) }
    private func saveSpeed() {
        let normalized = speedInput.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value.isFinite, (0.1...300).contains(value) else {
            inputError = "請輸入 0.1～300 之間的數值。"
            return
        }
        session.customSpeedKmh = value
        inputError = nil
    }
}
