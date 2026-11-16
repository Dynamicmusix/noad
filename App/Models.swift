import Foundation
import SafariServices
import NetworkExtension

public struct SafariContentRule: Codable, Identifiable {
    public var id: String { "\(trigger.urlFilter)|\(action.type)|\(action.selector ?? "")" }
    public var trigger: Trigger
    public var action: Action

    public struct Trigger: Codable {
        public var urlFilter: String
        public var loadType: [String]?
        public var resourceType: [String]?
        public var ifDomain: [String]?
        public var unlessDomain: [String]?
        public var urlFilterIsCaseSensitive: Bool?

        enum CodingKeys: String, CodingKey {
            case urlFilter = "url-filter"
            case loadType = "load-type"
            case resourceType = "resource-type"
            case ifDomain = "if-domain"
            case unlessDomain = "unless-domain"
            case urlFilterIsCaseSensitive = "url-filter-is-case-sensitive"
        }
    }

    public struct Action: Codable {
        public var type: String
        public var selector: String?
    }
}

public enum RegionalRuleset: String, CaseIterable, Identifiable {
    case none = "none"
    case arabic = "arabic"
    case bulgarian = "bulgarian"
    case chinese = "chinese"
    case czechSlovak = "czech-slovak"
    case dutch = "dutch"
    case french = "french"
    case german = "german"
    case hebrew = "hebrew"
    case indian = "indian"
    case indonesian = "indonesian"
    case italian = "italian"
    case japanese = "japanese"
    case korean = "korean"
    case latvian = "latvian"
    case lithuanian = "lithuanian"
    case nordic = "nordic"
    case polish = "polish"
    case portuguese = "portuguese"
    case romanian = "romanian"
    case russianUkranian = "russian-ukranian"
    case spanish = "spanish"
    case vietnamese = "vietnamese"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .none: return "Disabled (English / Global Only)"
        case .arabic: return "Arabic (1,237 rules)"
        case .bulgarian: return "Bulgarian (886 rules)"
        case .chinese: return "Chinese (10,000 rules)"
        case .czechSlovak: return "Czech & Slovak (404 rules)"
        case .dutch: return "Dutch (1,079 rules)"
        case .french: return "French (10,000 rules)"
        case .german: return "German (3,857 rules)"
        case .hebrew: return "Hebrew (658 rules)"
        case .indian: return "Indian (9,134 rules)"
        case .indonesian: return "Indonesian (4,888 rules)"
        case .italian: return "Italian (2,822 rules)"
        case .japanese: return "Japanese (6,443 rules)"
        case .korean: return "Korean (892 rules)"
        case .latvian: return "Latvian (271 rules)"
        case .lithuanian: return "Lithuanian (871 rules)"
        case .nordic: return "Nordic — DK/FI/IS/NO/SE (4,563 rules)"
        case .polish: return "Polish (2,307 rules)"
        case .portuguese: return "Portuguese (940 rules)"
        case .romanian: return "Romanian (413 rules)"
        case .russianUkranian: return "Russian & Ukrainian (1,284 rules)"
        case .spanish: return "Spanish (1,710 rules)"
        case .vietnamese: return "Vietnamese (713 rules)"
        }
    }

    public var localFilename: String? {
        self == .none ? nil : "regional-\(rawValue)"
    }

    public var remotePath: String? {
        self == .none ? nil : "regional/\(rawValue).json"
    }
}

public enum EncryptedDNSProvider: String, CaseIterable, Identifiable {
    case adguard = "AdGuard AdBlock DNS"
    case adguardFamily = "AdGuard Family DNS"
    case mullvadAdblock = "Mullvad AdBlock DoH"
    case controlDAds = "Control D (Ads & Trackers)"
    case custom = "Custom DoH Server"

    public var id: String { rawValue }

    public var serverURL: String {
        switch self {
        case .adguard: return "https://dns.adguard-dns.com/dns-query"
        case .adguardFamily: return "https://family.adguard-dns.com/dns-query"
        case .mullvadAdblock: return "https://adblock.dns.mullvad.net/dns-query"
        case .controlDAds: return "https://freedns.controld.com/p2"
        case .custom: return "https://dns.adguard-dns.com/dns-query"
        }
    }

    public var serverAddresses: [String] {
        switch self {
        case .adguard: return ["94.140.14.14", "94.140.15.15", "2a10:50c0::ad1:ff", "2a10:50c0::ad2:ff"]
        case .adguardFamily: return ["94.140.14.15", "94.140.15.16", "2a10:50c0::bad1:ff", "2a10:50c0::bad2:ff"]
        case .mullvadAdblock: return ["194.242.2.3", "2a07:e340::3"]
        case .controlDAds: return ["76.76.2.2", "76.76.10.2"]
        case .custom: return []
        }
    }
}
