import Lowtech
import SwiftUI
import System

struct OpenWithMenuView: View {
    let fileURLs: [URL]

    var body: some View {
        Menu("⌘O Open with...   ") {
            let apps = commonApplications(for: fileURLs).sorted(by: \.lastPathComponent)
            ForEach(apps, id: \.path) { app in
                Button(action: {
                    NSWorkspace.shared.open(
                        fileURLs, withApplicationAt: app, configuration: .init(),
                        completionHandler: { _, _ in }
                    )
                }) {
                    SwiftUI.Image(nsImage: icon(for: app))
                    Text(app.lastPathComponent.ns.deletingPathExtension)
                }
            }
        }
    }

}

struct OpenWithPickerView: View {
    let fileURLs: [URL]
    @Environment(\.dismiss) var dismiss
    @State private var fuzzy: FuzzyClient = FUZZY
    @State private var filterText = ""

    private var apps: [URL] {
        if filterText.isEmpty {
            return fuzzy.commonOpenWithApps
        }
        let query = filterText.lowercased()
        return fuzzy.installedApps
            .compactMap { url -> (URL, Int)? in
                let name = url.lastPathComponent.ns.deletingPathExtension.lowercased()
                guard let score = fuzzyMatchScore(query: query, target: name) else { return nil }
                return (url, score)
            }
            .sorted(by: { $0.1 > $1.1 })
            .map(\.0)
    }

    func openWithApp(_ app: URL) {
        RH.trackRun(fileURLs.compactMap(\.existingFilePath))
        NSWorkspace.shared.open(
            fileURLs, withApplicationAt: app, configuration: .init(),
            completionHandler: { _, _ in }
        )
        dismiss()
    }

    func appButton(_ app: URL) -> some View {
        Button(action: { openWithApp(app) }) {
            HStack(spacing: 8) {
                SwiftUI.Image(nsImage: icon(for: app))
                Text(app.lastPathComponent.ns.deletingPathExtension)
            }
            .padding(.leading, 4)
            .padding(.trailing, 24)
            .padding(.vertical, 6)
            .frame(minWidth: 300, maxWidth: .infinity, alignment: .leading)
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            TextField("Filter apps...", text: $filterText)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 300)
                .onSubmit {
                    if let first = apps.first {
                        openWithApp(first)
                    }
                }

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(apps, id: \.path) { app in
                        appButton(app)
                            .buttonStyle(FlatButton(color: .bg.primary.opacity(0.4), textColor: .primary))
                    }.focusable(false)
                }
            }
        }
        .padding(18)
        .fixedSize(horizontal: true, vertical: false)
        .frame(maxHeight: 500)
    }
}

struct OpenWithActionButtons: View {
    let selectedResults: Set<FilePath>

    var buttons: some View {
        ForEach(fuzzy.openWithAppShortcuts.sorted(by: \.key.lastPathComponent), id: \.0.path) { app, key in
            Button(action: {
                RH.trackRun(selectedResults)
                NSWorkspace.shared.open(selectedResults.map(\.url), withApplicationAt: app, configuration: .init(), completionHandler: { _, _ in })
            }) {
                HStack(spacing: 0) {
                    Text("\(key.uppercased())").mono(10, weight: .bold).foregroundColor(.fg.warm).roundbg(color: .bg.primary.opacity(0.2))
                    Text(" \(app.lastPathComponent.ns.deletingPathExtension)")
                }
            }
        }
        .buttonStyle(.borderlessText(color: .fg.warm.opacity(0.8)))
    }

    var body: some View {
        HStack {
            OpenWithMenuView(fileURLs: selectedResults.map(\.url))
                .help("Open the selected files with a specific app")
                .frame(width: 110, alignment: .leading)
                .disabled(selectedResults.isEmpty || fuzzy.openWithAppShortcuts.isEmpty)

            Divider().frame(height: 16)

            if fuzzy.openWithAppShortcuts.isEmpty {
                Text("Open with app hotkeys will appear here")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 10))
            } else {
                HStack(spacing: 1) {
                    Text("⌘").roundbg(color: .bg.primary.opacity(0.2))
                    Text("⌥").roundbg(color: .bg.primary.opacity(0.2))
                    Text(" +")
                }.foregroundColor(.fg.warm)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 3) { buttons }
                }
                Divider().frame(height: 16)
                ShareButton(urls: selectedResults.map(\.url))
                    .bold()
                    .buttonStyle(.borderlessText)
            }
        }
        .font(.system(size: 10))
        .buttonStyle(.text(color: .fg.warm.opacity(0.9)))
        .lineLimit(1)
    }

    @State private var fuzzy: FuzzyClient = FUZZY

}

func icon(for app: URL) -> NSImage {
    if let cached = FUZZY.appIconCache[app.path] {
        return cached
    }
    let i = NSWorkspace.shared.icon(forFile: app.path)
    i.size = NSSize(width: 16, height: 16)
    FUZZY.appIconCache[app.path] = i
    return i
}

extension URL {
    var bundleIdentifier: String? {
        guard let bundle = Bundle(url: self) else {
            return nil
        }
        return bundle.bundleIdentifier
    }
}

/// Returns a score for how well `query` fuzzy-matches `target`, or nil if no match.
/// Higher scores indicate better matches. Rewards consecutive and first-character matches.
/// Penalizes matches that span across word boundaries (spaces/hyphens).
func fuzzyMatchScore(query: String, target: String) -> Int? {
    var score = 0
    var consecutive = 0
    var lastMatchIdx = -1
    let targetChars = Array(target)

    var ti = 0
    for qChar in query {
        var found = false
        while ti < targetChars.count {
            if targetChars[ti] == qChar {
                if ti == 0 {
                    score += 10
                } else if targetChars[ti - 1] == " " || targetChars[ti - 1] == "-" {
                    score += 3
                }

                consecutive += 1
                score += consecutive

                if lastMatchIdx >= 0, lastMatchIdx + 1 != ti {
                    for gi in (lastMatchIdx + 1) ..< ti where targetChars[gi] == " " || targetChars[gi] == "-" {
                        score -= 4
                        break
                    }
                }

                lastMatchIdx = ti
                ti += 1
                found = true
                break
            }
            consecutive = 0
            ti += 1
        }
        if !found { return nil }
    }

    return score
}
