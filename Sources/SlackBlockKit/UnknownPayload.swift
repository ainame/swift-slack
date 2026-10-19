import OpenAPIRuntime

extension OpenAPIObjectContainer {
    /// Rebuilds the object stored by an `unknown(type:payload:)` case, merging the `type` back in
    /// so the payload round-trips unchanged.
    static func unknown(type: String, payload: OpenAPIObjectContainer) throws -> OpenAPIObjectContainer {
        var value = payload.value
        value["type"] = type
        return try OpenAPIObjectContainer(unvalidatedValue: value)
    }

    /// The `type` and block id (`block_id`) of an unknown payload, when present.
    func string(forKey key: String) -> String? {
        value[key] as? String
    }
}
