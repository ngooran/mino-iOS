//
//  ShareViewController.swift
//  MinoShare
//
//  Share Extension for receiving PDFs from other apps
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
        imageView.image = UIImage(systemName: "doc.zipper")
        imageView.tintColor = .systemBlue
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "Compress with Mino"
        label.font = .boldSystemFont(ofSize: 20)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let messageLabel: UILabel = {
        let label = UILabel()
        label.text = "Preparing PDF..."
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
        button.setTitle("Cancel", for: .normal)
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

    private func processSharedItems() {
        guard let extensionContext = extensionContext,
              let inputItems = extensionContext.inputItems as? [NSExtensionItem] else {
            showError("No items to share")
            return
        }

        for item in inputItems {
            guard let attachments = item.attachments else { continue }

            for attachment in attachments {
                if attachment.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
                    loadPDF(from: attachment)
                    return
                }
            }
        }

        showError("No PDF found in shared items")
    }

    private func loadPDF(from attachment: NSItemProvider) {
        attachment.loadFileRepresentation(forTypeIdentifier: UTType.pdf.identifier) { [weak self] url, error in
            guard let self = self else { return }

            if let error = error {
                DispatchQueue.main.async {
                    self.showError("Failed to load PDF: \(error.localizedDescription)")
                }
                return
            }

            guard let sourceURL = url else {
                DispatchQueue.main.async {
                    self.showError("Could not access PDF file")
                }
                return
            }

            // IMPORTANT: Copy the file immediately while still in the callback
            // The temporary file is deleted after this callback returns
            self.copyToSharedContainer(from: sourceURL)
        }
    }

    private func copyToSharedContainer(from sourceURL: URL) {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            DispatchQueue.main.async {
                self.showError("Could not access shared container")
            }
            return
        }

        let sharedPDFsURL = containerURL.appendingPathComponent(sharedPDFDirectory, isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: sharedPDFsURL, withIntermediateDirectories: true)
        } catch {
            DispatchQueue.main.async {
                self.showError("Could not create shared directory")
            }
            return
        }

        // Generate unique filename
        let originalName = sourceURL.deletingPathExtension().lastPathComponent
        let uniqueID = UUID().uuidString.prefix(8)
        let filename = "\(originalName)_\(uniqueID).pdf"
        let destinationURL = sharedPDFsURL.appendingPathComponent(filename)

        do {
            // Remove if exists
            try? FileManager.default.removeItem(at: destinationURL)
            // Copy immediately while the temp file still exists
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)

            // Save the URL to shared UserDefaults
            if let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier) {
                sharedDefaults.set(destinationURL.absoluteString, forKey: sharedPDFKey)
                sharedDefaults.synchronize()
            }

            // Now dispatch to main for UI updates and opening the app
            DispatchQueue.main.async {
                self.messageLabel.text = "Opening Mino..."
                self.openMainApp(with: destinationURL)
            }

        } catch {
            DispatchQueue.main.async {
                self.showError("Failed to copy PDF: \(error.localizedDescription)")
            }
        }
    }

    private func openMainApp(with fileURL: URL) {
        // URL encode the file path
        guard let encodedPath = fileURL.absoluteString.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed
        ) else {
            showError("Failed to encode file path")
            return
        }

        let urlString = "\(urlScheme)://import?file=\(encodedPath)"
        guard let url = URL(string: urlString) else {
            showError("Failed to create app URL")
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
                            self?.showError("Could not open Mino app")
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
        messageLabel.text = "PDF ready! Open Mino to compress."
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
