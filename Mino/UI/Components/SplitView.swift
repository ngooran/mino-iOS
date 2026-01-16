//
//  SplitView.swift
//  Mino
//
//  View for splitting a PDF into ranges or at a specific page
//

import SwiftUI

struct SplitView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let document: PDFDocumentInfo

    @State private var splitMode: SplitModeSelection = .range
    @State private var rangeStart: Int = 1
    @State private var rangeEnd: Int = 1
    @State private var splitAtPage: Int = 2
    @State private var isSplitting = false
    @State private var splitResults: [SplitResult] = []
    @State private var showingResults = false
    @State private var errorMessage: String?

    // Text field values for manual entry
    @State private var rangeStartText: String = "1"
    @State private var rangeEndText: String = "1"
    @State private var splitAtPageText: String = "2"

    enum SplitModeSelection: String, CaseIterable {
        case range = "Extract Range"
        case splitAt = "Split at Page"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 20) {
                        // Document info header
                        documentHeader

                        // Mode picker
                        modePicker

                        // Mode-specific content
                        if splitMode == .range {
                            rangeSelector
                        } else {
                            splitAtPageSelector
                        }
                    }
                    .padding()
                }

                bottomBar
            }
            .background(Color.minoBackground)
            .navigationTitle("Split PDF")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .minoToolbarStyle()
            .onAppear {
                rangeEnd = document.pageCount
                rangeEndText = "\(document.pageCount)"
                // Default split at page 2 (splits into first page and rest)
                splitAtPage = min(2, document.pageCount)
                splitAtPageText = "\(splitAtPage)"
            }
            .sheet(isPresented: $showingResults) {
                SplitResultsView(results: splitResults, mode: splitMode) {
                    showingResults = false
                    dismiss()
                }
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") {
                    errorMessage = nil
                }
            } message: {
                if let error = errorMessage {
                    Text(error)
                }
            }
            .overlay {
                if isSplitting {
                    SplitOverlay(job: appState.splitService.currentJob)
                }
            }
        }
    }

    // MARK: - Document Header

    private var documentHeader: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.minoAccent.opacity(0.15))
                    .frame(width: 56, height: 56)

                Image(systemName: "doc.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Color.minoAccent)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(document.name)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text("\(document.pageCount) pages • \(document.formattedSize)")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.5))
            }

            Spacer()
        }
        .padding()
        .minoGlass(in: 14)
    }

    // MARK: - Mode Picker

    private var modePicker: some View {
        Picker("Split Mode", selection: $splitMode) {
            ForEach(SplitModeSelection.allCases, id: \.self) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Range Selector

    private var rangeSelector: some View {
        VStack(spacing: 16) {
            // Range inputs with both stepper and text field
            HStack(spacing: 20) {
                // From Page
                VStack(alignment: .leading, spacing: 8) {
                    Text("From Page")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))

                    HStack(spacing: 8) {
                        TextField("", text: $rangeStartText)
                            .keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                            .multilineTextAlignment(.center)
                            .onChange(of: rangeStartText) { _, newValue in
                                if let value = Int(newValue), value >= 1, value <= document.pageCount {
                                    rangeStart = value
                                    if rangeStart > rangeEnd {
                                        rangeEnd = rangeStart
                                        rangeEndText = "\(rangeEnd)"
                                    }
                                }
                            }

                        Stepper("", value: $rangeStart, in: 1...document.pageCount)
                            .labelsHidden()
                            .onChange(of: rangeStart) { _, newValue in
                                rangeStartText = "\(newValue)"
                                if newValue > rangeEnd {
                                    rangeEnd = newValue
                                    rangeEndText = "\(rangeEnd)"
                                }
                            }
                    }
                }
                .frame(maxWidth: .infinity)

                // To Page
                VStack(alignment: .leading, spacing: 8) {
                    Text("To Page")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))

                    HStack(spacing: 8) {
                        TextField("", text: $rangeEndText)
                            .keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                            .multilineTextAlignment(.center)
                            .onChange(of: rangeEndText) { _, newValue in
                                if let value = Int(newValue), value >= rangeStart, value <= document.pageCount {
                                    rangeEnd = value
                                }
                            }

                        Stepper("", value: $rangeEnd, in: rangeStart...document.pageCount)
                            .labelsHidden()
                            .onChange(of: rangeEnd) { _, newValue in
                                rangeEndText = "\(newValue)"
                            }
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding()
            .minoGlass(in: 14)

            // Preview
            VStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .font(.system(size: 32))
                    .foregroundStyle(Color.minoAccent.opacity(0.5))

                Text("Will extract \(selectedPageCount) page\(selectedPageCount == 1 ? "" : "s")")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))

                Text("Pages \(rangeStart) to \(rangeEnd)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.4))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .minoGlass(in: 14)
        }
    }

    // MARK: - Split At Page Selector

    private var splitAtPageSelector: some View {
        VStack(spacing: 16) {
            // Split page input
            VStack(alignment: .leading, spacing: 12) {
                Text("Split After Page")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))

                HStack(spacing: 12) {
                    TextField("", text: $splitAtPageText)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .multilineTextAlignment(.center)
                        .onChange(of: splitAtPageText) { _, newValue in
                            if let value = Int(newValue), value >= 2, value <= document.pageCount {
                                splitAtPage = value
                            }
                        }

                    Stepper("", value: $splitAtPage, in: 2...document.pageCount)
                        .labelsHidden()
                        .onChange(of: splitAtPage) { _, newValue in
                            splitAtPageText = "\(newValue)"
                        }

                    Spacer()

                    Text("of \(document.pageCount)")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .padding()
            .minoGlass(in: 14)

            // Preview - show the two resulting files
            VStack(spacing: 16) {
                Text("Will create 2 files:")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))

                HStack(spacing: 16) {
                    // Part 1
                    VStack(spacing: 8) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.minoAccent.opacity(0.15))
                                .frame(width: 60, height: 70)

                            Image(systemName: "doc.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(Color.minoAccent)
                        }

                        Text("Part 1")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white)

                        Text(part1Description)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.5))
                    }

                    Image(systemName: "scissors")
                        .font(.title2)
                        .foregroundStyle(.white.opacity(0.3))

                    // Part 2
                    VStack(spacing: 8) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.orange.opacity(0.15))
                                .frame(width: 60, height: 70)

                            Image(systemName: "doc.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(Color.orange)
                        }

                        Text("Part 2")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white)

                        Text(part2Description)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .minoGlass(in: 14)

            // Info
            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .foregroundStyle(Color.minoAccent)

                Text("The PDF will be split after page \(splitAtPage - 1). Part 1 contains pages 1-\(splitAtPage - 1), Part 2 contains pages \(splitAtPage)-\(document.pageCount).")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .minoGlass(in: 10)
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 12) {
            Button {
                Task {
                    await performSplit()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "scissors")
                    Text(splitMode == .range ? "Extract Pages" : "Split PDF")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .foregroundStyle(.white)
                .minoGlassAccentButton()
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isSplitting || !isValidInput)
            .padding(.horizontal)
        }
        .padding(.vertical)
        .background(Color.minoCardBackground)
    }

    // MARK: - Computed Properties

    private var selectedPageCount: Int {
        rangeEnd - rangeStart + 1
    }

    private var part1PageCount: Int {
        splitAtPage - 1
    }

    private var part2PageCount: Int {
        document.pageCount - part1PageCount
    }

    private var part1Description: String {
        if part1PageCount == 1 {
            return "Page 1"
        }
        return "Pages 1-\(part1PageCount)"
    }

    private var part2Description: String {
        if part2PageCount == 1 {
            return "Page \(splitAtPage)"
        }
        return "Pages \(splitAtPage)-\(document.pageCount)"
    }

    private var isValidInput: Bool {
        if splitMode == .range {
            return rangeStart >= 1 && rangeEnd <= document.pageCount && rangeStart <= rangeEnd
        } else {
            return splitAtPage >= 2 && splitAtPage <= document.pageCount
        }
    }

    // MARK: - Actions

    private func performSplit() async {
        isSplitting = true
        HapticManager.shared.compressionStart()

        do {
            if splitMode == .range {
                let range = PageRange(start: rangeStart, end: rangeEnd)
                let result = try await appState.splitService.extractRange(
                    from: document,
                    range: range
                )
                splitResults = [result]
            } else {
                let results = try await appState.splitService.splitAtPage(
                    document: document,
                    splitPage: splitAtPage
                )
                splitResults = results
            }

            isSplitting = false
            HapticManager.shared.compressionComplete()
            showingResults = true
        } catch {
            isSplitting = false
            HapticManager.shared.error()
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Split Overlay

struct SplitOverlay: View {
    let job: SplitJob?

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: Color.minoAccent))
                    .scaleEffect(1.5)

                Text(job?.state.statusMessage ?? "Splitting...")
                    .font(.headline)
                    .foregroundStyle(.white)

                if let progress = job?.state.progress, progress > 0 {
                    ProgressView(value: progress)
                        .tint(Color.minoAccent)
                        .frame(width: 200)
                }
            }
            .padding(32)
            .minoGlass(in: 20)
        }
    }
}

// MARK: - Split Results View

struct SplitResultsView: View {
    let results: [SplitResult]
    let mode: SplitView.SplitModeSelection
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Success header
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.minoSuccess.opacity(0.15))
                            .frame(width: 64, height: 64)

                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(Color.minoSuccess)
                    }

                    Text("Split Complete!")
                        .font(.title2.bold())
                        .foregroundStyle(.white)

                    Text(mode == .range
                         ? "Extracted \(results.first?.pageCount ?? 0) pages"
                         : "Created \(results.count) PDF files")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                }
                .padding(.top)

                // Results list
                List(results) { result in
                    SplitResultRow(result: result)
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .background(Color.minoBackground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        // Record good split and potentially request review
                        HistoryManager.shared.recordGoodSplit()
                        HistoryManager.shared.requestReviewIfAppropriate()
                        onDone()
                    }
                }
            }
            .minoToolbarStyle()
        }
    }
}

// MARK: - Split Result Row

struct SplitResultRow: View {
    let result: SplitResult

    @State private var showingExportPicker = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.minoSuccess.opacity(0.15))
                    .frame(width: 40, height: 40)

                Image(systemName: "doc.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.minoSuccess)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(result.fileName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(result.summary)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }

            Spacer()

            Menu {
                ShareLink(item: result.outputURL) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }

                Button {
                    showingExportPicker = true
                } label: {
                    Label("Save to Files", systemImage: "folder")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .listRowBackground(Color.minoCardBackground)
        .sheet(isPresented: $showingExportPicker) {
            DocumentExporter(url: result.outputURL) { _ in
                showingExportPicker = false
            }
        }
    }
}

#Preview {
    SplitView(document: PDFDocumentInfo(
        url: URL(fileURLWithPath: "/test.pdf"),
        pageCount: 10
    ))
    .environment(AppState())
    .preferredColorScheme(.dark)
}
