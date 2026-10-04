import Foundation
import SlackBlockKit

/// Result builder for constructing arrays of blocks
@resultBuilder
public struct BlockBuilder {
    public static func buildBlock() -> [Block] {
        []
    }

    /// Handle arrays of Block (which is what gets passed from buildExpression)
    public static func buildBlock(_ components: [Block]...) -> [Block] {
        components.flatMap(\.self)
    }

    /// Handle single BlockComponent
    public static func buildBlock(_ component: some BlockComponent) -> [Block] {
        [component.render()]
    }

    /// Handle multiple BlockComponents
    public static func buildBlock(_ first: any BlockComponent, _ rest: any BlockComponent...) -> [Block] {
        var result: [Block] = [first.render()]
        for component in rest {
            result.append(component.render())
        }
        return result
    }

    public static func buildArray(_ components: [[Block]]) -> [Block] {
        components.flatMap(\.self)
    }

    public static func buildOptional(_ component: [Block]?) -> [Block] {
        component ?? []
    }

    public static func buildEither(first component: [Block]) -> [Block] {
        component
    }

    public static func buildEither(second component: [Block]) -> [Block] {
        component
    }

    public static func buildExpression(_ expression: some BlockComponent) -> [Block] {
        [expression.render()]
    }

    public static func buildExpression(_ expression: Block) -> [Block] {
        [expression]
    }
}

/// Result builder for constructing arrays of action elements
@resultBuilder
public struct ActionElementBuilder {
    public static func buildBlock() -> [ActionElementType] {
        []
    }

    /// Handle arrays of ActionElementType (the primary method)
    public static func buildBlock(_ components: [ActionElementType]...) -> [ActionElementType] {
        components.flatMap(\.self)
    }

    public static func buildExpression(_ expression: some ActionElementConvertible) -> [ActionElementType] {
        [expression.asActionElement()]
    }

    public static func buildArray(_ components: [[ActionElementType]]) -> [ActionElementType] {
        components.flatMap(\.self)
    }

    public static func buildOptional(_ component: [ActionElementType]?) -> [ActionElementType] {
        component ?? []
    }

    public static func buildEither(first component: [ActionElementType]) -> [ActionElementType] {
        component
    }

    public static func buildEither(second component: [ActionElementType]) -> [ActionElementType] {
        component
    }
}

/// Result builder for constructing arrays of context elements
@resultBuilder
public struct ContextElementBuilder {
    public static func buildBlock() -> [ContextElementType] {
        []
    }

    /// Handle arrays of ContextElementType (from buildExpression)
    public static func buildBlock(_ components: [ContextElementType]...) -> [ContextElementType] {
        components.flatMap(\.self)
    }

    public static func buildExpression(_ expression: Text) -> [ContextElementType] {
        [.text(expression.render())]
    }

    public static func buildExpression(_ expression: ContextImage) -> [ContextElementType] {
        [expression.asContextElement()]
    }

    public static func buildArray(_ components: [[ContextElementType]]) -> [ContextElementType] {
        components.flatMap(\.self)
    }

    public static func buildOptional(_ component: [ContextElementType]?) -> [ContextElementType] {
        component ?? []
    }

    public static func buildEither(first component: [ContextElementType]) -> [ContextElementType] {
        component
    }

    public static func buildEither(second component: [ContextElementType]) -> [ContextElementType] {
        component
    }
}

/// Result builder for Text DSL components
@resultBuilder
public struct TextBuilder {
    public static func buildBlock(_ component: Text) -> Text {
        component
    }
}

/// Result builder for lists of Text components
@resultBuilder
public struct TextListBuilder {
    public static func buildBlock(_ components: [Text]...) -> [Text] {
        components.flatMap(\.self)
    }

    public static func buildExpression(_ expression: Text) -> [Text] {
        [expression]
    }

    public static func buildArray(_ components: [[Text]]) -> [Text] {
        components.flatMap(\.self)
    }

    public static func buildOptional(_ component: [Text]?) -> [Text] {
        component ?? []
    }

    public static func buildEither(first component: [Text]) -> [Text] {
        component
    }

    public static func buildEither(second component: [Text]) -> [Text] {
        component
    }
}

/// Result builder for Option components
@resultBuilder
public struct OptionBuilder {
    public static func buildBlock(_ components: [Option]...) -> [Option] {
        components.flatMap(\.self)
    }

    public static func buildExpression(_ expression: Option) -> [Option] {
        [expression]
    }

    public static func buildArray(_ components: [[Option]]) -> [Option] {
        components.flatMap(\.self)
    }

    public static func buildOptional(_ component: [Option]?) -> [Option] {
        component ?? []
    }

    public static func buildEither(first component: [Option]) -> [Option] {
        component
    }

    public static func buildEither(second component: [Option]) -> [Option] {
        component
    }
}

/// Result builder for OptionGroup components
@resultBuilder
public struct OptionGroupBuilder {
    public static func buildBlock(_ components: [OptionGroup]...) -> [OptionGroup] {
        components.flatMap(\.self)
    }

    public static func buildExpression(_ expression: OptionGroup) -> [OptionGroup] {
        [expression]
    }

    public static func buildArray(_ components: [[OptionGroup]]) -> [OptionGroup] {
        components.flatMap(\.self)
    }

    public static func buildOptional(_ component: [OptionGroup]?) -> [OptionGroup] {
        component ?? []
    }

    public static func buildEither(first component: [OptionGroup]) -> [OptionGroup] {
        component
    }

    public static func buildEither(second component: [OptionGroup]) -> [OptionGroup] {
        component
    }
}

/// Result builder for input elements
@resultBuilder
public struct InputElementBuilder {
    public static func buildBlock<T: InputElementConvertible>(_ component: T) -> T {
        component
    }
}

/// Result builder for markdown content
@resultBuilder
public struct MarkdownBuilder {
    public static func buildBlock(_ components: String...) -> String {
        components.joined(separator: "\n")
    }

    public static func buildExpression(_ expression: String) -> String {
        expression
    }

    public static func buildArray(_ components: [String]) -> String {
        components.joined(separator: "\n")
    }

    public static func buildOptional(_ component: String?) -> String {
        component ?? ""
    }

    public static func buildEither(first component: String) -> String {
        component
    }

    public static func buildEither(second component: String) -> String {
        component
    }
}
