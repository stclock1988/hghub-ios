// HGHub iOS v1 — shared UI pieces.

import SwiftUI

/// A cover image: fetched through CoverDecryptor (AES-128-CBC
/// decrypted when the CDN returns ciphertext, map §6).
struct CoverImage: View {
    @EnvironmentObject private var edge: EdgeClient
    var urlString: String

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            Color(uiColor: .secondarySystemBackground)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if failed {
                Image(systemName: "photo")
                    .foregroundColor(.secondary)
            } else {
                ProgressView()
            }
        }
        .clipped()
        .task(id: urlString) {
            image = nil
            failed = false
            guard !urlString.isEmpty else { failed = true; return }
            do {
                let data = try await CoverDecryptor.shared.imageData(for: urlString, edge: edge)
                if let uiImage = UIImage(data: data) {
                    image = uiImage
                } else {
                    failed = true
                }
            } catch {
                failed = true
            }
        }
    }
}

struct ErrorStateView: View {
    var message: String
    var retry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundColor(.secondary)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button("重试", action: retry)
                .buttonStyle(.bordered)
        }
        .padding()
    }
}

/// A 3-column cover grid card used by Home / Search / Category.
struct VideoCardView: View {
    var card: VideoCard

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            CoverImage(urlString: card.cover)
                .aspectRatio(3 / 4, contentMode: .fit)
                .cornerRadius(8)
            Text(card.title)
                .font(.caption)
                .lineLimit(2)
            HStack(spacing: 4) {
                if card.score > 0 {
                    Text(String(format: "%.1f", card.score))
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
                Text("\(card.episode_count)集")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                if card.is_finished {
                    Text("已完结")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

struct VideoGrid: View {
    var cards: [VideoCard]

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
            spacing: 12
        ) {
            ForEach(cards) { card in
                NavigationLink(destination: DetailView(videoId: card.id)) {
                    VideoCardView(card: card)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal)
    }
}
