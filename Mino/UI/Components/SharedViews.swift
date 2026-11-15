//
//  SharedViews.swift
//  Mino
//
//  Rows and states reused across screens.
//

import SwiftUI

/// A generated file: thumbnail, name, outcome and date.
struct FileRow: View {
    let item: FileItem

    var body: some View {
        HStack(spacing: 12) {
            FileThumbnail(url: item.url)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(item.summary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(item.date, format: .relative(presentation: .named, unitsStyle: .abbreviated))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// An input PDF: thumbnail, name, pages and size.
struct DocumentRow: View {
    let document: PDFDocumentInfo
    var thumbnailWidth: CGFloat = 36

    var body: some View {
        HStack(spacing: 12) {
            FileThumbnail(url: document.url, width: thumbnailWidth)
            VStack(alignment: .leading, spacing: 2) {
                Text(document.name)
                    .font(thumbnailWidth > 40 ? .headline : .subheadline.weight(.semibold))
                    .lineLimit(2)
                Text(verbatim: "\(document.formattedPageCount) · \(document.formattedSize)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Progress shown while a task runs. Pass a progress value for a determinate ring.
struct WorkingView: View {
    let title: String
    let detail: String
    var progress: Double?

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.18), lineWidth: 10)
                if let progress {
                    Circle()
                        .trim(from: 0, to: max(0.02, progress))
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.3), value: progress)
                    Text(progress, format: .percent.precision(.fractionLength(0)))
                        .font(.system(.title, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                } else {
                    ProgressView()
                        .controlSize(.large)
                }
            }
            .frame(width: 120, height: 120)

            VStack(spacing: 4) {
                Text(title)
                    .font(.title3.weight(.semibold))
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// Success header: green check, headline and file name.
struct ResultHeader: View {
    let headline: String
    let detail: String

    @State private var appeared = false

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .background(Color.green.gradient, in: Circle())
                .scaleEffect(appeared ? 1 : 0.5)
                .opacity(appeared ? 1 : 0)
                .padding(.bottom, 6)
            Text(headline)
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .monospacedDigit()
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.6)) { appeared = true }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Shown when a task fails.
struct TaskFailedView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Something went wrong", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again", action: retry)
                .secondaryButtonStyle()
        }
    }
}

/// "Free actions left today" with a link to Mino Pro. Hidden for Pro users.
struct FreeAllowanceView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if !appState.isPro {
            let remaining = appState.usage.remaining
            HStack(spacing: 8) {
                HStack(spacing: 3) {
                    ForEach(0..<FreeUsage.dailyLimit, id: \.self) { index in
                        Circle()
                            .fill(index < remaining ? Color.accentColor : Color.secondary.opacity(0.25))
                            .frame(width: 7, height: 7)
                    }
                }
                .accessibilityHidden(true)
                Text("\(remaining) free actions left today")
                    .foregroundStyle(.secondary)
                Button("Get Pro") { appState.showPaywall(.general) }
                    .fontWeight(.semibold)
            }
            .font(.footnote)
            .frame(maxWidth: .infinity)
        }
    }
}

/// Opens the system "Save to Files" picker for a file.
struct SaveToFilesButton: View {
    let urls: [URL]
    @State private var isExporting = false

    var body: some View {
        Button {
            isExporting = true
        } label: {
            Label("Save to Files", systemImage: "folder")
        }
        .sheet(isPresented: $isExporting) {
            DocumentExporter(urls: urls) { _ in isExporting = false }
                .ignoresSafeArea()
        }
    }
}
