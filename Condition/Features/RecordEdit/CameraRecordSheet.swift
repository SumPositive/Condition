//
//  カメラ記録シート
//  機器表示のOCR、読み取り値の修正、複数回平均をまとめる
//

import SwiftUI
import UIKit
import Vision
import ImageIO
import AVFoundation
import CoreImage
import CoreML

struct CameraRecordSheet: View {
    let fields: [MeasurementAverageField]
    let onSave: @MainActor @Sendable ([MeasurementAverageField: Int]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var readings: [CameraReading] = []
    @State private var alertMessage: String?
    @State private var selectedValue: CameraValueTarget?
    @State private var editingValue: CameraValueTarget?
    @State private var scanSessionID = UUID()
    /// シャッタータップ用トリガ。UUID 更新でカメラ側が次フレームを撮影する
    @State private var captureTrigger: UUID? = nil
    /// 撮影後の review 状態。nil = ライブプレビュー、非nil = 撮影画像+編集UI 表示
    @State private var pendingCapture: PendingCapture? = nil
    /// レビュー時の編集中の値
    @State private var reviewValues: [MeasurementAverageField: Int] = [:]
    /// レビューでタップしたフィールドを Numpad シート表示するための Identifiable wrapper
    @State private var reviewEditingField: ReviewFieldTarget? = nil

    private var averages: [MeasurementAverageField: Int] {
        var result: [MeasurementAverageField: Int] = [:]
        for field in fields {
            let values = readings.compactMap { $0.values[field] }
            guard !values.isEmpty else { continue }
            result[field] = (values.reduce(0, +) + values.count / 2) / values.count
        }
        return result
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let capture = pendingCapture {
                        // レビュー：撮影画像 + 編集可能な数値入力
                        capturedReviewView(capture: capture)
                    } else if CameraLiveScannerView.isCameraAvailable {
                        // ライブプレビュー + シャッターボタン
                        liveCameraView()
                    } else {
                        ContentUnavailableView(
                            "record.camera.unavailable",
                            systemImage: "camera.slash"
                        )
                    }
                }

                Section("record.camera.readings") {
                    if readings.isEmpty {
                        ContentUnavailableView(
                            "record.camera.empty",
                            systemImage: "camera.viewfinder"
                        )
                    } else {
                        ForEach(readings) { reading in
                            CameraReadingRow(
                                reading: reading,
                                fields: fields,
                                onTapValue: { field in
                                    selectedValue = CameraValueTarget(readingID: reading.id, field: field)
                                }
                            )
                        }
                    }
                }

                if !averages.isEmpty {
                    Section("record.camera.average") {
                        ForEach(fields, id: \.self) { field in
                            if let value = averages[field] {
                                LabeledContent {
                                    Text(field.formatted(value))
                                        .monospacedDigit()
                                } label: {
                                    Label(LocalizedStringKey(field.titleKey), systemImage: field.iconName)
                                        .foregroundStyle(field.color)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("record.camera.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("action.save") {
                        onSave(averages)
                    }
                    .disabled(averages.isEmpty)
                    .bold()
                }
            }
            .sheet(item: $editingValue) { target in
                if let binding = valueBinding(for: target) {
                    NumpadInputSheet(
                        value: binding,
                        min: target.field.spec.min,
                        max: target.field.spec.max,
                        decimals: target.field.decimals
                    )
                }
            }
            .sheet(item: $reviewEditingField) { target in
                // レビュー画面でタップしたフィールドを Numpad で編集
                NumpadInputSheet(
                    value: Binding(
                        get: { reviewValues[target.field] ?? target.field.spec.initVal },
                        set: { reviewValues[target.field] = $0 }
                    ),
                    min: target.field.spec.min,
                    max: target.field.spec.max,
                    decimals: target.field.decimals
                )
            }
            .confirmationDialog(
                "record.camera.valueAction",
                isPresented: Binding(
                    get: { selectedValue != nil },
                    set: { if !$0 { selectedValue = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("record.camera.correct") {
                    editingValue = selectedValue
                    selectedValue = nil
                }
                Button("record.camera.removeValue", role: .destructive) {
                    if let selectedValue {
                        removeValue(selectedValue)
                    }
                    selectedValue = nil
                }
                Button("action.cancel", role: .cancel) {
                    selectedValue = nil
                }
            }
            .alert("record.camera.error", isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            )) {
                Button("action.ok", role: .cancel) {}
            } message: {
                Text(alertMessage ?? "")
            }
        }
    }

    @ViewBuilder
    private func liveCameraView() -> some View {
        VStack(spacing: 10) {
            CameraLiveScannerView(
                id: scanSessionID,
                fields: fields,
                captureTrigger: captureTrigger,
                onCapture: handleCapture,
                onError: { message in
                    alertMessage = message
                }
            )
            .frame(minHeight: 260)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(alignment: .bottom) {
                Label("液晶をタップしてピント合わせ", systemImage: "hand.tap")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 12)
            }

            Button {
                // シャッター：トリガを更新するとカメラ側が次フレームを撮影してくる
                captureTrigger = UUID()
            } label: {
                Label("シャッター", systemImage: "camera.aperture")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    private func capturedReviewView(capture: PendingCapture) -> some View {
        VStack(spacing: 12) {
            Image(uiImage: capture.image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 260)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            // OCR の検出状況をユーザに伝える
            if capture.suggested.isEmpty {
                Label("読み取り値を手入力してください", systemImage: "hand.point.up.left")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Label("自動検出した値を確認・修正してください", systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // 各フィールドの入力 (タップで Numpad シート)
            VStack(spacing: 6) {
                ForEach(fields, id: \.self) { field in
                    HStack {
                        Label(LocalizedStringKey(field.titleKey), systemImage: field.iconName)
                            .foregroundStyle(field.color)
                        Spacer()
                        Button {
                            reviewEditingField = ReviewFieldTarget(field: field)
                        } label: {
                            Text(reviewValueDisplay(field))
                                .font(.title3.bold().monospacedDigit())
                                .foregroundStyle(reviewValues[field] == nil ? .secondary : .primary)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            HStack(spacing: 12) {
                Button(role: .cancel) {
                    pendingCapture = nil
                    reviewValues = [:]
                    // 再開のため scanSessionID 更新
                    scanSessionID = UUID()
                } label: {
                    Label("撮り直し", systemImage: "arrow.uturn.backward.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    addReviewedReading()
                } label: {
                    Label("読み取り値に追加", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(reviewValues.isEmpty)
            }
        }
    }

    private func reviewValueDisplay(_ field: MeasurementAverageField) -> String {
        if let value = reviewValues[field] {
            return field.formatted(value)
        }
        return "—"
    }

    private func handleCapture(image: UIImage, values: [MeasurementAverageField: Int]) {
        pendingCapture = PendingCapture(image: image, suggested: values)
        // OCR 推定値で初期化（無ければ空のまま）
        reviewValues = values
    }

    private func addReviewedReading() {
        guard !reviewValues.isEmpty else { return }
        readings.append(CameraReading(values: reviewValues))
        AppAnalytics.shared.logOperation(
            "camera_record_read",
            parameters: ["field_count": reviewValues.count, "reading_count": readings.count, "mode": "capture"]
        )
        pendingCapture = nil
        reviewValues = [:]
        scanSessionID = UUID()
    }

    private func valueBinding(for target: CameraValueTarget) -> Binding<Int>? {
        guard let readingIndex = readings.firstIndex(where: { $0.id == target.readingID }),
              readings[readingIndex].values[target.field] != nil else {
            return nil
        }
        return Binding(
            get: { readings[readingIndex].values[target.field] ?? target.field.spec.initVal },
            set: { readings[readingIndex].values[target.field] = $0 }
        )
    }

    private func removeValue(_ target: CameraValueTarget) {
        guard let readingIndex = readings.firstIndex(where: { $0.id == target.readingID }) else { return }
        readings[readingIndex].values[target.field] = nil
        if readings[readingIndex].values.isEmpty {
            readings.remove(at: readingIndex)
        }
    }
}

private struct CameraReading: Identifiable {
    let id = UUID()
    var values: [MeasurementAverageField: Int]
}

/// 撮影直後・確定前の状態。プレビュー画像と OCR 推定値を保持する
private struct PendingCapture {
    let id = UUID()
    let image: UIImage
    let suggested: [MeasurementAverageField: Int]
}

/// レビュー画面で編集対象を指す Identifiable wrapper（sheet(item:) 用）
private struct ReviewFieldTarget: Identifiable {
    let field: MeasurementAverageField
    var id: String { field.cameraID }
}

private struct CameraValueTarget: Identifiable {
    let readingID: UUID
    let field: MeasurementAverageField

    var id: String { "\(readingID.uuidString)-\(field.cameraID)" }
}

private struct CameraReadingRow: View {
    let reading: CameraReading
    let fields: [MeasurementAverageField]
    let onTapValue: (MeasurementAverageField) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(fields, id: \.self) { field in
                if let value = reading.values[field] {
                    Button {
                        onTapValue(field)
                    } label: {
                        HStack {
                            Label(LocalizedStringKey(field.titleKey), systemImage: field.iconName)
                                .foregroundStyle(field.color)
                            Spacer()
                            Text(field.formatted(value))
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(.primary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct CameraLiveScannerView: UIViewControllerRepresentable {
    let id: UUID
    let fields: [MeasurementAverageField]
    /// シャッタータップで更新される値。Controller がこの変更を検知して次フレームを撮影する
    let captureTrigger: UUID?
    /// 撮影完了時のコールバック: 撮影画像 + OCR 推定値
    let onCapture: @MainActor @Sendable (UIImage, [MeasurementAverageField: Int]) -> Void
    let onError: (String) -> Void

    static var isCameraAvailable: Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil
    }

    func makeUIViewController(context: Context) -> CameraLiveScannerController {
        CameraLiveScannerController(fields: fields, onCapture: onCapture, onError: onError)
    }

    func updateUIViewController(_ uiViewController: CameraLiveScannerController, context: Context) {
        uiViewController.update(fields: fields)
        uiViewController.restartIfNeeded(id: id)
        if let captureTrigger {
            uiViewController.requestCaptureIfNeeded(triggerID: captureTrigger)
        }
    }
}

private final class CameraCaptureSessionBox: @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "Condition.CameraSession")

    func start() {
        queue.async { [self] in
            guard !session.isRunning else { return }
            session.startRunning()
        }
    }

    func stop() {
        queue.async { [self] in
            guard session.isRunning else { return }
            session.stopRunning()
        }
    }
}

private final class CameraLiveScannerController: UIViewController {
    private let sessionBox = CameraCaptureSessionBox()
    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "Condition.CameraLiveScanner")
    private let frameDelegate: CameraLiveScannerFrameDelegate
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var captureDevice: AVCaptureDevice?
    private var fields: [MeasurementAverageField]
    private let onCapture: @MainActor @Sendable (UIImage, [MeasurementAverageField: Int]) -> Void
    private let onError: (String) -> Void
    private var isConfigured = false
    private var isSessionReady = false
    private var currentID: UUID?
    private var lastCaptureTriggerID: UUID?

    init(
        fields: [MeasurementAverageField],
        onCapture: @escaping @MainActor @Sendable (UIImage, [MeasurementAverageField: Int]) -> Void,
        onError: @escaping (String) -> Void
    ) {
        self.fields = fields
        self.onCapture = onCapture
        self.onError = onError
        self.frameDelegate = CameraLiveScannerFrameDelegate(fields: fields, onCapture: onCapture)
        super.init(nibName: nil, bundle: nil)
    }

    func requestCaptureIfNeeded(triggerID: UUID) {
        guard triggerID != lastCaptureTriggerID else { return }
        lastCaptureTriggerID = triggerID
        frameDelegate.requestCapture()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureIfNeeded()
        // タップで focus / exposure を液晶の位置にロックする
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleFocusTap(_:)))
        view.addGestureRecognizer(tap)
    }

    @objc private func handleFocusTap(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: view)
        guard let previewLayer, let device = captureDevice else { return }
        let devicePoint = previewLayer.captureDevicePointConverted(fromLayerPoint: point)
        applyFocusAndExposure(device: device, at: devicePoint)
        showFocusRing(at: point)
    }

    private func applyFocusAndExposure(device: AVCaptureDevice, at devicePoint: CGPoint) {
        do {
            try device.lockForConfiguration()
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = devicePoint
            }
            if device.isFocusModeSupported(.autoFocus) {
                device.focusMode = .autoFocus
            } else if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = devicePoint
            }
            if device.isExposureModeSupported(.autoExpose) {
                device.exposureMode = .autoExpose
            } else if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            if device.isAutoFocusRangeRestrictionSupported {
                device.autoFocusRangeRestriction = .near
            }
            device.unlockForConfiguration()
        } catch {
            // ロックできなくても致命傷ではないので無視
        }
    }

    private func showFocusRing(at point: CGPoint) {
        // 黄色いリング: タップした場所が一瞬光る
        let size: CGFloat = 70
        let ring = UIView(frame: CGRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size))
        ring.layer.borderColor = UIColor.systemYellow.cgColor
        ring.layer.borderWidth = 1.5
        ring.layer.cornerRadius = size / 2
        ring.alpha = 0.0
        view.addSubview(ring)
        UIView.animate(withDuration: 0.18, animations: {
            ring.alpha = 1.0
            ring.transform = CGAffineTransform(scaleX: 0.85, y: 0.85)
        }) { _ in
            UIView.animate(withDuration: 0.5, delay: 0.3, options: [], animations: {
                ring.alpha = 0.0
            }) { _ in
                ring.removeFromSuperview()
            }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopSession()
    }

    func update(fields: [MeasurementAverageField]) {
        self.fields = fields
        frameDelegate.update(fields: fields)
    }

    func restartIfNeeded(id: UUID) {
        guard currentID != id else { return }
        currentID = id
        frameDelegate.resetRecognition()
        startSession()
    }

    private func configureIfNeeded() {
        guard !isConfigured else { return }
        isConfigured = true

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if granted {
                        self.configureSession()
                    } else {
                        self.onError(String(localized: "record.camera.permissionDenied"))
                    }
                }
            }
        default:
            onError(String(localized: "record.camera.permissionDenied"))
        }
    }

    private func configureSession() {
        let session = sessionBox.session
        session.beginConfiguration()
        session.sessionPreset = .high

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            onError(String(localized: "record.camera.unavailable"))
            return
        }
        session.addInput(input)
        captureDevice = device
        // 起動時に接写優先＋画面中央にピントを合わせる
        applyFocusAndExposure(device: device, at: CGPoint(x: 0.5, y: 0.5))

        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(frameDelegate, queue: queue)
        if session.canAddOutput(output) {
            session.addOutput(output)
        }
        if let connection = output.connection(with: .video) {
            if #available(iOS 17.0, *) {
                if connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90
                }
            }
        }
        session.commitConfiguration()

        frameDelegate.setSessionBox(sessionBox)
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.insertSublayer(layer, at: 0)
        previewLayer = layer
        isSessionReady = true
        startSession()
    }

    private func startSession() {
        guard isSessionReady else { return }
        // セッション開始は専用キューで行い、UIスレッドの停止を避ける
        sessionBox.start()
    }

    private func stopSession() {
        // シートを閉じる時は専用キューでセッションを停止する
        sessionBox.stop()
    }
}

/// 撮影モード用 FrameDelegate。フレーム継続認識はせず、シャッター要求があった次フレームだけを
/// UIImage 化 + OCR して onCapture でメインに返す
private final class CameraLiveScannerFrameDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var sessionBox: CameraCaptureSessionBox?
    private var fields: [MeasurementAverageField]
    private let onCapture: @MainActor @Sendable (UIImage, [MeasurementAverageField: Int]) -> Void
    private var captureRequested = false
    private var isProcessing = false

    init(
        fields: [MeasurementAverageField],
        onCapture: @escaping @MainActor @Sendable (UIImage, [MeasurementAverageField: Int]) -> Void
    ) {
        self.fields = fields
        self.onCapture = onCapture
        super.init()
    }

    func setSessionBox(_ sessionBox: CameraCaptureSessionBox) {
        lock.lock()
        self.sessionBox = sessionBox
        lock.unlock()
    }

    func update(fields: [MeasurementAverageField]) {
        lock.lock()
        self.fields = fields
        lock.unlock()
    }

    func resetRecognition() {
        lock.lock()
        captureRequested = false
        isProcessing = false
        lock.unlock()
    }

    func requestCapture() {
        lock.lock()
        captureRequested = true
        lock.unlock()
    }

    private func shouldProcessThisFrame() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard captureRequested, !isProcessing else { return false }
        captureRequested = false
        isProcessing = true
        return true
    }

    private func finishProcessing() {
        lock.lock()
        isProcessing = false
        lock.unlock()
    }

    private func currentFields() -> [MeasurementAverageField] {
        lock.lock()
        defer { lock.unlock() }
        return fields
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard shouldProcessThisFrame() else { return }
        let targetFields = currentFields()

        // フレームを UIImage 化（プレビューにユーザが確認するため）
        guard let image = Self.makeUIImage(from: sampleBuffer) else {
            finishProcessing()
            return
        }

        // OCR を1回だけ実行（best-effort、失敗しても画像は返す）
        let values = Self.runOCR(sampleBuffer: sampleBuffer, fields: targetFields)

        let onCapture = self.onCapture
        Task { @MainActor in
            onCapture(image, values)
        }
        finishProcessing()
    }

    /// CMSampleBuffer → UIImage。iOS 17+ では connection.videoRotationAngle=90 によって
    /// ピクセルバッファが既に縦向きに回転されているので、追加の orientation 補正は不要（.up）
    private static func makeUIImage(from sampleBuffer: CMSampleBuffer) -> UIImage? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    /// OCR を1回だけ実行：Core ML → Vision → 7seg の優先順
    private static func runOCR(sampleBuffer: CMSampleBuffer, fields: [MeasurementAverageField]) -> [MeasurementAverageField: Int] {
        // Core ML（モデルがある場合）
        if CoreMLDigitsRecognizer.isAvailable {
            let v = CoreMLDigitsRecognizer.parse(sampleBuffer: sampleBuffer, fields: fields)
            if !v.isEmpty { return v }
        }
        // Vision OCR
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.minimumTextHeight = 0.02
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-US"]
        let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .up, options: [:])
        try? handler.perform([request])
        let recognized: [CameraRecognizedText] = request.results?
            .flatMap { observation -> [CameraRecognizedText] in
                observation.topCandidates(4).map { candidate in
                    CameraRecognizedText(
                        text: candidate.string,
                        confidence: candidate.confidence,
                        boundingBox: observation.boundingBox
                    )
                }
            } ?? []
        let vision = CameraValueParser.parse(recognized: recognized, fields: fields)
        if !vision.isEmpty { return vision }
        // ヒューリスティック 7seg
        return SevenSegmentValueRecognizer.parse(sampleBuffer: sampleBuffer, fields: fields)
    }
}

private enum CameraTextRecognizer {
    static func recognize(_ image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else {
            throw CameraRecordError.imageUnavailable
        }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest { request, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    let texts = (request.results as? [VNRecognizedTextObservation])?
                        .compactMap { $0.topCandidates(1).first?.string } ?? []
                    continuation.resume(returning: texts.joined(separator: "\n"))
                }
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = false
                request.recognitionLanguages = ["en-US"]

                do {
                    let handler = VNImageRequestHandler(
                        cgImage: cgImage,
                        orientation: CGImagePropertyOrientation(image.imageOrientation),
                        options: [:]
                    )
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

private enum CameraValueParser {
    static func parse(recognized: [CameraRecognizedText], fields: [MeasurementAverageField]) -> [MeasurementAverageField: Int] {
        let tokens = recognized.flatMap {
            numberTokens(in: $0.text, confidence: $0.confidence, boundingBox: $0.boundingBox)
        }
        return parse(tokens: tokens, fields: fields)
    }

    static func parse(text: String, fields: [MeasurementAverageField]) -> [MeasurementAverageField: Int] {
        let tokens = numberTokens(in: text, confidence: 1, boundingBox: nil)
        return parse(tokens: tokens, fields: fields)
    }

    private static func parse(tokens: [CameraNumberToken], fields: [MeasurementAverageField])
        -> [MeasurementAverageField: Int] {
        var values: [MeasurementAverageField: Int] = [:]
        var usedIndexes: Set<Int> = []

        let needsBloodPressurePair = fields.contains(.bpHi) && fields.contains(.bpLo)
        let bloodPressurePair = firstBloodPressurePair(tokens)

        if needsBloodPressurePair, let pair = bloodPressurePair {
            values[.bpHi] = pair.systolic
            values[.bpLo] = pair.diastolic
            usedIndexes.insert(pair.systolicIndex)
            usedIndexes.insert(pair.diastolicIndex)
        }

        for field in fields where values[field] == nil {
            // 血圧は上・下のペアが成立する時だけ採用し、断片数字を単独で割り当てない
            if field == .bpHi || field == .bpLo {
                continue
            }
            guard let match = firstValue(for: field, tokens: tokens, excluding: usedIndexes) else { continue }
            values[field] = match.value
            usedIndexes.insert(match.index)
        }

        if needsBloodPressurePair, bloodPressurePair == nil, values.values.allSatisfy({ $0 < 300 }) {
            let hasDecimalMeasurement = values.keys.contains { 0 < $0.decimals }
            if !hasDecimalMeasurement {
                // 血圧計でペアが取れない時は、心拍らしき断片だけで完了しない
                return [:]
            }
        }

        return values
    }

    private static func numberTokens(
        in text: String,
        confidence: Float,
        boundingBox: CGRect?
    ) -> [CameraNumberToken] {
        // 7セグ液晶は Vision OCR の confidence が低めに出るため閾値を緩める
        // 誤検出は血圧ペア整合性 + 連続フレーム同一で抑える
        guard 0.40 <= confidence else { return [] }
        let pattern = #"(?<![\dA-Za-z])\d{2,3}(?:[\.,]\d{1,2})?(?![\dA-Za-z])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsText = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)).compactMap { match in
            let raw = nsText.substring(with: match.range)
            let normalized = raw.replacingOccurrences(of: ",", with: ".")
            guard let number = Double(normalized) else { return nil }
            return CameraNumberToken(
                raw: raw,
                number: number,
                hasDecimal: raw.contains(".") || raw.contains(","),
                confidence: confidence,
                boundingBox: boundingBox
            )
        }
    }

    private static func firstBloodPressurePair(_ tokens: [CameraNumberToken])
        -> (systolicIndex: Int, diastolicIndex: Int, systolic: Int, diastolic: Int)? {
        let integerTokens = tokens.indices.compactMap { index -> (index: Int, token: CameraNumberToken, value: Int)? in
            let token = tokens[index]
            guard !token.hasDecimal else { return nil }
            guard isLikelyDisplayNumber(token) else { return nil }
            return (index, token, Int(token.number.rounded()))
        }

        var best: (systolicIndex: Int, diastolicIndex: Int, systolic: Int, diastolic: Int, score: CGFloat)?
        for systolicCandidate in integerTokens {
            guard 80 <= systolicCandidate.value, systolicCandidate.value <= 260 else { continue }
            for diastolicCandidate in integerTokens where systolicCandidate.index != diastolicCandidate.index {
                guard 40 <= diastolicCandidate.value, diastolicCandidate.value <= 140 else { continue }
                guard diastolicCandidate.value < systolicCandidate.value else { continue }
                let pulsePressure = systolicCandidate.value - diastolicCandidate.value
                guard 15 <= pulsePressure, pulsePressure <= 90 else { continue }

                let score = bloodPressurePairScore(
                    systolic: systolicCandidate.token,
                    diastolic: diastolicCandidate.token
                )
                if best == nil || (best?.score ?? 0) < score {
                    best = (
                        systolicCandidate.index,
                        diastolicCandidate.index,
                        systolicCandidate.value,
                        diastolicCandidate.value,
                        score
                    )
                }
            }
        }
        guard let best else { return nil }
        return (best.systolicIndex, best.diastolicIndex, best.systolic, best.diastolic)
    }

    private static func isLikelyDisplayNumber(_ token: CameraNumberToken) -> Bool {
        guard let box = token.boundingBox else { return true }
        // 画面端や小さな記憶番号などは7セグ表示値として扱わない
        // 機種・撮影距離による差を吸収するため閾値を緩めに設定
        if box.height < 0.020 { return false }
        if box.maxY < 0.10 { return false }
        if box.maxX < 0.20 { return false }
        return true
    }

    private static func bloodPressurePairScore(
        systolic: CameraNumberToken,
        diastolic: CameraNumberToken
    ) -> CGFloat {
        guard let sysBox = systolic.boundingBox,
              let diaBox = diastolic.boundingBox else {
            return 1
        }
        let sysMidX = sysBox.midX
        let diaMidX = diaBox.midX
        let xDistance = abs(sysMidX - diaMidX)
        let yDistance = abs(sysBox.midY - diaBox.midY)
        let yOrderBonus: CGFloat = diaBox.midY < sysBox.midY ? 2 : 0
        let sizeScore = sysBox.height + diaBox.height
        // 同じ列に縦並びする大きな数字ほど血圧ペアとして優先する
        return yOrderBonus + sizeScore + yDistance - xDistance
    }

    private static func firstValue(
        for field: MeasurementAverageField,
        tokens: [CameraNumberToken],
        excluding usedIndexes: Set<Int>
    ) -> (index: Int, value: Int)? {
        for index in tokens.indices where !usedIndexes.contains(index) {
            let token = tokens[index]
            guard let value = scaledValue(token, for: field) else { continue }
            return (index, value)
        }
        return nil
    }

    private static func scaledValue(_ token: CameraNumberToken, for field: MeasurementAverageField) -> Int? {
        switch field {
        case .bpHi, .bpLo, .pulse:
            guard !token.hasDecimal else { return nil }
            guard isLikelyDisplayNumber(token) else { return nil }
            let value = Int(token.number.rounded())
            if field == .pulse, value < 35 {
                return nil
            }
            return field.spec.contains(value) ? value : nil
        case .weight:
            guard token.hasDecimal else { return nil }
            let value = Int((token.number * 10).rounded())
            return field.spec.contains(value) ? value : nil
        case .temp:
            guard token.hasDecimal else { return nil }
            let value = Int((token.number * 10).rounded())
            return field.spec.contains(value) ? value : nil
        case .bodyFat, .skMuscle:
            guard token.hasDecimal else { return nil }
            let value = Int((token.number * 10).rounded())
            return field.spec.contains(value) ? value : nil
        }
    }
}

private struct CameraNumberToken {
    let raw: String
    let number: Double
    let hasDecimal: Bool
    let confidence: Float
    let boundingBox: CGRect?
}

private struct CameraRecognizedText {
    let text: String
    let confidence: Float
    let boundingBox: CGRect
}

/// Roboflow Universe で公開されている 7セグ Digits Recognizer モデル（Core ML）を用いた認識器。
/// `.mlmodel` を Bundle に追加すると自動的に有効化される（追加されていなければ空を返す）。
/// クラスラベル: "0"〜"9" + "-"（小数点 / セパレータ）
private enum CoreMLDigitsRecognizer {
    /// Vision ラップ済みモデル（起動時に1回ロード）
    /// VNCoreMLModel は Sendable ではないが、ここでは load 後 read-only に使うため
    /// nonisolated(unsafe) で Sendable チェックを抑止する（実質スレッドセーフ）。
    /// プロジェクト名は Roboflow Digits Recognizer に合わせて "DigitsRecognizer" を期待する。
    nonisolated(unsafe) private static let visionModel: VNCoreMLModel? = {
        let candidates = ["DigitsRecognizer", "DigitsRecognizer1", "DigitsRecognizer 1"]
        for name in candidates {
            if let url = Bundle.main.url(forResource: name, withExtension: "mlmodelc"),
               let mlModel = try? MLModel(contentsOf: url),
               let visionModel = try? VNCoreMLModel(for: mlModel) {
                return visionModel
            }
        }
        return nil
    }()

    static var isAvailable: Bool { visionModel != nil }

    static func parse(sampleBuffer: CMSampleBuffer, fields: [MeasurementAverageField]) -> [MeasurementAverageField: Int] {
        guard let visionModel,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return [:] }

        var observations: [VNRecognizedObjectObservation] = []
        let request = VNCoreMLRequest(model: visionModel) { req, _ in
            observations = (req.results as? [VNRecognizedObjectObservation]) ?? []
        }
        request.imageCropAndScaleOption = .scaleFit

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
        do {
            try handler.perform([request])
        } catch {
            return [:]
        }
        return assembleNumbers(observations: observations, fields: fields)
    }

    /// 検出した digit bbox を Y 座標で行ごとにグループ化し、左→右に並べて数値化、血圧の妥当性を検証
    private static func assembleNumbers(
        observations: [VNRecognizedObjectObservation],
        fields: [MeasurementAverageField]
    ) -> [MeasurementAverageField: Int] {
        // 数字のみ抽出（"-" や低 confidence は除外）
        let digits: [(digit: Int, box: CGRect)] = observations.compactMap { obs in
            guard 0.50 <= obs.confidence,
                  let label = obs.labels.first?.identifier,
                  let digit = Int(label), (0...9).contains(digit) else { return nil }
            return (digit, obs.boundingBox)
        }
        guard 2 <= digits.count else { return [:] }

        // Y 座標で行クラスタリング（Vision は Y 反転：midY 大 = 画面上）
        let sortedByY = digits.sorted { $0.box.midY > $1.box.midY }
        let yThreshold: CGFloat = 0.05   // bbox 高さの相対閾値（行間判定）
        var rows: [[(digit: Int, box: CGRect)]] = []
        for d in sortedByY {
            if let last = rows.last, let lastY = last.first?.box.midY,
               abs(lastY - d.box.midY) < yThreshold {
                rows[rows.count - 1].append(d)
            } else {
                rows.append([d])
            }
        }

        // 各行内で X 昇順 → 桁を連結 → Int 化
        let rowNumbers: [Int] = rows.compactMap { row in
            let ordered = row.sorted { $0.box.minX < $1.box.minX }
            let str = ordered.map { String($0.digit) }.joined()
            return Int(str)
        }
        guard 2 <= rowNumbers.count else { return [:] }

        let systolic = rowNumbers[0]
        let diastolic = rowNumbers[1]
        // SevenSegmentValueRecognizer と同じ妥当性検証
        guard 80 <= systolic, systolic <= 220,
              40 <= diastolic, diastolic <= 130,
              diastolic < systolic else { return [:] }
        let pulsePressure = systolic - diastolic
        guard 15 <= pulsePressure, pulsePressure <= 80 else { return [:] }

        var result: [MeasurementAverageField: Int] = [.bpHi: systolic, .bpLo: diastolic]
        if fields.contains(.pulse), 3 <= rowNumbers.count {
            let pulse = rowNumbers[2]
            if 35 <= pulse, pulse <= 200 {
                result[.pulse] = pulse
            }
        }
        return result
    }
}

private enum SevenSegmentValueRecognizer {
    static func parse(sampleBuffer: CMSampleBuffer, fields: [MeasurementAverageField]) -> [MeasurementAverageField: Int] {
        guard fields.contains(.bpHi), fields.contains(.bpLo),
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return [:]
        }
        for orientation in [CGImagePropertyOrientation.right, .left, .up] {
            guard let image = makeOrientedImage(from: pixelBuffer, orientation: orientation),
                  let gray = GrayImage(image: image) else {
                continue
            }
            let values = parse(gray: gray, fields: fields)
            if !values.isEmpty {
                return values
            }
        }
        return [:]
    }

    private static func parse(gray: GrayImage, fields: [MeasurementAverageField]) -> [MeasurementAverageField: Int] {
        let rows = displayRows(in: gray)
        // 7セグ妥当性チェック：行ジオメトリの整合性を先に検証
        guard 2 <= rows.count, areRowsConsistent(rows) else { return [:] }

        let pairedValues: [(row: CGRect, value: Int)] = rows.compactMap { row in
            guard let value = readRowValue(in: row, gray: gray) else { return nil }
            return (row, value)
        }
        guard 2 <= pairedValues.count else { return [:] }

        let systolic = pairedValues[0].value
        let diastolic = pairedValues[1].value
        guard 80 <= systolic, systolic <= 220,    // 220 まで（260は誤読の温床）
              40 <= diastolic, diastolic <= 130,  // 130 まで
              diastolic < systolic else {
            return [:]
        }
        // 脈圧 (pulse pressure) の生理的妥当性
        let pulsePressure = systolic - diastolic
        guard 15 <= pulsePressure, pulsePressure <= 80 else { return [:] }

        var result: [MeasurementAverageField: Int] = [.bpHi: systolic, .bpLo: diastolic]
        if fields.contains(.pulse), 3 <= pairedValues.count {
            let pulse = pairedValues[2].value
            if 35 <= pulse, pulse <= 200 {
                result[.pulse] = pulse
            }
        }
        return result
    }

    /// 連続する行のジオメトリ（高さ・縦間隔）が血圧計の表示として妥当か検証する。
    /// LCD は高さがほぼ同じ・上下2〜3行が等間隔で並ぶ
    private static func areRowsConsistent(_ rows: [CGRect]) -> Bool {
        guard 2 <= rows.count else { return false }
        let heights = rows.prefix(3).map(\.height)
        // 1行の高さが極端に違うのは表示ではない可能性（ロゴ、ラベル等）
        if let minH = heights.min(), let maxH = heights.max(), minH > 0 {
            if 1.7 < maxH / minH { return false }
        }
        // 3行ある場合、隣接行のY距離がほぼ均等
        if 3 <= rows.count {
            let gap1 = rows[1].midY - rows[0].midY
            let gap2 = rows[2].midY - rows[1].midY
            if gap1 > 0, gap2 > 0 {
                let ratio = max(gap1, gap2) / min(gap1, gap2)
                if 1.8 < ratio { return false }
            }
        }
        return true
    }

    private static func readRowValue(in row: CGRect, gray: GrayImage) -> Int? {
        var candidates: [(value: Int, score: CGFloat)] = []

        let projectionBoxes = digitBoxes(in: row, gray: gray)
        let projectionDigits = projectionBoxes.compactMap { classifyDigitWithScore(in: $0, gray: gray) }
        if !projectionDigits.isEmpty, projectionDigits.count == projectionBoxes.count {
            let text = projectionDigits.map { String($0.digit) }.joined()
            if let value = Int(text) {
                candidates.append((value, projectionDigits.map(\.score).reduce(0, +)))
            }
        }

        for count in 1...3 {
            let boxes = equalDigitBoxes(in: row, count: count)
            let digits = boxes.compactMap { classifyDigitWithScore(in: $0, gray: gray) }
            guard digits.count == count else { continue }
            let text = digits.map { String($0.digit) }.joined()
            if let value = Int(text) {
                candidates.append((value, digits.map(\.score).reduce(0, +)))
            }
        }

        return candidates
            .filter { 10 <= $0.value && $0.value <= 260 }
            .sorted {
                if $0.score == $1.score { return $0.value < $1.value }
                return $1.score < $0.score
            }
            .first?.value
    }

    private static func makeOrientedImage(
        from pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation
    ) -> CGImage? {
        let image = CIImage(cvPixelBuffer: pixelBuffer).oriented(orientation)
        let context = CIContext(options: [.useSoftwareRenderer: false])
        return context.createCGImage(image, from: image.extent)
    }

    private static func displayRows(in gray: GrayImage) -> [CGRect] {
        let roi = CGRect(
            x: CGFloat(gray.width) * 0.24,
            y: CGFloat(gray.height) * 0.10,
            width: CGFloat(gray.width) * 0.70,
            height: CGFloat(gray.height) * 0.78
        ).integral
        let threshold = gray.darkThreshold(in: roi)
        var bands: [ClosedRange<Int>] = []
        var start: Int?
        let yRange = Int(roi.minY)..<Int(roi.maxY)
        let xRange = Int(roi.minX)..<Int(roi.maxX)

        for y in yRange {
            var count = 0
            for x in xRange where gray.isDark(x: x, y: y, threshold: threshold) {
                count += 1
            }
            let active = CGFloat(count) / roi.width
            if 0.010 <= active {
                if start == nil { start = y }
            } else if let bandStart = start {
                if Swift.max(6, Int(gray.height) / 90) <= y - bandStart {
                    bands.append(bandStart...y)
                }
                start = nil
            }
        }
        if let bandStart = start {
            bands.append(bandStart...Int(roi.maxY))
        }

        let merged = mergeBands(bands, maxGap: Swift.max(10, Int(roi.height) / 28))
        return merged
            .map { range in
                CGRect(x: roi.minX, y: CGFloat(range.lowerBound), width: roi.width, height: CGFloat(range.upperBound - range.lowerBound))
            }
            .filter { Swift.max(14, CGFloat(gray.height) * 0.018) <= $0.height }
            .sorted { $0.minY < $1.minY }
    }

    private static func digitBoxes(in row: CGRect, gray: GrayImage) -> [CGRect] {
        let threshold = gray.darkThreshold(in: row)
        var bands: [ClosedRange<Int>] = []
        var start: Int?
        let xRange = Int(row.minX)..<Int(row.maxX)
        let yRange = Int(row.minY)..<Int(row.maxY)

        for x in xRange {
            var count = 0
            for y in yRange where gray.isDark(x: x, y: y, threshold: threshold) {
                count += 1
            }
            let active = CGFloat(count) / row.height
            if 0.025 <= active {
                if start == nil { start = x }
            } else if let bandStart = start {
                if Swift.max(4, Int(row.height) / 12) <= x - bandStart {
                    bands.append(bandStart...x)
                }
                start = nil
            }
        }
        if let bandStart = start {
            bands.append(bandStart...Int(row.maxX))
        }

        let merged = mergeBands(bands, maxGap: Swift.max(10, Int(row.height) / 3))
        let boxes = merged.map { range -> CGRect in
            let rect = CGRect(
                x: CGFloat(range.lowerBound),
                y: row.minY,
                width: CGFloat(range.upperBound - range.lowerBound),
                height: row.height
            )
            return trim(rect: rect, gray: gray, threshold: threshold).insetBy(dx: -2, dy: -2)
        }
        // 横幅が小さい1も拾うが、ノイズは除外する
        return boxes
            .filter { 4 <= $0.width && Swift.max(12, row.height * 0.35) <= $0.height }
            .sorted { $0.minX < $1.minX }
    }

    private static func classifyDigit(in rect: CGRect, gray: GrayImage) -> Int? {
        classifyDigitWithScore(in: rect, gray: gray)?.digit
    }

    private static func classifyDigitWithScore(in rect: CGRect, gray: GrayImage) -> (digit: Int, score: CGFloat)? {
        let threshold = gray.darkThreshold(in: rect)
        let w = rect.width
        let h = rect.height
        guard 4 <= w, 12 <= h else { return nil }

        let zones: [CGRect] = [
            CGRect(x: rect.minX + w * 0.22, y: rect.minY + h * 0.02, width: w * 0.56, height: h * 0.16), // a
            CGRect(x: rect.minX + w * 0.68, y: rect.minY + h * 0.12, width: w * 0.24, height: h * 0.34), // b
            CGRect(x: rect.minX + w * 0.68, y: rect.minY + h * 0.54, width: w * 0.24, height: h * 0.34), // c
            CGRect(x: rect.minX + w * 0.22, y: rect.minY + h * 0.82, width: w * 0.56, height: h * 0.16), // d
            CGRect(x: rect.minX + w * 0.08, y: rect.minY + h * 0.54, width: w * 0.24, height: h * 0.34), // e
            CGRect(x: rect.minX + w * 0.08, y: rect.minY + h * 0.12, width: w * 0.24, height: h * 0.34), // f
            CGRect(x: rect.minX + w * 0.22, y: rect.minY + h * 0.42, width: w * 0.56, height: h * 0.16), // g
        ]
        let active = zones.map { darkRatio(in: $0, gray: gray, threshold: threshold) }
        let bits = active.map { 0.10 <= $0 }

        let patterns: [Int: [Bool]] = [
            0: [true, true, true, true, true, true, false],
            1: [false, true, true, false, false, false, false],
            2: [true, true, false, true, true, false, true],
            3: [true, true, true, true, false, false, true],
            4: [false, true, true, false, false, true, true],
            5: [true, false, true, true, false, true, true],
            6: [true, false, true, true, true, true, true],
            7: [true, true, true, false, false, false, false],
            8: [true, true, true, true, true, true, true],
            9: [true, true, true, true, false, true, true],
        ]
        let scored = patterns.map { digit, pattern in
            let diff = zip(bits, pattern).filter { $0 != $1 }.count
            let confidence = zip(active, pattern).reduce(CGFloat(0)) { total, item in
                total + (item.1 ? item.0 : 1 - item.0)
            }
            return (digit: digit, diff: diff, confidence: confidence)
        }
        let best = scored.sorted {
            if $0.diff == $1.diff { return $1.confidence < $0.confidence }
            return $0.diff < $1.diff
        }.first
        guard let best, best.diff <= 2 else { return nil }
        return (best.digit, best.confidence - CGFloat(best.diff))
    }

    private static func equalDigitBoxes(in row: CGRect, count: Int) -> [CGRect] {
        let trimX = row.width * 0.04
        let area = row.insetBy(dx: trimX, dy: 0)
        let gap = area.width * 0.025
        let width = (area.width - gap * CGFloat(count - 1)) / CGFloat(count)
        return (0..<count).map { index in
            CGRect(
                x: area.minX + CGFloat(index) * (width + gap),
                y: area.minY,
                width: width,
                height: area.height
            )
        }
    }

    private static func mergeBands(_ bands: [ClosedRange<Int>], maxGap: Int) -> [ClosedRange<Int>] {
        var result: [ClosedRange<Int>] = []
        for band in bands {
            guard let last = result.last else {
                result.append(band)
                continue
            }
            if band.lowerBound - last.upperBound <= maxGap {
                result[result.count - 1] = last.lowerBound...band.upperBound
            } else {
                result.append(band)
            }
        }
        return result
    }

    private static func trim(rect: CGRect, gray: GrayImage, threshold: UInt8) -> CGRect {
        var minX = Int(rect.maxX)
        var maxX = Int(rect.minX)
        var minY = Int(rect.maxY)
        var maxY = Int(rect.minY)
        for y in Int(rect.minY)..<Int(rect.maxY) {
            for x in Int(rect.minX)..<Int(rect.maxX) where gray.isDark(x: x, y: y, threshold: threshold) {
                minX = Swift.min(minX, x)
                maxX = Swift.max(maxX, x)
                minY = Swift.min(minY, y)
                maxY = Swift.max(maxY, y)
            }
        }
        guard minX <= maxX, minY <= maxY else { return rect }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    private static func darkRatio(in rect: CGRect, gray: GrayImage, threshold: UInt8) -> CGFloat {
        let xRange = Int(rect.minX)..<Int(rect.maxX)
        let yRange = Int(rect.minY)..<Int(rect.maxY)
        var dark = 0
        var total = 0
        for y in yRange {
            for x in xRange {
                total += 1
                if gray.isDark(x: x, y: y, threshold: threshold) {
                    dark += 1
                }
            }
        }
        guard 0 < total else { return 0 }
        return CGFloat(dark) / CGFloat(total)
    }
}

private struct GrayImage {
    let width: Int
    let height: Int
    let pixels: [UInt8]

    init?(image: CGImage) {
        width = image.width
        height = image.height
        var data = [UInt8](repeating: 0, count: width * height)
        guard let context = CGContext(
            data: &data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        pixels = data
    }

    func luminance(x: Int, y: Int) -> UInt8 {
        guard 0 <= x, x < width, 0 <= y, y < height else { return 255 }
        return pixels[y * width + x]
    }

    func isDark(x: Int, y: Int, threshold: UInt8) -> Bool {
        luminance(x: x, y: y) <= threshold
    }

    func darkThreshold(in rect: CGRect) -> UInt8 {
        var samples: [UInt8] = []
        let xStep = Swift.max(1, Int(rect.width) / 80)
        let yStep = Swift.max(1, Int(rect.height) / 80)
        var y = Int(rect.minY)
        while y < Int(rect.maxY) {
            var x = Int(rect.minX)
            while x < Int(rect.maxX) {
                samples.append(luminance(x: x, y: y))
                x += xStep
            }
            y += yStep
        }
        guard !samples.isEmpty else { return 90 }
        samples.sort()
        let p18 = samples[Int(CGFloat(samples.count - 1) * 0.18)]
        let p55 = samples[Int(CGFloat(samples.count - 1) * 0.55)]
        let threshold = Int(p18) + Swift.max(18, (Int(p55) - Int(p18)) / 2)
        return UInt8(Swift.min(150, Swift.max(55, threshold)))
    }
}

private enum CameraRecordError: LocalizedError {
    case imageUnavailable

    var errorDescription: String? {
        String(localized: "record.camera.imageUnavailable")
    }
}

private extension MeasurementAverageField {
    var cameraID: String {
        switch self {
        case .bpHi: return "bp_systolic"
        case .bpLo: return "bp_diastolic"
        case .pulse: return "pulse"
        case .weight: return "weight"
        case .temp: return "temperature"
        case .bodyFat: return "body_fat"
        case .skMuscle: return "skeletal_muscle"
        }
    }

    var titleKey: String {
        switch self {
        case .bpHi: return "metric.systolic.long"
        case .bpLo: return "metric.diastolic.long"
        case .pulse: return "metric.heartRate"
        case .weight: return "metric.weight"
        case .temp: return "metric.bodyTemp"
        case .bodyFat: return "metric.bodyFat"
        case .skMuscle: return "metric.skeletalMuscle"
        }
    }

    var iconName: String {
        switch self {
        case .bpHi, .bpLo: return "heart.text.square"
        case .pulse: return "waveform.path.ecg"
        case .weight: return "scalemass"
        case .temp: return "thermometer.medium"
        case .bodyFat: return "percent"
        case .skMuscle: return "figure.strengthtraining.traditional"
        }
    }

    var color: Color {
        switch self {
        case .bpHi: return .red
        case .bpLo: return .blue
        case .pulse: return .orange
        case .weight: return .indigo
        case .temp: return .pink
        case .bodyFat: return .purple
        case .skMuscle: return .teal
        }
    }

    var spec: MeasureSpec {
        switch self {
        case .bpHi: return MeasureRange.bpHi
        case .bpLo: return MeasureRange.bpLo
        case .pulse: return MeasureRange.pulse
        case .weight: return MeasureRange.weight
        case .temp: return MeasureRange.temp
        case .bodyFat: return MeasureRange.bodyFat
        case .skMuscle: return MeasureRange.skMuscle
        }
    }

    var decimals: Int { spec.decimals }

    func formatted(_ value: Int) -> String {
        ValueFormatter.format(value, decimals: decimals)
    }
}

private extension MeasureSpec {
    func contains(_ value: Int) -> Bool {
        min <= value && value <= max
    }
}

private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
