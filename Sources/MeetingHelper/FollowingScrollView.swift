import SwiftUI

/// Follow streamed content only while the reader is at the end. Content growth
/// itself must not be mistaken for the reader scrolling away from the bottom.
struct FollowingScrollView<Revision: Equatable, Content: View>: View {
    let revision: Revision
    @ViewBuilder var content: () -> Content
    @ViewState private var followsEnd = true
    @ViewState private var phase = ScrollPhase.idle
    @ViewState private var userScrolling = false
    private let endID = "response-end"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    content()
                    Color.clear.frame(height: 1).id(endID)
                }
            }
            .onScrollGeometryChange(for: Metrics.self) { geometry in
                Metrics(geometry)
            } action: { old, new in
                if phase != .idle && phase != .animating {
                    followsEnd = new.isAtEnd
                } else if followsEnd && old.contentHeight != new.contentHeight {
                    proxy.scrollTo(endID, anchor: .bottom)
                }
            }
            .onScrollPhaseChange { _, new, context in
                phase = new
                if new == .tracking || new == .interacting || new == .decelerating {
                    userScrolling = true
                    followsEnd = Metrics(context.geometry).isAtEnd
                } else if new == .idle {
                    if userScrolling { followsEnd = Metrics(context.geometry).isAtEnd }
                    userScrolling = false
                    if followsEnd { proxy.scrollTo(endID, anchor: .bottom) }
                }
            }
            .onChange(of: revision) { _, _ in
                if followsEnd && phase == .idle { proxy.scrollTo(endID, anchor: .bottom) }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !followsEnd {
                    HStack {
                        Spacer()
                        Button {
                            followsEnd = true
                            proxy.scrollTo(endID, anchor: .bottom)
                        } label: {
                            Label("Latest answer", systemImage: "arrow.down")
                        }
                        .buttonStyle(.bordered).controlSize(.small)
                        .help("Jump to the end and follow new AI text")
                        Spacer()
                    }.padding(.vertical, 6).background(.bar)
                }
            }
        }
    }

    private struct Metrics: Equatable {
        let contentHeight: CGFloat
        let isAtEnd: Bool

        init(_ geometry: ScrollGeometry) {
            contentHeight = geometry.contentSize.height
            isAtEnd = geometry.contentSize.height - geometry.visibleRect.maxY <= 32
        }
    }
}
