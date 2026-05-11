import SwiftUI

struct ErrorToastView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 8))
    }
}
