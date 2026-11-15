//
//  PaywallView.swift
//  Mino
//
//  Mino Pro: one plan, one price, one button.
//

import SwiftUI

struct PaywallView: View {
    let reason: PaywallReason

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?
    @State private var infoMessage: String?
    @State private var isRestoring = false
    /// Active iPhone Duo hinge crossing the sheet (book pose).
    @State private var fold: CGRect?
    /// Short screens (open iPhone Duo, iPhone landscape) get a tighter header,
    /// so every feature fits above the pinned price and button.
    @State private var isShort = false

    private var store: ProStore { appState.store }

    /// What Pro adds, built from the tools that ship in this build.
    private var features: [(symbol: String, color: Color, text: String)] {
        var list: [(symbol: String, color: Color, text: String)] = [
            ("infinity", .teal, String(localized: "Unlimited actions, every day")),
        ]
        if Tool.scan.isAvailable && Tool.ocr.isAvailable {
            list.append((Tool.ocr.systemImage, .mint, String(localized: "Scan with text recognition")))
        }
        if Tool.fillSign.isAvailable {
            list.append((Tool.fillSign.systemImage, .pink, String(localized: "Fill, sign and edit")))
        }
        if Tool.pdfToWord.isAvailable {
            list.append((Tool.pdfToWord.systemImage, .blue, String(localized: "Convert to and from Word")))
        } else if Tool.officeToPDF.isAvailable {
            list.append((Tool.officeToPDF.systemImage, .blue, String(localized: "Convert Office files to PDF")))
        }
        list.append(("doc.on.doc.fill", .indigo, String(localized: "Merge, split and batch")))
        if Tool.protect.isAvailable {
            list.append((Tool.protect.systemImage, .gray, String(localized: "Password protection")))
        } else {
            list.append(("slider.horizontal.3", .gray, String(localized: "Custom quality and resolution")))
        }
        list.append(("person.2.fill", .green, String(localized: "Family Sharing for up to 6 people")))
        return list
    }

    var body: some View {
        NavigationStack {
            Group {
                if let fold {
                    foldedLayout(fold)
                } else {
                    standardLayout
                }
            }
            .background(Color.groupedBackground)
            // Only an actually bent hinge matters here; a flat display reads as one page.
            .readVerticalFold(includeInactive: false, into: $fold)
            .onGeometryChange(for: Bool.self) { $0.size.height < 720 } action: { isShort = $0 }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
            .alert("Purchase Failed", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .alert("Mino Pro", isPresented: Binding(get: { infoMessage != nil }, set: { if !$0 { infoMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(infoMessage ?? "")
            }
        }
        .task { await store.loadProduct() }
    }

    // MARK: - Layouts

    /// One column. Price and purchase button stay pinned at the bottom, so they're
    /// always on screen, even in a short iPad form sheet.
    private var standardLayout: some View {
        ScrollView {
            VStack(spacing: 16) {
                hero
                featureList
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .bottomActions {
            planCard
                .frame(maxWidth: 520)
                .padding(.bottom, 4)
            purchaseControls
                .frame(maxWidth: 520)
        }
        // A sheet on one half of an open iPhone Duo can touch the hinge band.
        .avoidingFoldEdges()
    }

    /// iPhone Duo book pose: what Pro includes on the leading page,
    /// price and purchase on the trailing page, nothing across the hinge.
    private func foldedLayout(_ fold: CGRect) -> some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    hero
                    featureList
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .frame(width: max(0, fold.minX))

            Color.clear
                .frame(width: fold.width)

            VStack(spacing: 16) {
                Spacer(minLength: 0)
                planCard
                purchaseControls
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Parts

    private var hero: some View {
        VStack(spacing: 8) {
            AppIconView(size: isShort ? 48 : 64)
                .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
            Text("Mino Pro")
                .font(isShort ? .title.bold() : .largeTitle.bold())
            Text(reason.message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var featureList: some View {
        VStack(spacing: 0) {
            ForEach(Array(features.enumerated()), id: \.offset) { index, feature in
                HStack(spacing: 12) {
                    IconTile(systemImage: feature.symbol, color: feature.color)
                    Text(feature.text)
                    Spacer()
                }
                .padding(.vertical, isShort ? 7 : 9)
                if index < features.count - 1 {
                    Divider().padding(.leading, 42)
                }
            }
        }
        .padding(.horizontal, 16)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var planCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Lifetime").font(.headline)
                Text("One payment. No subscription.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let price = store.displayPrice {
                Text(price)
                    .font(.system(.title2, design: .rounded, weight: .bold))
            } else {
                ProgressView()
            }
        }
        .cardStyle(cornerRadius: 22)
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.accentColor, lineWidth: 2)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var purchaseControls: some View {
        Button {
            Task { await purchase() }
        } label: {
            if store.isPurchasing {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            } else {
                ActionLabel(title: store.displayPrice.map { String(localized: "Unlock for \($0)") } ?? String(localized: "Unlock Mino Pro"))
            }
        }
        .primaryButtonStyle()
        .disabled(store.isPurchasing || isRestoring)

        HStack(spacing: 8) {
            Button("Restore Purchase") { Task { await restore() } }
                .disabled(store.isPurchasing || isRestoring)
            Text("·").accessibilityHidden(true)
            Link("Terms", destination: MinoLinks.terms)
            Text("·").accessibilityHidden(true)
            Link("Privacy", destination: MinoLinks.privacy)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .tint(.secondary)
    }

    // MARK: - Actions

    private func purchase() async {
        do {
            switch try await store.purchase() {
            case .purchased:
                HapticManager.shared.compressionComplete()
                appState.didUnlockPro()
            case .pending:
                infoMessage = String(localized: "Your purchase is waiting for approval. Mino Pro unlocks as soon as it's approved.")
            case .cancelled:
                break
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func restore() async {
        isRestoring = true
        defer { isRestoring = false }
        do {
            if try await store.restore() {
                appState.didUnlockPro()
            } else {
                infoMessage = String(localized: "No Mino Pro purchase was found for this Apple Account.")
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
