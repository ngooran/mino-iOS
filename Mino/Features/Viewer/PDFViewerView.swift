//
//  PDFViewerView.swift
//  Mino
//
//  PDF viewer using native PDFKit with page navigation and thumbnails
//

import SwiftUI
import PDFKit

// MARK: - Main PDF Viewer View

struct PDFViewerView: View {
    @Environment(\.dismiss) private var dismiss

    let documentURL: URL

    @State private var pdfDocument: PDFDocument?
    @State private var currentPage: Int = 1
    @State private var totalPages: Int = 0
    @State private var showingThumbnails = false
    @State private var showingPageIndicator = true
    @State private var isLoading = true
    @State private var error: Error?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if isLoading {
                    ProgressView("Loading PDF...")
                        .foregroundStyle(.white)
                } else if let error = error {
                    errorView(error)
                } else if let document = pdfDocument {
                    pdfContent(document: document)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color.black.opacity(0.9), for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .principal) {
                    Text(documentURL.deletingPathExtension().lastPathComponent)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }

                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        showingThumbnails = true
                    } label: {
                        Image(systemName: "square.grid.2x2")
                    }

                    ShareLink(item: documentURL) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
            .sheet(isPresented: $showingThumbnails) {
                if let document = pdfDocument {
                    ThumbnailGridView(
                        document: document,
                        currentPage: $currentPage,
                        totalPages: totalPages
                    )
                }
            }
        }
        .task {
            await loadDocument()
        }
    }

    // MARK: - Views

    @ViewBuilder
    private func pdfContent(document: PDFDocument) -> some View {
        ZStack(alignment: .bottom) {
            PDFKitView(
                document: document,
                currentPage: $currentPage,
                totalPages: $totalPages
            )
            .ignoresSafeArea(edges: .bottom)
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showingPageIndicator.toggle()
                }
            }

            // Page indicator overlay
            if showingPageIndicator {
                pageIndicator
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
    }

    private var pageIndicator: some View {
        Text("\(currentPage) / \(totalPages)")
            .font(.system(.callout, design: .monospaced))
            .fontWeight(.medium)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.bottom, 20)
    }

    private func errorView(_ error: Error) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.red)

            Text("Failed to load PDF")
                .font(.headline)
                .foregroundStyle(.white)

            Text(error.localizedDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    // MARK: - Loading

    private func loadDocument() async {
        do {
            guard documentURL.startAccessingSecurityScopedResource() || true else {
                throw NSError(domain: "PDFViewer", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Cannot access document"
                ])
            }

            guard let document = PDFDocument(url: documentURL) else {
                throw NSError(domain: "PDFViewer", code: 2, userInfo: [
                    NSLocalizedDescriptionKey: "Failed to load PDF document"
                ])
            }

            await MainActor.run {
                pdfDocument = document
                totalPages = document.pageCount
                isLoading = false
            }
        } catch {
            await MainActor.run {
                self.error = error
                isLoading = false
            }
        }
    }
}

// MARK: - PDFKit View (UIViewRepresentable)

struct PDFKitView: UIViewRepresentable {
    let document: PDFDocument
    @Binding var currentPage: Int
    @Binding var totalPages: Int

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()

        // Configure display
        pdfView.document = document
        pdfView.displayMode = .singlePage
        pdfView.displayDirection = .horizontal
        pdfView.usePageViewController(true)
        pdfView.autoScales = true
        pdfView.pageBreakMargins = .zero
        pdfView.backgroundColor = .black

        // Set initial page count
        DispatchQueue.main.async {
            totalPages = document.pageCount
        }

        // Observe page changes
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged(_:)),
            name: .PDFViewPageChanged,
            object: pdfView
        )

        return pdfView
    }

    func updateUIView(_ pdfView: PDFView, context: Context) {
        // Navigate to page if changed externally (e.g., from thumbnail grid)
        if let targetPage = document.page(at: currentPage - 1),
           pdfView.currentPage != targetPage {
            pdfView.go(to: targetPage)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    static func dismantleUIView(_ pdfView: PDFView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator)
    }

    class Coordinator: NSObject {
        var parent: PDFKitView

        init(_ parent: PDFKitView) {
            self.parent = parent
        }

        @objc func pageChanged(_ notification: Notification) {
            guard let pdfView = notification.object as? PDFView,
                  let currentPage = pdfView.currentPage,
                  let document = pdfView.document else {
                return
            }

            let pageIndex = document.index(for: currentPage)

            DispatchQueue.main.async {
                self.parent.currentPage = pageIndex + 1
            }
        }
    }
}

// MARK: - Thumbnail Grid View

struct ThumbnailGridView: View {
    @Environment(\.dismiss) private var dismiss

    let document: PDFDocument
    @Binding var currentPage: Int
    let totalPages: Int

    private let columns = [
        GridItem(.adaptive(minimum: 100, maximum: 150), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(0..<totalPages, id: \.self) { index in
                            ThumbnailCell(
                                document: document,
                                pageIndex: index,
                                isSelected: currentPage == index + 1
                            )
                            .id(index)
                            .onTapGesture {
                                currentPage = index + 1
                                dismiss()
                            }
                        }
                    }
                    .padding()
                }
                .onAppear {
                    // Scroll to current page
                    proxy.scrollTo(currentPage - 1, anchor: .center)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Pages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Thumbnail Cell

struct ThumbnailCell: View {
    let document: PDFDocument
    let pageIndex: Int
    let isSelected: Bool

    @State private var thumbnail: UIImage?

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.secondarySystemBackground))
                    .aspectRatio(0.75, contentMode: .fit)

                if let thumbnail = thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .padding(4)
                } else {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        isSelected ? Color.accentColor : Color.clear,
                        lineWidth: 3
                    )
            }
            .shadow(color: .black.opacity(0.1), radius: 2, y: 1)

            Text("\(pageIndex + 1)")
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
        }
        .task {
            await loadThumbnail()
        }
    }

    private func loadThumbnail() async {
        guard thumbnail == nil else { return }

        // Get the page on main actor, then render in background
        guard let page = document.page(at: pageIndex) else { return }

        let pageRect = page.bounds(for: .mediaBox)
        let scale: CGFloat = 150 / max(pageRect.width, pageRect.height)
        let thumbnailSize = CGSize(
            width: pageRect.width * scale,
            height: pageRect.height * scale
        )

        let renderer = UIGraphicsImageRenderer(size: thumbnailSize)
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: thumbnailSize))

            context.cgContext.translateBy(x: 0, y: thumbnailSize.height)
            context.cgContext.scaleBy(x: scale, y: -scale)

            page.draw(with: .mediaBox, to: context.cgContext)
        }

        thumbnail = image
    }
}

#Preview {
    PDFViewerView(documentURL: URL(fileURLWithPath: "/test.pdf"))
}
