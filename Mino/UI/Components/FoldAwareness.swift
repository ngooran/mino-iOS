//
//  FoldAwareness.swift
//  Mino
//
//  iPhone Duo book pose: the hinge splits the inner display into two regions.
//  iOS 27.1 reports it as a "division" reserved region. Nothing important
//  should sit across it.
//

import SwiftUI

/// Narrowest side of a fold that still works as a page of its own.
private let minimumPageWidth: CGFloat = 280

extension View {
    /// Reports the frame of a vertical fold (the book-pose hinge) in this view's
    /// own coordinates, or nil when there is none (iPhone, iPad, older iOS).
    /// Only a fold with a usable page on both sides counts: a sheet that sits on
    /// one half of the display and merely touches the hinge band reports nil.
    ///
    /// - Parameter includeInactive: Also report the fold while the device lies flat.
    ///   Use it for layout structure (column widths) so the layout doesn't jump
    ///   while folding. Leave it off to react only when the device is actually bent.
    func readVerticalFold(includeInactive: Bool, into fold: Binding<CGRect?>) -> some View {
        onGeometryChange(for: CGRect?.self) { proxy in
            guard #available(iOS 27.1, *) else { return nil }
            let options: ReservedRegion.QueryOptions = includeInactive ? .includeInactive : []
            return proxy.reservedRegions(kind: .division, options: options)
                .map(\.frame)
                .first { $0.height > $0.width && $0.minX >= minimumPageWidth && proxy.size.width - $0.maxX >= minimumPageWidth }
        } action: { newValue in
            fold.wrappedValue = newValue
        }
    }

    /// Keeps content out of a fold band that overlaps this view's leading or
    /// trailing edge, as happens to split view columns that meet at the hinge.
    /// The background still extends under the fold; only content moves.
    func avoidingFoldEdges() -> some View {
        modifier(FoldEdgeInsets())
    }
}

private struct FoldEdgeInsets: ViewModifier {
    @State private var insets = HorizontalInsets()

    nonisolated struct HorizontalInsets: Equatable, Sendable {
        var leading: CGFloat = 0
        var trailing: CGFloat = 0
    }

    func body(content: Content) -> some View {
        content
            .safeAreaPadding(.leading, insets.leading)
            .safeAreaPadding(.trailing, insets.trailing)
            .onGeometryChange(for: HorizontalInsets.self) { proxy in
                var result = HorizontalInsets()
                guard #available(iOS 27.1, *) else { return result }
                let width = proxy.size.width
                // Inactive folds count too, so content doesn't shift while folding.
                for frame in proxy.reservedRegions(kind: .division, options: .includeInactive).map(\.frame)
                where frame.height > frame.width {
                    if frame.minX <= 0, frame.maxX > 0, frame.maxX < width {
                        result.leading = max(result.leading, frame.maxX)
                    }
                    if frame.maxX >= width, frame.minX < width, frame.minX > 0 {
                        result.trailing = max(result.trailing, width - frame.minX)
                    }
                }
                return result
            } action: { insets = $0 }
    }
}

#if DEBUG
/// Launch with `-showRegions` to outline every reserved region the system reports.
struct ReservedRegionsDebugOverlay: View {
    var body: some View {
        if ProcessInfo.processInfo.arguments.contains("-showRegions") {
            GeometryReader { proxy in
                if #available(iOS 27.1, *) {
                    let division = proxy.reservedRegions(kind: .division, options: .includeInactive)
                    let occlusion = proxy.reservedRegions(kind: .occlusion, options: .includeInactive)
                    ZStack(alignment: .topLeading) {
                        ForEach(division + occlusion) { region in
                            Rectangle()
                                .stroke(region.kind == .division ? Color.red : Color.yellow, lineWidth: 3)
                                .background((region.kind == .division ? Color.red : Color.yellow).opacity(0.15))
                                .frame(width: region.frame.width, height: region.frame.height)
                                .offset(x: region.frame.minX, y: region.frame.minY)
                        }
                        Text(([ "size \(Int(proxy.size.width))x\(Int(proxy.size.height))" ] + (division + occlusion).map {
                            "\($0.kind) active=\($0.isActive) frame=\(Int($0.frame.minX)),\(Int($0.frame.minY)),\(Int($0.frame.width))x\(Int($0.frame.height)) margins=\(Int($0.margins.leading)),\(Int($0.margins.trailing)),\(Int($0.margins.top)),\(Int($0.margins.bottom))"
                        }).joined(separator: "\n"))
                        .font(.system(size: 13, design: .monospaced))
                        .padding(6)
                        .background(.black.opacity(0.8))
                        .foregroundStyle(.green)
                        .offset(x: 60, y: proxy.size.height - 160)
                    }
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }
}
#endif
