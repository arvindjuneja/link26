import Foundation

/// The resource bundle holding the GENERATED golden fixtures. Test-only: no app
/// target depends on it, so the ~210 KB never ships (D23).
public enum SentryFixtures {
  public static let bundle = Bundle.module
}
