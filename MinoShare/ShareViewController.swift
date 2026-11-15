//
//  ShareViewController.swift
//  MinoShare
//
//  Share Extension: receives PDFs, images and Office documents from other
//  apps, copies them to the App Group container and opens Mino, which
//  shows the right tool.
//

import UIKit
import UniformTypeIdentifiers

class ShareViewController: UIViewController {

    // MARK: - Constants

    private let appGroupIdentifier = "group.com.applestan.Mino"
    private let sharedPDFDirectory = "SharedPDFs"
    private let sharedPDFKey = "sharedPDFURL"
    private let urlScheme = "mino"

    // MARK: - UI Elements

    private let containerView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.systemBackground
        view.layer.cornerRadius = 16
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOffset = CGSize(width: 0, height: 4)
        view.layer.shadowRadius = 12
        view.layer.shadowOpacity = 0.15
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let iconImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(systemName: "doc.on.doc")
        imageView.tintColor = .systemTeal
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = String(localized: "Open in Mino")
        label.font = .boldSystemFont(ofSize: 20)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let messageLabel: UILabel = {
        let label = UILabel()
        label.text = String(localized: "Preparing…")
        label.font = .systemFont(ofSize: 15)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.hidesWhenStopped = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()

    private let cancelButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle(String(localized: "Cancel"), for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 17)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        processSharedItems()
    }

    // MARK: - UI Setup

    private func setupUI() {
        view.backgroundColor = UIColor.black.withAlphaComponent(0.4)

        view.addSubview(containerView)
        containerView.addSubview(iconImageView)
        containerView.addSubview(titleLabel)
        containerView.addSubview(messageLabel)
        containerView.addSubview(activityIndicator)
        containerView.addSubview(cancelButton)

        NSLayoutConstraint.activate([
            containerView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            containerView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            containerView.widthAnchor.constraint(equalToConstant: 300),

            iconImageView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 24),
            iconImageView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 48),
            iconImageView.heightAnchor.constraint(equalToConstant: 48),

            titleLabel.topAnchor.constraint(equalTo: iconImageView.bottomAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -20),

            messageLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            messageLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 20),
            messageLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -20),

            activityIndicator.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 16),
            activityIndicator.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),

            cancelButton.topAnchor.constraint(equalTo: activityIndicator.bottomAnchor, constant: 16),
            cancelButton.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            cancelButton.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -20)
        ])

        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        activityIndicator.startAnimating()
    }

    // MARK: - Actions

    @objc private func cancelTapped() {
        extensionContext?.cancelRequest(withError: NSError(domain: "MinoShare", code: -1))
    }

    // MARK: - Processing

    /// Most files Mino takes in one share.
    private let maxFiles = 30

    /// Uniform type identifiers Mino can use, most specific first.
    private static let acceptedTypes: [UTType] = {
        var types: [UTType] = [.pdf, .image, .rtf, .plainText, .html]
        let office = [
            "org.openxmlformats.wordprocessingml.document",
            "com.microsoft.word.doc",
            "org.openxmlformats.spreadsheetml.sheet",
            "com.microsoft.excel.xls",
            "org.openxmlformats.presentationml.presentation",
            "com.microsoft.powerpoint.ppt",
            "com.apple.iwork.pages.sffpages",
            "com.apple.iwork.numbers.sffnumbers",
            "com.apple.iwork.keynote.sffkey",
            "public.comma-separated-values-text",
        ]
        types.append(contentsOf: office.compactMap { UTType($0) })
        return types
    }()

    private func processSharedItems() {
        guard let extensionContext = extensionContext,
              let inputItems = extensionContext.inputItems as? [NSExtensionItem] else {
            showError(String(localized: "No items to share"))
            return
        }

        // Each attachment with the first type Mino accepts.
        var attachments: [(provider: NSItemProvider, type: String)] = []
        for item in inputItems {
            for provider in item.attachments ?? [] {
                if let type = Self.acceptedTypes.first(where: { provider.hasItemConformingToTypeIdentifier($0.identifier) }) {
                    attachments.append((provider, type.identifier))
                }
            }
        }
        attachments = Array(attachments.prefix(maxFiles))
        guard !attachments.isEmpty else {
            showError(String(localized: "Mino can open PDFs, images and Office documents."))
            return
        }
        guard let sharedFolder = sharedFolder() else {
            showError(String(localized: "Could not access shared container"))
            return
        }

        let group = DispatchGroup()
        let lock = NSLock()
        var copies: [Int: URL] = [:]
        for (index, attachment) in attachments.enumerated() {
            group.enter()
            attachment.provider.loadFileRepresentation(forTypeIdentifier: attachment.type) { [weak self] url, _ in
                defer { group.leave() }
                // The temporary file is deleted when this callback returns, so copy it now.
                guard let self, let url, let copy = self.copyToSharedContainer(from: url, folder: sharedFolder) else { return }
                lock.lock()
                copies[index] = copy
                lock.unlock()
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            let urls = copies.keys.sorted().compactMap { copies[$0] }
            guard !urls.isEmpty else {
                self.showError(String(localized: "The files couldn't be read."))
                return
            }
            // Kept for Mino to pick up at launch if the URL can't open it.
            if let sharedDefaults = UserDefaults(suiteName: self.appGroupIdentifier) {
                sharedDefaults.set(urls.map(\.absoluteString).joined(separator: "\n"), forKey: self.sharedPDFKey)
            }
            self.messageLabel.text = String(localized: "Opening Mino…")
            self.openMainApp(with: urls)
        }
    }

    private func sharedFolder() -> URL? {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else { return nil }
        let folder = containerURL.appendingPathComponent(sharedPDFDirectory, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return folder
        } catch {
            return nil
        }
    }

    /// Copies a shared file into its own folder, so it keeps its name.
    private func copyToSharedContainer(from sourceURL: URL, folder: URL) -> URL? {
        let directory = folder.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let destination = directory.appendingPathComponent(sourceURL.lastPathComponent)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: sourceURL, to: destination)
            return destination
        } catch {
            return nil
        }
    }

    private func openMainApp(with fileURLs: [URL]) {
        // mino://import?file=<url>&file=<url>
        var components = URLComponents()
        components.scheme = urlScheme
        components.host = "import"
        components.queryItems = fileURLs.map { URLQueryItem(name: "file", value: $0.absoluteString) }

        guard let url = components.url else {
            showError(String(localized: "Could not open Mino"))
            return
        }

        // Use responder chain to open URL
        var responder: UIResponder? = self
        while responder != nil {
            if let application = responder as? UIApplication {
                application.open(url, options: [:]) { [weak self] success in
                    DispatchQueue.main.async {
                        if success {
                            self?.extensionContext?.completeRequest(returningItems: nil)
                        } else {
                            self?.showError(String(localized: "Could not open Mino"))
                        }
                    }
                }
                return
            }
            responder = responder?.next
        }

        // Fallback: Use openURL selector
        openURLFallback(url)
    }

    private func openURLFallback(_ url: URL) {
        // Use selector-based approach to open URL from extension
        let selector = sel_registerName("openURL:")
        var responder: UIResponder? = self

        while responder != nil {
            if responder!.responds(to: selector) {
                responder!.perform(selector, with: url)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    self?.extensionContext?.completeRequest(returningItems: nil)
                }
                return
            }
            responder = responder?.next
        }

        // If we can't open the app, still complete successfully
        // The user can open the app manually
        messageLabel.text = String(localized: "Ready. Open Mino to continue.")
        activityIndicator.stopAnimating()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }

    private func showError(_ message: String) {
        activityIndicator.stopAnimating()
        messageLabel.text = message
        messageLabel.textColor = .systemRed
        iconImageView.image = UIImage(systemName: "exclamationmark.circle")
        iconImageView.tintColor = .systemRed

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.extensionContext?.cancelRequest(
                withError: NSError(domain: "MinoShare", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: message
                ])
            )
        }
    }
}
