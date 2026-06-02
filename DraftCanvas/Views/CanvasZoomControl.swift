import SwiftUI

struct CanvasZoomControl: View {
    @Binding var zoom: CGFloat
    private let minZoom: CGFloat = 0.25
    private let maxZoom: CGFloat = 4.0
    private let step: CGFloat = 0.1

    var body: some View {
        HStack(spacing: 3) {
            Button {
                withAnimation(.smooth(duration: 0.2)) {
                    zoom = max(minZoom, zoom - step)
                }
            } label: {
                Image(systemName: "minus")
                    .frame(width: 18, height: 18)
                    .padding(5)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(zoom <= minZoom)

            Slider(value: $zoom, in: minZoom...maxZoom)
                .frame(width: 140)

            Button {
                withAnimation(.smooth(duration: 0.2)) {
                    zoom = min(maxZoom, zoom + step)
                }
            } label: {
                Image(systemName: "plus")
                    .frame(width: 18, height: 18)
                    .padding(5)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(zoom >= maxZoom)

            Text("\(Int((zoom * 100).rounded()))%")
                .font(.caption.weight(.semibold).monospacedDigit())
                .frame(width: 44, alignment: .trailing)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.smooth(duration: 0.2)) {
                        zoom = 1.0
                    }
                }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.10), radius: 6, x: 0, y: 2)
    }
}
