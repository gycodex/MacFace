import AVFoundation
import Combine
import SwiftUI

enum UnlockMode: String, CaseIterable, Identifiable {
    case glance, password
    var id: Self { self }

    var title: String {
        switch self {
        case .glance: "看一眼"
        case .password: "仅用密码"
        }
    }

    var detail: String {
        switch self {
        case .glance: "唤醒锁屏，留空按回车并看向镜头。"
        case .password: "暂停人脸解锁，使用 macOS 密码。"
        }
    }

    var icon: String {
        switch self {
        case .glance: "faceid"
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
    private var mode: UnlockMode { UnlockMode(rawValue: storedMode) ?? .password }
    @State private var showingPreview = false
    @State private var showingHelp = false
    @State private var showingEnrollment = false
    @State private var enrolled = false
    @State private var confirmingRemoval = false
    @State private var removalInProgress = false
    @State private var removalError = false
    @State private var backendReady = false
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
                Button("解锁原理", systemImage: "questionmark.circle") { showingHelp.toggle() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .font(.title3)
                    .help("了解 MacFace 如何解锁")
                    .popover(isPresented: $showingHelp, arrowEdge: .top) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("MacFace 如何解锁").font(.headline)
                            Text("在「看一眼」模式下，锁屏亮起时，摄像头会短暂预热并提前识别人脸。")
                            Text("留空按回车才会提交解锁。MacFace 会再核对一帧新画面，确认你还在镜头前。")
                            Text("也可以直接输入正确密码。人脸特征仅保存在本机，摄像头画面不会保存。")
                        }
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(16)
                        .frame(width: 305)
                    }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("解锁方式").font(.headline)
                VStack(spacing: 0) {
                    ForEach(UnlockMode.allCases) { option in
                        Button {
                            storedMode = option.rawValue
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
                        if option == .glance {
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

            Label("按 ⌃⌘Q 锁屏。系统密码始终可用。", systemImage: "lock")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .onAppear(perform: refreshStatus)
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
    }

    func enrollmentFrame() async -> EnrollmentFrame? {
        await withCheckedContinuation { continuation in
            queue.async {
                guard let buffer = self.latest,
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

struct CameraPreview: View {
    let enrollment: Bool
    @Environment(\.dismiss) private var dismiss
    @StateObject private var camera = PreviewCamera()
    @State private var saving = false
    @State private var result: String?
    @State private var showConfirmation = false

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
                .clipShape(RoundedRectangle(cornerRadius: 12))
            Text(result ?? camera.message).font(.subheadline).foregroundStyle(.secondary)
            if enrollment {
                HStack {
                    Text("正对镜头并保持光线充足。").font(.footnote).foregroundStyle(.secondary)
                    Spacer()
                    if saving { ProgressView().controlSize(.small) }
                    Button("录入当前人脸") { showConfirmation = true }
                        .buttonStyle(.borderedProminent)
                        .disabled(!camera.ready || saving)
                }
            }
        }
        .padding(20)
        .onAppear { camera.start(enrollment: enrollment) }
        .onDisappear { camera.stop() }
        .interactiveDismissDisabled(saving)
        .confirmationDialog("保存这张人脸用于解锁？", isPresented: $showConfirmation) {
            Button("保存人脸") { save() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("这会替换以前的录入。只保存人脸特征，需要管理员确认。")
        }
    }

    private func save() {
        saving = true
        result = "正在处理人脸…"
        Task {
            guard let frame = await camera.enrollmentFrame() else {
                result = "暂时没有画面，请再试一次。"
                saving = false
                return
            }
            let message = await Task.detached { Enrollment.save(frame) }.value
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

    static func save(_ frame: EnrollmentFrame) -> String? {
        guard let resources = Bundle.main.resourceURL else { return "缺少录入组件。" }
        let extractor = Process()
        extractor.executableURL = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/MacFaceEnroll")
        extractor.arguments = [resources.path, String(frame.width), String(frame.height)]
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
                return "录入组件未能接收摄像头画面。"
            }
            try input.fileHandleForWriting.close()
            let template = output.fileHandleForReading.readDataToEndOfFile()
            extractor.waitUntilExit()
            if extractor.terminationStatus == 3 {
                return "请让画面中只有一张清晰的正脸，然后重试。"
            }
            guard extractor.terminationStatus == 0, template.count == 512 else {
                return "无法生成有效的人脸特征。"
            }

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
