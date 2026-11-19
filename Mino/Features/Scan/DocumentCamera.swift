//
//  DocumentCamera.swift
//  Mino
//
//  The system document camera (VisionKit): live edge detection, automatic
//  capture and perspective correction. It does not run in the simulator.
//

import SwiftUI
import VisionKit

struct DocumentCamera: UIViewControllerRepresentable {
    /// Called with the captured pages, or an empty array when cancelled.
    let onFinish: ([UIImage]) -> Void

    /// False in the simulator and on devices without a suitable camera.
    static var isSupported: Bool {
        #if DEBUG
        if StandInCamera.isEnabled { return true }
        #endif
        return VNDocumentCameraViewController.isSupported
    }

    /// The Scan screen opens the camera as soon as it appears, except with
    /// demo data (screenshots), where there is no camera.
    static var opensByItself: Bool {
        #if DEBUG
        if StandInCamera.isEnabled { return true }
        #endif
        return !StorageRoot.isDemo
    }

    func makeUIViewController(context: Context) -> UIViewController {
        #if DEBUG
        if StandInCamera.isEnabled { return StandInCamera(onFinish: onFinish) }
        #endif
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onFinish: ([UIImage]) -> Void

        init(onFinish: @escaping ([UIImage]) -> Void) {
            self.onFinish = onFinish
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            onFinish((0..<scan.pageCount).map { scan.imageOfPage(at: $0) })
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onFinish([])
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            onFinish([])
        }
    }
}

#if DEBUG
/// A stand-in for the document camera in the simulator (`-demoCamera`), so
/// presenting, folding and dismissing the camera can be tested without one.
/// It shows how many cameras have been created: a new number after folding
/// means the camera was closed and opened again.
final class StandInCamera: UIViewController {
    static var isEnabled: Bool { ProcessInfo.processInfo.arguments.contains("-demoCamera") }
    private static var created = 0

    private let onFinish: ([UIImage]) -> Void
    private let number: Int
    private let label = UILabel()

    init(onFinish: @escaping ([UIImage]) -> Void) {
        self.onFinish = onFinish
        StandInCamera.created += 1
        number = StandInCamera.created
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        label.textColor = .white
        label.numberOfLines = 0
        label.textAlignment = .center
        label.font = .monospacedSystemFont(ofSize: 22, weight: .semibold)
        let save = UIButton(configuration: .filled(), primaryAction: UIAction(title: "Save 2 Pages") { [weak self] _ in
            self?.onFinish(DebugLaunch.makeSampleScanPages(count: 2).compactMap { UIImage(contentsOfFile: $0.path) })
        })
        let cancel = UIButton(configuration: .gray(), primaryAction: UIAction(title: "Cancel") { [weak self] _ in
            self?.onFinish([])
        })
        let stack = UIStackView(arrangedSubviews: [label, save, cancel])
        stack.axis = .vertical
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // `-demoCameraSave <seconds>`: press Save by itself, for scripted runs.
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-demoCameraSave"), index + 1 < arguments.count,
           let seconds = Double(arguments[index + 1]) {
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
                self?.onFinish(DebugLaunch.makeSampleScanPages(count: 2).compactMap { UIImage(contentsOfFile: $0.path) })
            }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        label.text = "STAND-IN CAMERA #\(number)\n\(Int(view.bounds.width)) × \(Int(view.bounds.height))"
    }
}
#endif
