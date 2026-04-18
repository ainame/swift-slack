import Foundation

public enum Languages {
    public static let langToReaction: [String: String] = [
        "en": ":flag-us:",
        "ja": ":flag-jp:",
        "zh": ":flag-cn:",
        "ko": ":flag-kr:",
        "de": ":flag-de:",
        "fr": ":flag-fr:",
        "it": ":flag-it:",
        "es": ":flag-es:",
        "nl": ":flag-nl:",
        "pl": ":flag-pl:",
        "pt": ":flag-pt:",
        "ru": ":flag-ru:",
        "bg": ":flag-bg:",
        "cs": ":flag-cz:",
        "da": ":flag-dk:",
        "el": ":flag-gr:",
        "et": ":flag-ee:",
        "fi": ":flag-fi:",
        "hu": ":flag-hu:",
        "id": ":flag-id:",
        "lt": ":flag-lt:",
        "ro": ":flag-ro:",
        "sk": ":flag-sk:",
        "sl": ":flag-si:",
        "sv": ":flag-se:",
        "tr": ":flag-tr:",
        "uk": ":flag-ua:",
    ]

    public static let langToName: [String: String] = [
        "en": "English",
        "ja": "Japanese",
        "zh": "Chinese",
        "ko": "Korean",
        "de": "German",
        "fr": "French",
        "it": "Italian",
        "es": "Spanish",
        "nl": "Dutch",
        "pl": "Polish",
        "pt": "Portuguese",
        "ru": "Russian",
        "bg": "Bulgarian",
        "cs": "Czech",
        "da": "Danish",
        "el": "Greek",
        "et": "Estonian",
        "fi": "Finnish",
        "hu": "Hungarian",
        "id": "Indonesian",
        "lt": "Lithuanian",
        "ro": "Romanian",
        "sk": "Slovak",
        "sl": "Slovenian",
        "sv": "Swedish",
        "tr": "Turkish",
        "uk": "Ukrainian",
    ]

    // Maps country codes and reaction names to language codes
    public static let reactionToLang: [String: String] = [
        // Direct language mappings
        "jp": "ja",
        "fr": "fr",
        "de": "de",
        "it": "it",
        "es": "es",
        "nl": "nl",
        "pl": "pl",
        "pt": "pt",
        "ru": "ru",
        "bg": "bg",
        "cz": "cs",
        "dk": "da",
        "gr": "el",
        "ee": "et",
        "fi": "fi",
        "hu": "hu",
        "id": "id",
        "lt": "lt",
        "ro": "ro",
        "sk": "sk",
        "si": "sl",
        "se": "sv",
        "tr": "tr",
        "ua": "uk",

        // Country code mappings
        "us": "en",
        "gb": "en",
        "ca": "en",
        "au": "en",
        "nz": "en",
        "cn": "zh",
        "kr": "ko",
        "at": "de",
        "ch": "de",
        "be": "nl",
        "ar": "es",
        "mx": "es",
        "co": "es",
        "cl": "es",
        "pe": "es",
        "ve": "es",
        "ec": "es",
        "gt": "es",
        "cu": "es",
        "bo": "es",
        "do": "es",
        "hn": "es",
        "py": "es",
        "sv": "es",
        "ni": "es",
        "cr": "es",
        "pa": "es",
        "uy": "es",
        "pr": "es",
        "br": "pt",
        "ao": "pt",
        "mz": "pt",
        "gw": "pt",
        "cv": "pt",
        "st": "pt",
        "mc": "fr",
        "lu": "fr",
        "sn": "fr",
        "ci": "fr",
        "ml": "fr",
        "bf": "fr",
        "ne": "fr",
        "tg": "fr",
        "bj": "fr",
        "mg": "fr",
        "cm": "fr",
        "ga": "fr",
        "gn": "fr",
        "cg": "fr",
        "cd": "fr",
        "bi": "fr",
        "dj": "fr",
        "cf": "fr",
        "td": "fr",
        "km": "fr",
        "ht": "fr",
        "gf": "fr",
        "pf": "fr",
        "nc": "fr",
        "bl": "fr",
        "mf": "fr",
        "pm": "fr",
        "wf": "fr",
        "tf": "fr",
        "yt": "fr",
        "gp": "fr",
        "mq": "fr",
        "re": "fr",
        "sm": "it",
        "va": "it",
        "li": "de",
    ]

    public static func languageFromReaction(_ reaction: String) -> String? {
        // Handle flag-XX format
        if reaction.hasPrefix("flag-") {
            let countryCode = String(reaction.dropFirst(5))
            return reactionToLang[countryCode]
        }

        // Handle :flag-XX: format
        if reaction.hasPrefix(":flag-") && reaction.hasSuffix(":") {
            let countryCode = String(reaction.dropFirst(6).dropLast(1))
            return reactionToLang[countryCode]
        }

        // Handle :XX: format (emoji shortcode)
        if reaction.hasPrefix(":") && reaction.hasSuffix(":") {
            let countryCode = String(reaction.dropFirst(1).dropLast(1))
            return reactionToLang[countryCode]
        }

        // Direct reaction name or country code
        return reactionToLang[reaction]
    }

    public static func getOrderedLanguages(from env: String?) -> [String] {
        let defaultOrder = "en,ja,zh,de,fr,it,es,nl,pl,pt,ru,bg,cs,da,el,et,fi,hu,id,lt,ro,sk,sl,sv,tr,uk"
        let order = env ?? defaultOrder
        return order.split(separator: ",").map(String.init).filter { langToReaction[$0] != nil }
    }
}
