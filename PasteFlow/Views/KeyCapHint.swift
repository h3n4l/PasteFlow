import SwiftUI

struct KeyCapHint: View {
    let key: String
    let label: String?

    init(key: String, label: String? = nil) {
        self.key = key
        self.label = label
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundColor(Color(.textSecondary))
                .frame(minWidth: 16, minHeight: 14)
                .padding(.horizontal, 3)
                .background(Color(.textSecondary).opacity(0.12))
                .cornerRadius(3)
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color(.textSecondary).opacity(0.25), lineWidth: 0.5))
            if let label {
                Text(label)
                    .font(.system(size: 11))
                    .foregroundColor(Color(.textSecondary).opacity(0.7))
            }
        }
    }
}
