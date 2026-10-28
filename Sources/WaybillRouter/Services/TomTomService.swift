import Foundation

struct Coordinate: Hashable {
    var lat: Double
    var lon: Double
}

struct GeocodeHit: Hashable {
    var label: String
    var coordinate: Coordinate
}

struct RouteResult {
    /// Kolejność firm (indeksy z przekazanej tablicy) po optymalizacji TomTom.
    var order: [Int]
    var lengthMeters: Int
    var travelSeconds: Int
}

enum TomTomError: LocalizedError {
    case missingKey
    case http(Int, String)
    case noRoute

    var errorDescription: String? {
        switch self {
        case .missingKey: "Brak klucza TomTom. Wpisz go w Ustawieniach."
        case .http(let code, let body): "TomTom zwrócił błąd \(code): \(body.prefix(200))"
        case .noRoute: "TomTom nie zwrócił trasy."
        }
    }
}

/// Wyszukiwanie adresów i liczenie tras przez TomTom REST API.
/// Parametry trasy (pojazd, unikanie promów itd.) są w `routeQuery`.
struct TomTomService {
    var apiKey: String = Defaults.tomTomKey
    var truckProfile: Bool = UserDefaults.standard.bool(forKey: SettingsKey.truckProfile)

    private static let pathAllowed: CharacterSet = {
        var set = CharacterSet.urlPathAllowed
        set.remove(charactersIn: "/?#%;")
        return set
    }()

    /// Szuka firmy/adresu w Polsce, najbliżej magazynu.
    func geocode(_ query: String, near: Coordinate) async throws -> GeocodeHit? {
        try await search(query, near: near, limit: 1).first
    }

    /// Kilka propozycji (firmy i adresy) dla wpisanego tekstu, najbliższe magazynowi pierwsze.
    func search(_ query: String, near: Coordinate, limit: Int = 8) async throws -> [GeocodeHit] {
        guard !apiKey.isEmpty else { throw TomTomError.missingKey }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let q = trimmed.addingPercentEncoding(withAllowedCharacters: Self.pathAllowed) ?? ""
        var c = URLComponents(string: "https://api.tomtom.com/search/2/search/\(q).json")!
        c.queryItems = [
            .init(name: "key", value: apiKey),
            .init(name: "countrySet", value: "PL"),
            .init(name: "language", value: "pl-PL"),
            .init(name: "limit", value: String(limit)),
            .init(name: "typeahead", value: "true"),
            .init(name: "lat", value: String(near.lat)),
            .init(name: "lon", value: String(near.lon)),
        ]
        let response: SearchResponse = try await get(c.url!)
        var seen = Set<String>()
        return response.results.compactMap { r in
            let addr = r.address?.freeformAddress ?? trimmed
            let label = [r.poi?.name, addr].compactMap { $0 }.joined(separator: ", ")
            guard seen.insert(label).inserted else { return nil }
            return GeocodeHit(label: label, coordinate: Coordinate(lat: r.position.lat, lon: r.position.lon))
        }
    }

    /// Trasa magazyn → przystanki → magazyn. `computeBestOrder=true` układa przystanki optymalnie (TSP);
    /// początek i koniec trasy zostają na miejscu.
    func route(depot: Coordinate, stops: [Coordinate]) async throws -> RouteResult {
        guard !apiKey.isEmpty else { throw TomTomError.missingKey }
        let points = ([depot] + stops + [depot]).map { "\($0.lat),\($0.lon)" }.joined(separator: ":")
        var c = URLComponents(string: "https://api.tomtom.com/routing/1/calculateRoute/\(points)/json")!
        c.queryItems = [URLQueryItem(name: "key", value: apiKey)] + routeQuery(optimize: stops.count > 1)
        let response: RouteResponse = try await get(c.url!)
        guard let route = response.routes.first else { throw TomTomError.noRoute }
        var order = Array(stops.indices)
        if let opt = response.optimizedWaypoints, opt.count == stops.count {
            order = opt.sorted { $0.optimizedIndex < $1.optimizedIndex }.map(\.providedIndex)
        }
        return RouteResult(
            order: order,
            lengthMeters: route.summary.lengthInMeters,
            travelSeconds: route.summary.travelTimeInSeconds
        )
    }

    private func routeQuery(optimize: Bool) -> [URLQueryItem] {
        var items: [URLQueryItem] = [
            .init(name: "routeType", value: "fastest"),
            .init(name: "traffic", value: "false"),
            .init(name: "avoid", value: "ferries"),
            .init(name: "avoid", value: "unpavedRoads"),
        ]
        if optimize {
            items.append(.init(name: "computeBestOrder", value: "true"))
        }
        if truckProfile {
            // Peugeot Boxer: dostawczy do 3,5 t. Zmień, jeśli jeździsz innym autem.
            items += [
                .init(name: "travelMode", value: "truck"),
                .init(name: "vehicleCommercial", value: "true"),
                .init(name: "vehicleWeight", value: "3500"),
                .init(name: "vehicleLength", value: "6.4"),
                .init(name: "vehicleWidth", value: "2.1"),
                .init(name: "vehicleHeight", value: "2.8"),
            ]
        } else {
            items.append(.init(name: "travelMode", value: "car"))
        }
        return items
    }

    private func get<T: Decodable>(_ url: URL) async throws -> T {
        let (data, response) = try await URLSession.shared.data(from: url)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else {
            throw TomTomError.http(code, String(decoding: data, as: UTF8.self))
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

// MARK: - Odpowiedzi API

private struct SearchResponse: Decodable {
    struct Result: Decodable {
        struct Position: Decodable { var lat: Double; var lon: Double }
        struct Address: Decodable { var freeformAddress: String? }
        struct POI: Decodable { var name: String? }
        var position: Position
        var address: Address?
        var poi: POI?
    }
    var results: [Result]
}

private struct RouteResponse: Decodable {
    struct Route: Decodable {
        struct Summary: Decodable {
            var lengthInMeters: Int
            var travelTimeInSeconds: Int
        }
        var summary: Summary
    }
    struct Waypoint: Decodable {
        var providedIndex: Int
        var optimizedIndex: Int
    }
    var routes: [Route]
    var optimizedWaypoints: [Waypoint]?
}
