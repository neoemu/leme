import SwiftkubeModel

extension core.v1.Event {
    /// Unlike most resources, `core.v1.Event.metadata` is a NON-optional
    /// stored property, so it cannot witness `MetadataHavingResource`'s
    /// optional `metadata` requirement. The familiar `event.metadata?.name`
    /// form then silently resolves to the protocol extension default — which
    /// always returns nil — yielding empty names/namespaces for every event.
    /// Always go through this accessor instead.
    var objectMeta: meta.v1.ObjectMeta { metadata }
}
