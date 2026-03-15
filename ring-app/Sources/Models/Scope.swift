import Foundation

/// Combines a scope definition with its activation state for a specific provider.
struct ScopeStatus: Identifiable {
    let definition: ScopeDefinition
    let isActive: Bool

    var id: String { definition.id }
    var label: String { definition.label }
    var oauthScope: String { definition.oauthScope }
}

extension Provider {
    /// Returns all available scopes annotated with whether they are currently active.
    func scopeStatuses(activeScopes: [String]) -> [ScopeStatus] {
        let activeSet = Set(activeScopes)
        return availableScopes.map { def in
            let isActive = activeSet.contains(def.id) || activeSet.contains(def.oauthScope)
            return ScopeStatus(definition: def, isActive: isActive)
        }
    }
}
