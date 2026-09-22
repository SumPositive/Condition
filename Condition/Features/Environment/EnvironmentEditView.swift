// EnvironmentEditView.swift
// 環境シート（天候・室内・端末気圧）。測定記録と症状記録の両方から開く

import SwiftUI
import UIKit

struct EnvironmentEditView: View {

    /// 編集を終えた結果を返す。キャンセル時は呼ばない
    let onDone: (EnvironmentSnapshot) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var vm: EnvironmentEditViewModel

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
                    .foregroundStyle(Color.accentColor)
                    .lineLimit(1)
                    .fixedSize()
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("environment.title"))
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("action.cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("action.done") {
                        onDone(vm.snapshot())
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - 屋外

    private var outdoorSection: some View {
        Section {
            if vm.isFetching {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("symptom.weather.fetching").foregroundStyle(.secondary)
                }
            } else {
                Button {
                    Task { await vm.fetchFromJMA() }
                } label: {
                    Label("symptom.weather.fetchJMA", systemImage: "location.fill")
                }
                .disabled(!vm.canFetchJMA)
                if !vm.canFetchJMA {
                    Text("symptom.weather.outOfRangeHint")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if let message = vm.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }

            numberRow("symptom.weather.outdoorTemp", text: $vm.tempText, decimal: true)
            numberRow("symptom.weather.outdoorHumidity", text: $vm.humidityText, decimal: false)
            numberRow("symptom.weather.pressure", text: $vm.pressureText, decimal: true)

            if let delta = vm.pressureDelta24h_10hpa {
                LabeledContent("symptom.weather.pressureDelta") {
                    Text(String(format: "%+.1f hPa", Double(delta) / 10))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            LabeledContent("symptom.weather.place") {
                TextField("", text: $vm.place)
                    .multilineTextAlignment(.trailing)
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
            numberRow("symptom.weather.indoorTemp", text: $vm.indoorTempText, decimal: true)
            numberRow("symptom.weather.indoorHumidity", text: $vm.indoorHumidityText, decimal: false)
        } header: {
            Text("symptom.section.indoor")
        } footer: {
            Text("symptom.section.indoor.footer")
        }
    }

    // MARK: - デバイス

    /// 気圧計の無い端末でもセクション自体は出す。
    /// 隠すと「この機能が無い」のか「見落としたのか」を利用者が判別できないため
    private var devicePressureSection: some View {
        Section {
            if DevicePressureService.isAvailable {
                if vm.devicePressure_10hpa != 0 {
                    LabeledContent("environment.device.pressure") {
                        Text(String(format: "%.1f hPa", Double(vm.devicePressure_10hpa) / 10))
                            .monospacedDigit()
                    }
                }
                Button {
                    Task { await vm.fetchDevicePressure() }
                } label: {
                    Label("symptom.weather.measureDevicePressure", systemImage: "barometer")
                }
                .disabled(!vm.canFetchDevicePressure)
            } else {
                // 気圧計を積んでいない機種、または OS が対応していない場合
                LabeledContent("environment.device.pressure") {
                    Text("environment.device.unavailable")
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text(Self.deviceSectionTitle)
        } footer: {
            Text("environment.section.device.footer")
        }
    }

    private static var deviceSectionTitle: String {
        String(localized: "environment.section.device")
    }

    // MARK: - 部品

    private func numberRow(
        _ titleKey: LocalizedStringKey,
        text: Binding<String>,
        decimal: Bool
    ) -> some View {
        LabeledContent(titleKey) {
            TextField("", text: text)
                // 気温は氷点下があるので符号を打てるキーボードにする
                .keyboardType(decimal ? .numbersAndPunctuation : .numberPad)
                .multilineTextAlignment(.trailing)
        }
    }
}
