import CoreLocation
import MapKit
import SwiftUI

/// Finds gyms on Apple Maps: the ones near you when the field is empty, or whatever you search for.
/// Location is only asked for when the picker opens, and the picker still works without it.
@Observable
final class GymSearch {
    private(set) var results: [Gym] = []
    private(set) var isSearching = false
    /// Where you are, once location has been allowed. Nil until then, or if it wasn't.
    private(set) var here: CLLocationCoordinate2D?
    private(set) var locationDenied = false

    /// One location fix, asking for permission the first time. Gives up after a few seconds.
    func locate() async {
        let session = CLServiceSession(authorization: .whenInUse)
        defer { session.invalidate() }
        let deadline = Date.now.addingTimeInterval(8)
        do {
            for try await update in CLLocationUpdate.liveUpdates() {
                if let location = update.location {
                    here = location.coordinate
                    return
                }
                if update.authorizationDenied || update.authorizationDeniedGlobally {
                    locationDenied = true
                    return
                }
                if Date.now > deadline { return }
            }
        } catch {
            return
        }
    }

    /// Gyms matching `query`, near you when your location is known. An empty query lists gyms nearby.
    func search(_ query: String) async {
        let text = query.trimmingCharacters(in: .whitespaces)
        if text.isEmpty, here == nil {
            results = []
            return
        }
        isSearching = true
        defer { isSearching = false }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text.isEmpty ? "gym" : text
        request.resultTypes = .pointOfInterest
        if text.isEmpty { request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.fitnessCenter]) }
        if let here { request.region = MKCoordinateRegion(center: here, latitudinalMeters: 20_000, longitudinalMeters: 20_000) }
        guard let response = try? await MKLocalSearch(request: request).start(), !Task.isCancelled else { return }
        results = response.mapItems.compactMap { item in
            let place = item.placemark
            return Gym(name: item.name ?? "", address: Self.shortAddress(of: place), latitude: place.coordinate.latitude, longitude: place.coordinate.longitude)
        }
    }

    /// The street and suburb, such as "186 Victoria St West, Auckland CBD". Enough to tell two branches of
    /// one gym apart without the postcode and country running off the row.
    static func shortAddress(of place: MKPlacemark) -> String? {
        let street = [place.subThoroughfare, place.thoroughfare].compactMap { $0 }.joined(separator: " ")
        let parts = [street.isEmpty ? nil : street, place.subLocality ?? place.locality].compactMap { $0 }
        return parts.isEmpty ? place.title : parts.joined(separator: ", ")
    }
}

/// Picks where a workout was done: gyms near you or from a search on the map, the gyms you've used before,
/// or a name you type when there's nothing on the map, such as "Home".
struct GymPicker: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    let current: Gym?
    let recent: [Gym]
    let onPick: (Gym?) -> Void

    /// Debug builds can fill the search on launch with `-gymQuery <text>`, for screenshots.
    @State private var query: String = {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "-gymQuery"), index + 1 < args.count { return args[index + 1] }
        #endif
        return ""
    }()
    @State private var search = GymSearch()
    @FocusState private var searching: Bool

    private var typed: Gym? { Gym(name: query) }

    /// Recent gyms that match what's typed, so the list narrows as you search.
    private var matchingRecent: [Gym] {
        let text = query.trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? recent : recent.filter { $0.name.localizedCaseInsensitiveContains(text) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Text("Gym")
                    .textStyle(Tokens.Typography.title)
                    .foregroundStyle(palette.foreground)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .foregroundStyle(palette.foreground)
                        .frame(width: Tokens.Size.control, height: Tokens.Size.control)
                }
                .buttonStyle(.press)
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, Tokens.Space.xxl)
            .padding(.top, Tokens.Space.xxl)

            HStack(spacing: Tokens.Space.s) {
                Image(systemName: "magnifyingglass").foregroundStyle(palette.foregroundMuted)
                TextField("", text: $query, prompt: Text("Search, or type a name").foregroundStyle(palette.foregroundFaint))
                    .textStyle(Tokens.Typography.body)
                    .foregroundStyle(palette.foreground)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .focused($searching)
                    .onSubmit { if let typed { pick(typed) } }
            }
            .padding(.horizontal, Tokens.Space.m)
            .frame(height: Tokens.Size.primaryButton)
            .background(palette.surface, in: .rect(cornerRadius: Tokens.Radius.control))
            .padding(.horizontal, Tokens.Space.xxl)
            .padding(.top, Tokens.Space.l)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let typed, !recent.contains(where: { $0.name.caseInsensitiveCompare(typed.name) == .orderedSame }) {
                        row(title: "Use \u{201C}\(typed.name)\u{201D}", subtitle: "Without a map location", systemImage: "text.cursor") { pick(typed) }
                    }
                    if !matchingRecent.isEmpty {
                        caption("Recent")
                        ForEach(matchingRecent, id: \.self) { gym in gymRow(gym) }
                    }
                    caption(query.trimmingCharacters(in: .whitespaces).isEmpty ? "Near you" : "On the map")
                    if search.isSearching, search.results.isEmpty {
                        ProgressView().padding(.vertical, Tokens.Space.l)
                    } else if search.results.isEmpty {
                        Text(emptyMessage)
                            .textStyle(Tokens.Typography.caption)
                            .foregroundStyle(palette.foregroundMuted)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.vertical, Tokens.Space.m)
                    }
                    ForEach(search.results.filter { !recent.contains($0) }, id: \.self) { gym in gymRow(gym) }
                    if current != nil {
                        Button {
                            pick(nil)
                        } label: {
                            Text("Clear gym")
                                .textStyle(Tokens.Typography.body)
                                .foregroundStyle(palette.accent)
                                .frame(maxWidth: .infinity, minHeight: Tokens.Size.setRow, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.pressRow)
                        .padding(.top, Tokens.Space.l)
                    }
                }
                .padding(.horizontal, Tokens.Space.xxl)
                .padding(.bottom, Tokens.Space.xxxl)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(palette.background)
        .presentationDetents([.large])
        .presentationBackground(palette.background)
        .animation(.standard, value: search.results)
        .task {
            await search.locate()
            await search.search(query)
        }
        .task(id: query) {
            // Waits for typing to pause, so every letter doesn't send a search.
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await search.search(query)
        }
    }

    private var emptyMessage: String {
        if !query.trimmingCharacters(in: .whitespaces).isEmpty { return "Nothing on the map for that. You can still use the name you typed." }
        if search.locationDenied { return "Location is off, so there's nothing nearby to show. Search for your gym, or type its name." }
        return "Search for your gym, or type its name."
    }

    private func pick(_ gym: Gym?) {
        onPick(gym)
        dismiss()
    }

    private func gymRow(_ gym: Gym) -> some View {
        row(title: gym.name, subtitle: gym.address ?? (gym.coordinate == nil ? "Typed" : nil),
            systemImage: gym.coordinate == nil ? "text.cursor" : "mappin.and.ellipse",
            isSelected: gym == current) { pick(gym) }
    }

    private func row(title: String, subtitle: String?, systemImage: String, isSelected: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Tokens.Space.m) {
                Image(systemName: systemImage)
                    .foregroundStyle(palette.foregroundMuted)
                    .frame(width: Tokens.Space.xxl)
                VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                    Text(title)
                        .textStyle(Tokens.Typography.body)
                        .foregroundStyle(palette.foreground)
                    if let subtitle {
                        Text(subtitle)
                            .textStyle(Tokens.Typography.caption)
                            .foregroundStyle(palette.foregroundMuted)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if isSelected { Image(systemName: "checkmark").foregroundStyle(palette.foreground) }
            }
            .frame(minHeight: Tokens.Size.setRow)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressRow)
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .textStyle(Tokens.Typography.caption)
            .foregroundStyle(palette.foregroundMuted)
            .padding(.top, Tokens.Space.xl)
            .padding(.bottom, Tokens.Space.xs)
    }
}

/// The gym as an outlined button, such as "City Gym", or "Add gym" when there's none. Opens the picker.
struct GymButton: View {
    @Environment(\.palette) private var palette
    let gym: Gym?
    let recent: [Gym]
    let onPick: (Gym?) -> Void
    @State private var picking = false

    var body: some View {
        Button { picking = true } label: {
            OutlinedLabel(systemImage: "mappin.and.ellipse", text: gym?.name ?? "Add gym", showsChevron: true, isMuted: gym == nil)
        }
        .buttonStyle(.press)
        .accessibilityLabel(gym.map { "Gym, \($0.name)" } ?? "Add gym")
        .onAppear {
            // Debug builds open the picker on launch with `-openGymPicker`, for screenshots.
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-openGymPicker") { picking = true }
            #endif
        }
        .sheet(isPresented: $picking) {
            GymPicker(current: gym, recent: recent, onPick: onPick)
                .environment(\.palette, palette)
        }
    }
}

/// A small, still map with a pin on the gym, for the workout's page. Tapping it opens Apple Maps there.
struct GymMap: View {
    @Environment(\.palette) private var palette
    let gym: Gym
    let coordinate: CLLocationCoordinate2D

    var body: some View {
        Map(initialPosition: .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 600, longitudinalMeters: 600)), interactionModes: []) {
            Marker(gym.name, systemImage: "dumbbell.fill", coordinate: coordinate)
                .tint(palette.accent)
        }
        .frame(height: 140)
        .clipShape(.rect(cornerRadius: Tokens.Radius.panel))
        .onTapGesture {
            let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
            item.name = gym.name
            item.openInMaps()
        }
        .accessibilityElement()
        .accessibilityLabel("Map of \(gym.name)")
        .accessibilityHint("Opens it in Maps")
        .accessibilityAddTraits(.isButton)
    }
}
