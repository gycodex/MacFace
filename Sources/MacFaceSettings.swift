import AVFoundation
import Combine
import SwiftUI

enum UnlockMode: String, CaseIterable, Identifiable {
    case automatic, glance, password
    var id: Self { self }

    var title: String {
        switch self {
        case .automatic: "自动刷脸"
        case .glance: "回车刷脸"
        case .password: "仅用密码"
        }
    }

    var detail: String {
        switch self {
        case .automatic: "锁屏亮起后看一眼就解锁。刚锁屏时直视镜头也会解锁。"
        case .glance: "唤醒锁屏，留空按回车并看向镜头。"
        case .password: "暂停人脸解锁，使用 macOS 密码。"
        }
    }

    var icon: String {
        switch self {
        case .automatic: "faceid"
        case .glance: "return"
        case .password: "key"
        }
    }
}

@main
struct MacFaceSettingsApp: App {
    var body: some Scene {
        Window("MacFace", id: "settings") {
            SettingsView()
                .frame(width: 490)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

struct SettingsView: View {
    @AppStorage("ScreenUnlockMode", store: UserDefaults(suiteName: "com.macface.settings"))
    private var storedMode = UnlockMode.glance.rawValue
    @AppStorage("ShowsMenuBarIcon", store: UserDefaults(suiteName: "com.macface.settings"))
    private var showsMenuBarIcon = true
    private var mode: UnlockMode { UnlockMode(rawValue: storedMode) ?? .password }
    @State private var showingPreview = false
    @State private var showingHelp = false
    @State private var showingEnrollment = false
    @State private var enrolled = false
    @State private var confirmingRemoval = false
    @State private var removalInProgress = false
    @State private var removalError = false
    @State private var backendReady = false
    @State private var starting = true
    @State private var quitting = false
    @State private var quitFailed = false
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
                    .resizable()
                    .frame(width: 50, height: 50)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("锁屏解锁").font(.title2.weight(.semibold))
                    Label(backendReady ? "后台就绪" : (enrolled ? "后台未就绪" : "等待录入人脸"),
                          systemImage: "circle.fill")
                        .font(.caption)
                        .foregroundStyle(backendReady ? Color.green : Color.secondary)
                }
                Spacer()
                Toggle("菜单栏图标", isOn: $showsMenuBarIcon)
                    .accessibilityLabel("在菜单栏显示图标")
                    .fixedSize()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .onChange(of: showsMenuBarIcon) {
                        CFPreferencesAppSynchronize("com.macface.settings" as CFString)
                        DistributedNotificationCenter.default().postNotificationName(
                            Notification.Name("com.macface.settings.menu-bar-icon-changed"),
                            object: nil, userInfo: nil, deliverImmediately: true
                        )
                    }
                    .help("隐藏图标后，仍可从「应用程序」打开 MacFace。")
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("解锁方式").font(.headline)
                VStack(spacing: 0) {
                    ForEach(UnlockMode.allCases) { option in
                        Button {
                            storedMode = option.rawValue
                            if option == .automatic {
                                CFPreferencesAppSynchronize("com.macface.settings" as CFString)
                                DistributedNotificationCenter.default().postNotificationName(
                                    Notification.Name("com.macface.settings.request-event-access"),
                                    object: nil, userInfo: nil, deliverImmediately: true
                                )
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: option.icon)
                                    .frame(width: 22)
                                    .foregroundStyle(.secondary)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(option.title).fontWeight(.medium)
                                    Text(option.detail).font(.subheadline).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: mode == option ? "largecircle.fill.circle" : "circle")
                                    .foregroundStyle(mode == option ? Color.accentColor : Color.secondary)
                                    .accessibilityHidden(true)
                            }
                            .padding(.horizontal, 13)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(mode == option ? [.isSelected] : [])
                        if option != .password {
                            Divider().padding(.leading, 46)
                        }
                    }
                }
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("人脸录入").font(.headline)
                HStack(spacing: 9) {
                    Text(enrolled ? "已录入" : "尚未录入")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("预览摄像头") { showingPreview = true }
                    Button(enrolled ? "重新录入" : "录入人脸") { showingEnrollment = true }
                        .disabled(removalInProgress)
                    if enrolled {
                        Button("删除", systemImage: "trash", role: .destructive) { confirmingRemoval = true }
                            .labelStyle(.iconOnly)
                            .help("删除本机人脸录入")
                            .disabled(removalInProgress)
                    }
                }
                .padding(12)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
            }

            HStack {
                Label("按 ⌃⌘Q 锁屏。系统密码始终可用。", systemImage: "lock")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("退出 MacFace") { quitMacFace() }
                    .buttonStyle(.link)
                    .disabled(starting || quitting || removalInProgress)
                    .help("关闭设置并停止人脸识别后台。重新打开 MacFace 可恢复。")
                Button("解锁原理", systemImage: "info.circle") { showingHelp.toggle() }
                    .buttonStyle(.link)
                    .popover(isPresented: $showingHelp, arrowEdge: .bottom) {
                        VStack(alignment: .leading, spacing: 13) {
                            Text("MacFace 如何解锁").font(.headline)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("怎么刷脸").fontWeight(.semibold)
                                Text("自动刷脸：锁屏亮起后看向摄像头，通过验证即解锁。刚锁屏时直视镜头也会解锁。回车刷脸：密码框留空按回车。")
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("自动模式的权限").fontWeight(.semibold)
                                Text("给 MacFace 后台开启辅助功能后，识别通过即可自动提交验证。权限未生效时，密码框留空按回车仍可刷脸。")
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("密码与隐私").fontWeight(.semibold)
                                Text("随时可以直接输入系统密码。MacFace 只在本机保存人脸特征，不保存密码或摄像头画面。")
                            }
                        }
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(16)
                        .frame(width: 310)
                    }
            }
            .font(.footnote)
        }
        .padding(24)
        .onAppear {
            refreshStatus()
        }
        .task {
            starting = true
            await Task.detached { MacFaceService.start() }.value
            starting = false
            refreshStatus()
        }
        .onReceive(timer) { _ in refreshStatus() }
        .sheet(isPresented: $showingPreview) { CameraPreview(enrollment: false) }
        .sheet(isPresented: $showingEnrollment, onDismiss: refreshStatus) { CameraPreview(enrollment: true) }
        .confirmationDialog("删除已录入的人脸？", isPresented: $confirmingRemoval) {
            Button("删除人脸", role: .destructive) { removeEnrollment() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后可继续使用系统密码。重新录入后才能再刷脸。")
        }
        .alert("未能删除人脸", isPresented: $removalError) {
            Button("好", role: .cancel) {}
        }
        .alert("未能停止 MacFace 后台", isPresented: $quitFailed) {
            Button("好", role: .cancel) {}
        }
    }

    private func quitMacFace() {
        quitting = true
        Task {
            if await Task.detached(operation: MacFaceService.stop).value {
                NSApplication.shared.terminate(nil)
            } else {
                quitting = false
                quitFailed = true
                refreshStatus()
            }
        }
    }

    private func removeEnrollment() {
        removalInProgress = true
        Task {
            let removed = await Task.detached { Enrollment.remove() }.value
            removalInProgress = false
            removalError = !removed
            refreshStatus()
        }
    }

    private func refreshStatus() {
        backendReady = FileManager.default.fileExists(atPath: "/tmp/com.macface.agent.\(getuid()).sock")
        enrolled = FileManager.default.isReadableFile(
            atPath: "/Library/Application Support/MacFace/enrollment-\(getuid()).bin"
        )
    }
}

private enum MacFaceService {
    private static var domain: String { "gui/\(getuid())" }
    private static var service: String { "\(domain)/com.macface.agent" }

    static func start() {
        if !launchctl(["kickstart", service]) && !launchctl(["print", service]) {
            _ = launchctl(["bootstrap", domain, "/Library/LaunchAgents/com.macface.agent.plist"])
        }
    }

    static func stop() -> Bool {
        launchctl(["bootout", service]) || !launchctl(["print", service])
    }

    private static func launchctl(_ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}

struct EnrollmentFrame {
    let width: Int
    let height: Int
    let bytes: Data
}

final class PreviewCamera: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "com.macface.settings.preview")
    private var wantsCamera = false
    private var latest: CVPixelBuffer?
    private var latestTime: TimeInterval = 0
    private var consumedTime: TimeInterval = 0
    @Published var message = "正在打开摄像头…"
    @Published var ready = false

    func start(enrollment: Bool) {
        queue.async { self.wantsCamera = true }
        AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in
            guard let self else { return }
            guard allowed else {
                self.show("请在系统设置 → 隐私与安全性 → 摄像头中允许 MacFace。")
                return
            }
            self.queue.async {
                guard self.wantsCamera else { return }
                let devices = AVCaptureDevice.DiscoverySession(
                    deviceTypes: [.external], mediaType: .video, position: .unspecified
                ).devices
                guard let camera = devices.first(where: { !$0.isContinuityCamera }),
                      let input = try? AVCaptureDeviceInput(device: camera),
                      self.session.canAddInput(input) else {
                    self.show("未找到可用的外接摄像头。")
                    return
                }
                self.session.beginConfiguration()
                self.session.addInput(input)
                if self.session.canSetSessionPreset(.medium) {
                    self.session.sessionPreset = .medium
                }
                if enrollment {
                    let output = AVCaptureVideoDataOutput()
                    guard self.session.canAddOutput(output) else {
                        self.session.commitConfiguration()
                        self.show("无法从摄像头采集录入画面。")
                        return
                    }
                    output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                    output.alwaysDiscardsLateVideoFrames = true
                    output.setSampleBufferDelegate(self, queue: self.queue)
                    self.session.addOutput(output)
                }
                self.session.commitConfiguration()
                self.session.startRunning()
                self.show(self.session.isRunning ? camera.localizedName : "摄像头暂时无法使用。")
            }
        }
    }

    func stop() {
        queue.async {
            self.wantsCamera = false
            self.session.stopRunning()
            self.latest = nil
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        if latest == nil {
            DispatchQueue.main.async { self.ready = true }
        }
        latest = CMSampleBufferGetImageBuffer(sampleBuffer)
        latestTime = ProcessInfo.processInfo.systemUptime
    }

    func enrollmentFrame() async -> EnrollmentFrame? {
        await withCheckedContinuation { continuation in
            queue.async {
                guard let buffer = self.latest,
                      self.latestTime > self.consumedTime,
                      ProcessInfo.processInfo.systemUptime - self.latestTime < 0.45,
                      CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess else {
                    continuation.resume(returning: nil)
                    return
                }
                defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
                guard let address = CVPixelBufferGetBaseAddress(buffer) else {
                    continuation.resume(returning: nil)
                    return
                }
                let width = CVPixelBufferGetWidth(buffer)
                let height = CVPixelBufferGetHeight(buffer)
                let stride = CVPixelBufferGetBytesPerRow(buffer)
                self.consumedTime = self.latestTime
                var bytes = Data()
                bytes.reserveCapacity(width * height * 4)
                for row in 0..<height {
                    bytes.append(address.advanced(by: row * stride).assumingMemoryBound(to: UInt8.self),
                                 count: width * 4)
                }
                continuation.resume(returning: EnrollmentFrame(width: width, height: height, bytes: bytes))
            }
        }
    }

    private func show(_ value: String) {
        DispatchQueue.main.async { self.message = value }
    }
}

struct PreviewLayer: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        view.wantsLayer = true
        view.layer = preview
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}
}

private enum EnrollmentAngle: Int, CaseIterable {
    case center, left, right

    var instruction: String {
        switch self {
        case .center: "正对摄像头"
        case .left: "把鼻尖稍微转向画面左侧"
        case .right: "把鼻尖稍微转向画面右侧"
        }
    }

    var symbol: String {
        switch self {
        case .center: "faceid"
        case .left: "arrow.left"
        case .right: "arrow.right"
        }
    }
}

struct CameraPreview: View {
    let enrollment: Bool
    @Environment(\.dismiss) private var dismiss
    @StateObject private var camera = PreviewCamera()
    @State private var capturing = false
    @State private var saving = false
    @State private var result: String?
    @State private var showConfirmation = false
    @State private var samples: [[Float]] = []

    private var angle: EnrollmentAngle? {
        EnrollmentAngle(rawValue: samples.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(enrollment ? "录入人脸" : "摄像头预览").font(.headline)
                Spacer()
                Button(enrollment ? "取消" : "完成") { dismiss() }.disabled(saving)
            }
            PreviewLayer(session: camera.session)
                .frame(width: 420, height: 270)
                .background(.black)
                .overlay {
                    if enrollment {
                        RoundedRectangle(cornerRadius: 58)
                            .strokeBorder(.white.opacity(0.8), lineWidth: 2)
                            .frame(width: 146, height: 182)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
            if enrollment {
                HStack {
                    Label(angle?.instruction ?? "三个角度已录入",
                          systemImage: angle?.symbol ?? "checkmark.circle.fill")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text("\(samples.count)/\(EnrollmentAngle.allCases.count)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("已完成 \(samples.count) 个角度，共 \(EnrollmentAngle.allCases.count) 个")
                }
                ProgressView(value: Double(samples.count), total: Double(EnrollmentAngle.allCases.count))
                    .accessibilityHidden(true)
            }
            Text(result ?? camera.message).font(.subheadline).foregroundStyle(.secondary)
            if enrollment {
                HStack {
                    Spacer()
                    if saving { ProgressView().controlSize(.small) }
                    if angle == nil {
                        Button("重新采集") {
                            samples.removeAll()
                            result = nil
                        }
                        .disabled(saving)
                        Button("保存人脸") { showConfirmation = true }
                            .buttonStyle(.borderedProminent)
                            .disabled(saving)
                    } else if !capturing {
                        Button(samples.isEmpty ? "开始录入" : "继续录入") { capturing = true }
                            .buttonStyle(.borderedProminent)
                            .disabled(!camera.ready)
                    }
                }
            }
        }
        .padding(20)
        .onAppear { camera.start(enrollment: enrollment) }
        .onDisappear { camera.stop() }
        .interactiveDismissDisabled(saving)
        .task(id: capturing) {
            if capturing { await captureAngles() }
        }
        .confirmationDialog("保存人脸用于解锁？", isPresented: $showConfirmation) {
            Button("保存人脸") { save() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("保存后会替换已有录入。需要管理员确认，只保存人脸特征。")
        }
    }

    private func captureAngles() async {
        var previous: [Float]?
        result = "让脸位于取景框内，按提示保持片刻。"
        while !Task.isCancelled, let angle {
            if let frame = await camera.enrollmentFrame() {
                let capture = await Task.detached { Enrollment.extract(frame, angle: angle) }.value
                guard !Task.isCancelled else { return }
                switch capture {
                case .sample(let features):
                    if let reference = samples.first, Enrollment.similarity(features, reference) < 0.55 {
                        previous = nil
                        result = "请由同一个人完成三个角度。"
                    } else if let last = previous, Enrollment.similarity(features, last) >= 0.55 {
                        samples.append(features)
                        previous = nil
                        result = self.angle == nil ? "可以保存人脸。" : "已采集，按提示转到下一个角度。"
                    } else {
                        previous = features
                        result = "保持片刻。"
                    }
                case .adjustPose:
                    previous = nil
                    result = "让画面中只有一张清晰的人脸，然后按提示调整角度。"
                case .failure(let message):
                    result = message
                    capturing = false
                    return
                }
            } else {
                previous = nil
                result = "正在等待摄像头画面…"
            }
            if self.angle != nil {
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        if !Task.isCancelled { capturing = false }
    }

    private func save() {
        saving = true
        result = "正在保存人脸特征…"
        let captured = samples
        Task {
            let message = await Task.detached { Enrollment.save(captured) }.value
            saving = false
            if let message {
                result = message
            } else {
                dismiss()
            }
        }
    }
}

private enum Enrollment {
    static func remove() -> Bool {
        guard let resources = Bundle.main.resourceURL else { return false }
        return (try? authorize(resources: resources, argument: "--remove")) ?? false
    }

    private static func authorize(resources: URL, argument: String) throws -> Bool {
        let action = Process()
        action.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        action.arguments = ["-e", """
        on run argv
            do shell script ("/bin/bash " & quoted form of item 1 of argv & " " & quoted form of item 2 of argv & " " & quoted form of item 3 of argv) with administrator privileges
        end run
        """, resources.appendingPathComponent("save-enrollment.sh").path, argument, String(getuid())]
        action.standardOutput = FileHandle.nullDevice
        action.standardError = FileHandle.nullDevice
        try action.run()
        action.waitUntilExit()
        return action.terminationStatus == 0
    }

    enum Capture {
        case sample([Float])
        case adjustPose
        case failure(String)
    }

    static func similarity(_ first: [Float], _ second: [Float]) -> Float {
        zip(first, second).reduce(0) { $0 + $1.0 * $1.1 }
    }

    private static func normalized(_ values: [Float]) -> [Float]? {
        let squaredLength = similarity(values, values)
        guard squaredLength.isFinite, squaredLength > 1e-12 else { return nil }
        let length = squaredLength.squareRoot()
        return values.map { $0 / length }
    }

    static func extract(_ frame: EnrollmentFrame, angle: EnrollmentAngle) -> Capture {
        guard let resources = Bundle.main.resourceURL else { return .failure("缺少录入组件。") }
        let extractor = Process()
        extractor.executableURL = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/MacFaceEnroll")
        extractor.arguments = [resources.path, String(frame.width), String(frame.height), String(angle.rawValue)]
        let input = Pipe()
        let output = Pipe()
        extractor.standardInput = input
        extractor.standardOutput = output
        extractor.standardError = FileHandle.nullDevice
        do {
            signal(SIGPIPE, SIG_IGN)
            try extractor.run()
            do { try input.fileHandleForWriting.write(contentsOf: frame.bytes) } catch {
                try? input.fileHandleForWriting.close()
                extractor.waitUntilExit()
                return .failure("录入组件未能接收摄像头画面。")
            }
            try input.fileHandleForWriting.close()
            let template = output.fileHandleForReading.readDataToEndOfFile()
            extractor.waitUntilExit()
            if extractor.terminationStatus == 3 { return .adjustPose }
            guard extractor.terminationStatus == 0, template.count == 512 else {
                return .failure("无法生成有效的人脸特征。")
            }
            let values = template.withUnsafeBytes { bytes in
                (0..<128).map { bytes.loadUnaligned(fromByteOffset: $0 * MemoryLayout<Float>.size, as: Float.self) }
            }
            guard let features = normalized(values) else { return .failure("无法生成有效的人脸特征。") }
            return .sample(features)
        } catch {
            return .failure("无法采集人脸，请重试。")
        }
    }

    static func save(_ samples: [[Float]]) -> String? {
        guard let resources = Bundle.main.resourceURL,
              samples.count == EnrollmentAngle.allCases.count else { return "请先完成三个角度的录入。" }
        let sum = (0..<128).map { index in samples.reduce(Float.zero) { $0 + $1[index] } }
        guard let features = normalized(sum) else { return "无法生成有效的人脸特征。" }
        let template = features.withUnsafeBytes { Data($0) }
        do {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MacFace-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                    attributes: [.posixPermissions: 0o700])
            defer { try? FileManager.default.removeItem(at: directory) }
            let pending = directory.appendingPathComponent("enrollment.bin")
            guard FileManager.default.createFile(atPath: pending.path, contents: template,
                                                 attributes: [.posixPermissions: 0o600]) else {
                return "无法暂存人脸特征。"
            }

            return try authorize(resources: resources, argument: pending.path)
                ? nil : "录入未保存。请确认已批准管理员提示。"
        } catch {
            return "无法完成录入，请重试。"
        }
    }
}
