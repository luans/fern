import Foundation

/// Experimentos da Fase 5. Cada um mora na sua pasta em `Experiments/`, tem uma chave
/// liga/desliga em Ajustes › Experimentos e não altera o núcleo (`Core/`, `Web/`).
/// Para adicionar um: crie o caso aqui, a pasta do módulo e use `isEnabled` (ou
/// `@AppStorage(experiment.storageKey)`) onde ele aparece na interface.
enum Experiment: String, CaseIterable, Identifiable, Sendable {
    case systemMonitor

    var id: String { rawValue }

    var storageKey: String { "experiment.\(rawValue)" }

    var isEnabledByDefault: Bool {
        switch self {
        case .systemMonitor: true
        }
    }

    var isEnabled: Bool {
        UserDefaults.standard.object(forKey: storageKey) as? Bool ?? isEnabledByDefault
    }

    var title: LocalizedStringResource {
        switch self {
        case .systemMonitor: "System monitor"
        }
    }

    var summary: LocalizedStringResource {
        switch self {
        case .systemMonitor:
            "Shows the Mac's CPU, memory and thermal state at the bottom of the sidebar."
        }
    }
}
