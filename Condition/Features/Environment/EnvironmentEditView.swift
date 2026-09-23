// EnvironmentEditView.swift
// 環境シート（天候・室内・端末気圧）。測定記録と症状記録の両方から開く

import SwiftUI
import UIKit

struct EnvironmentEditView: View {

    /// 編集を終えた結果を返す。キャンセル時は呼ばない
    let onDone: (EnvironmentSnapshot) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var vm: EnvironmentEditViewModel
    /// 1時間以内の再取得で出す、広告視聴の確認
    @State private var showAdGate = false
    /// リワード広告。シートを開いた時点で読み込んでおく
    @StateObject private var adLoader = RewardedAdLoader()

    init(
        snapshot: EnvironmentSnapshot,
        recordDate: Date,
        onDone: @escaping (EnvironmentSnapshot) -> Void
    ) {
        self.onDone = onDone
        _vm = State(initialValue: EnvironmentEditViewModel(
            snapshot: snapshot, recordDate: recordDate
        ))
    }

    var body: some View {
        NavigationStack {
            Form {
                fetchButtonSection
                outdoorSection
                indoorSection
                devicePressureSection
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 4) {
                        Image(systemName: "cloud.sun.fill")
                        Text("environment.title")
                    }
                    .font(.headline)
                    // シートのタイトルは通常のラベル色にする（他のシートと揃える）
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                    .fixedSize()
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("environment.title"))
                }
                ToolbarItem(placement: .topBarLeading) {
                    // 下向き矢印はシートを下へ閉じる操作と向きが一致する。
                    // 入力は閉じた時点で反映されるので確定/破棄の二択にしない
                    // （症状・対処シートと同じ作法）。
                    // 破棄したいときは、呼び出し元の症状シートでキャンセルする。
                    // 反映は onDisappear に任せ、スワイプで閉じた場合と揃える
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .accessibilityLabel(Text("action.close"))
                }
            }
        }
        // 下の記録画面と同じ灰色だと、どちらを操作しているのか分からなくなる。
        // 天候のシートなので青緑を淡く混ぜ、症状(青)・対処(橙)とも区別する
        .presentationBackground(Color.azTintedSheetBackground(.systemTeal))
        // 閉じ方によらず入力を反映する（閉じるボタン・スワイプのどちらでも同じ）
        .onDisappear { onDone(vm.snapshot()) }
        .onAppear {
            // 押してから読み込むと待たせるので、先に用意しておく。
            // 無料で取れる間は広告が要らないため読み込まない
            if !vm.canFetchWithoutAd { adLoader.preload() }

            // 視聴完了でだけ取得を通す
            adLoader.onRewardEarned = {
                vm.grantAdReward()
                Task { await vm.fetchAll() }
            }
            // 在庫が無い・表示できないのはユーザーの責任ではないので取得を通す
            // （設計書 6.7-4）
            adLoader.onUnavailable = {
                vm.grantAdReward()
                Task { await vm.fetchAll() }
            }
            // 途中で閉じたときは何も起きない（再タップでやり直せる）
            adLoader.onDismissed = {}
        }
        // .sheet では App の dynamicTypeSize が届かないことがあるため明示する
        .azAppFontScale()
    }

    /// 観測時刻の書式。日付列に添えるので最短にする（9/24 0:00）。
    /// 年は出さない（保持期間が短く、記録日時から明らかなため）
    private static let observedFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("Mdjm")
        return f
    }()

    // MARK: - 取得ボタン

    /// 取得ボタンの色。取得できない時は灰色、広告を挟む時は少し暗くして
    /// 「いつもと同じ1タップではない」ことを色でも示す
    private var fetchButtonColor: Color {
        guard vm.canFetchAny else { return .gray }
        return vm.canFetchWithoutAd ? .accentColor : .indigo
    }

    /// 取得は入力行ではなく「操作」なので、屋外セクションの外に出して
    /// 塗りつぶしのカプセルで見せる。1つのボタンで気象データと端末気圧を順に取る
    private var fetchButtonSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    // 前回の取得から1時間以内なら、先に広告を見てもらう
                    if vm.canFetchWithoutAd {
                        Task { await vm.fetchAll() }
                    } else {
                        showAdGate = true
                    }
                } label: {
                    HStack(spacing: 8) {
                        if vm.isFetching {
                            ProgressView().tint(.white)
                        } else {
                            // 広告を挟むときは再生マークにして、押す前に気づけるようにする
                            Image(systemName: vm.canFetchWithoutAd
                                  ? "location.fill" : "play.rectangle.fill")
                        }
                        Text(vm.isFetching ? "symptom.weather.fetching" : "symptom.weather.fetchJMA")
                            .fontWeight(.semibold)
                    }
                    .lineLimit(1)
                    // 端に文字が触れないよう左右に余白を取り、
                    // 収まらないぶんは文字を縮めて1行に保つ
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(.white)
                    .padding(.vertical, 11)
                    .padding(.horizontal, 20)
                    .frame(maxWidth: .infinity)
                    .background(fetchButtonColor)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(vm.isFetching || !vm.canFetchAny)

                // 広告を挟むときだけ、その条件を押す前に知らせる。
                // 無料で取れる間は出さない（読む必要が無いため）
                if vm.canFetchAny, !vm.canFetchWithoutAd {
                    Text("environment.help.fetchInterval")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .confirmationDialog(
                Text("environment.adGate.title"),
                isPresented: $showAdGate,
                titleVisibility: .visible
            ) {
                Button("environment.adGate.watch") { adLoader.present() }
                Button("action.cancel", role: .cancel) {}
            } message: {
                Text("environment.adGate.message")
            }
        }
        // セクションの枠を出さず、カプセルだけを見せる
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 4, trailing: 16))
        .listRowBackground(Color.clear)
    }

    // MARK: - 屋外

    private var outdoorSection: some View {
        Section {
            if !vm.canFetchJMA {
                Text("symptom.weather.outOfRangeHint")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let message = vm.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }

            // 気温は2桁打った時点で小数点を入れる（302 → 30.2）
            // 範囲は世界の観測記録を少し上回る程度に取り、打ち間違いだけを弾く
            numberRow("symptom.weather.outdoorTemp", text: $vm.tempText,
                      decimal: true, allowsNegative: true, unit: "℃",
                      autoDecimalAfter: 2, range: -50...60)
            numberRow("symptom.weather.outdoorHumidity", text: $vm.humidityText,
                      decimal: false, unit: "%", range: 0...100)
            numberRow("symptom.weather.pressure", text: $vm.pressureText,
                      decimal: true, unit: "hPa", range: 870...1085)

            if let delta = vm.pressureDelta24h_10hpa {
                LabeledContent("symptom.weather.pressureDelta") {
                    Text(String(format: "%+.1f hPa", Double(delta) / 10))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            // 取得前は出さない。空欄を見せても何を入れるのか分からず、
            // 気象データを取ると自動で埋まる。手入力した値があるときも出す
            if !vm.place.isEmpty || vm.source.isPresent {
                // 取得元の観測所名なので編集させない。
                // 直しても観測値そのものは変わらず、出典と食い違うだけになる
                LabeledContent("symptom.weather.place") {
                    HStack(spacing: 6) {
                        Text(vm.place)
                        // いつの観測値かが分かるよう時刻を添える。
                        // アメダスは10分ごとなので記録時刻とは少しずれる
                        if let observedAt = vm.observedAt {
                            Text(Self.observedFormatter.string(from: observedAt))
                                .monospacedDigit()
                        }
                    }
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                }
            }
        } header: {
            Text("environment.section.outdoor")
        } footer: {
            outdoorFooter
        }
    }

    /// 観測所と出典。別地点の値であることを隠さない
    @ViewBuilder
    private var outdoorFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !vm.stationName.isEmpty {
                Text(String(
                    format: String(localized: "symptom.weather.stationNote"),
                    vm.stationName
                ))
            }
            // 気圧観測所は全国154か所しかなく、気温側と別地点になることが多い
            if !vm.pressureStationName.isEmpty, let distance = vm.pressureDistanceKm {
                Text(String(
                    format: String(localized: "symptom.weather.pressureStationNote"),
                    vm.pressureStationName, distance
                ))
            }
            if vm.source == .jma {
                Text("symptom.weather.jmaAttribution")
            }
        }
    }

    // MARK: - 室内

    private var indoorSection: some View {
        Section {
            // 室温も気温と同じく2桁で小数点を入れる
            // 室温は屋外より狭く取る（暖房のない寒冷地〜冷房のない酷暑）
            numberRow("symptom.weather.indoorTemp", text: $vm.indoorTempText,
                      decimal: true, allowsNegative: true, unit: "℃",
                      autoDecimalAfter: 2, range: -20...50)
            numberRow("symptom.weather.indoorHumidity", text: $vm.indoorHumidityText,
                      decimal: false, unit: "%", range: 0...100)
        } header: {
            // ヘルプは見出しの右に置く。屋外の気温より優先されることは
            // 入力欄を見ただけでは分からないので、開いて読めるようにする
            HStack(spacing: 6) {
                Text("symptom.section.indoor")
                BeginnerHelpBanner(
                    "symptom.help.indoor",
                    storageKey: "helpDismissed.symptom.indoor",
                    compact: true,
                    tight: true
                )
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - デバイス

    /// 気圧計の無い端末でもセクション自体は出す。
    /// 隠すと「この機能が無い」のか「見落としたのか」を利用者が判別できないため
    private var devicePressureSection: some View {
        Section {
            if DevicePressureService.isAvailable {
                // 取得は屋外セクションのボタンがまとめて行う。ここは結果を見せるだけ
                LabeledContent("environment.device.pressure") {
                    if vm.devicePressure_10hpa != 0 {
                        Text(String(format: "%.1f hPa", Double(vm.devicePressure_10hpa) / 10))
                            .monospacedDigit()
                    } else {
                        Text("environment.summary.empty")
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                // 気圧計を積んでいない機種、または OS が対応していない場合
                LabeledContent("environment.device.pressure") {
                    Text("environment.device.unavailable")
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text(Self.deviceSectionTitle)
        }
    }

    private static var deviceSectionTitle: String {
        String(localized: "environment.section.device")
    }

    // MARK: - 部品

    /// 数値入力の行。システムのキーボードではなく専用テンキーを出す。
    /// 気温・室温は氷点下があるので符号キーを付ける
    private func numberRow(
        _ titleKey: LocalizedStringKey,
        text: Binding<String>,
        decimal: Bool,
        allowsNegative: Bool = false,
        unit: String? = nil,
        autoDecimalAfter: Int? = nil,
        range: ClosedRange<Double>
    ) -> some View {
        EnvNumpadField(
            titleKey: titleKey,
            text: text,
            decimal: decimal,
            allowsNegative: allowsNegative,
            unit: unit,
            autoDecimalAfter: autoDecimalAfter,
            range: range
        )
    }
}
