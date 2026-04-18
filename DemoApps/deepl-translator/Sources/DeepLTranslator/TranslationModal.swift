import Foundation
import SlackBlockKitDSL
import SlackKit
import SlackModels

public enum TranslationModal {
    public static func buildNewModal(defaultLang: String, languages: [String]) -> View {
        struct NewModal: SlackModalView {
            let defaultLang: String
            let languages: [String]

            var callbackId: String { "run-translation" }
            var title: TextObject { "DeepL API Runner :books:" }
            var submit: TextObject? { "Translate" }

            var blocks: [Block] {
                Block.input(InputBlock(
                    label: TextObject(type: .plainText, text: "Text"),
                    element: PlainTextInput()
                        .actionId("a")
                        .multiline(true)
                        .placeholder(Text("Put the text to translate"))
                        .asInputElement(),
                    blockId: "text",
                ))

                Block.input(InputBlock(
                    label: TextObject(type: .plainText, text: "Language"),
                    element: createLanguageSelect(options: languageOptions),
                    blockId: "lang",
                ))
            }

            private var languageOptions: [Option] {
                languages.compactMap { lang in
                    guard let reaction = Languages.langToReaction[lang],
                          let name = Languages.langToName[lang] else { return nil }
                    return Option("\(reaction) \(name)").value(lang)
                }
            }

            private var initialLanguageOption: Option {
                languageOptions.first { $0.render().value == defaultLang } ?? Option("English").value("en")
            }

            private func createLanguageSelect(options: [Option]) -> InputElementType {
                StaticSelect {
                    for option in options {
                        option
                    }
                }
                .actionId("a")
                .placeholder(Text("Select language"))
                .initialOption(initialLanguageOption)
                .asInputElement()
            }
        }

        let view = NewModal(defaultLang: defaultLang, languages: languages).render()
        switch view {
        case let .modal(modalView):
            return .modal(modalView)
        case .homeTab:
            fatalError("Expected modal view")
        }
    }

    public static func buildLoadingView() -> View {
        struct LoadingView: SlackModalView {
            var callbackId: String { "run-translation" }
            var title: TextObject { "DeepL API Runner :books:" }
            var close: TextObject? { "Close" }
            var submit: TextObject? { nil }

            var blocks: [Block] {
                Section {
                    Text(":hourglass_flowing_sand: Translating...")
                }
            }
        }

        let view = LoadingView().render()
        switch view {
        case let .modal(modalView):
            return .modal(modalView)
        case .homeTab:
            fatalError("Expected modal view")
        }
    }

    public static func buildResultView(lang: String, originalText: String, translatedText: String) -> View {
        struct ResultView: SlackModalView {
            let lang: String
            let originalText: String
            let translatedText: String

            var title: TextObject { "DeepL API Runner :books:" }
            var close: TextObject? { "Close" }
            var submit: TextObject? { nil }

            var blocks: [Block] {
                Section {
                    Text("*Original:*\n\(originalText)")
                        .type(.mrkdwn)
                }

                Section {
                    Text("*Translated (\(Languages.langToName[lang] ?? lang)):*\n\(translatedText)")
                        .type(.mrkdwn)
                }
            }
        }

        let view = ResultView(lang: lang, originalText: originalText, translatedText: translatedText).render()
        switch view {
        case let .modal(modalView):
            return .modal(modalView)
        case .homeTab:
            fatalError("Expected modal view")
        }
    }
}
