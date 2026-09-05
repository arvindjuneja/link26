import Foundation

/// Named-placeholder interpolation for the handler templates (S2).
///
/// The bodies in `copy.json` are the web's message strings with their interpolated
/// runs cut out and named — `{gap} {rank} {cash} {item} {queue}`. Nothing else in
/// the app authors a sentence, so this is the one place a handler line is assembled,
/// and the five names are a closed enum: a template that grows a sixth placeholder
/// fails the content test in `CareerTests` rather than shipping a `{brace}` to a
/// player.
public enum Templating {

  /// The five runs a handler template can carry.
  ///
  /// - `gap`:   standing still owed to the next rung.
  /// - `rank`:  a rung's label.
  /// - `cash`:  the wallet, in ¢.
  /// - `item`:  a kit item's label.
  /// - `queue`: a shift's label.
  public enum Placeholder: String, Sendable, Hashable, CaseIterable {
    case gap
    case rank
    case cash
    case item
    case queue
  }

  /// Fill `template` from `params`, through `CopyPack.render`.
  ///
  /// An unfilled placeholder is a programmer error, not a content error: the
  /// template set is closed and every emitter knows what its own line needs. In
  /// DEBUG that traps and names the run; in a release build `CopyPack.render`
  /// leaves the raw `{key}` intact, which is visible in review and never a
  /// half-blank sentence.
  public static func render(
    _ template: String, _ params: [Placeholder: String], through copy: CopyPack
  ) -> String {
    let named = Dictionary(uniqueKeysWithValues: params.map { ($0.key.rawValue, $0.value) })
    #if DEBUG
      for key in placeholders(in: template) where named[key] == nil {
        fatalError("handler template leaves {\(key)} unfilled: \(template)")
      }
    #endif
    return copy.render(template, named)
  }

  /// The placeholder names `template` carries, in the order they appear.
  ///
  /// Mirrors `CopyPack.render`'s scan exactly — same single pass, same
  /// unterminated-brace bail-out — so it reports the runs that would actually be
  /// substituted and never flags a lone `{`.
  public static func placeholders(in template: String) -> [String] {
    guard template.contains("{") else { return [] }
    var found: [String] = []
    var rest = Substring(template)
    while let open = rest.firstIndex(of: "{") {
      guard let close = rest[rest.index(after: open)...].firstIndex(of: "}") else { break }
      found.append(String(rest[rest.index(after: open)..<close]))
      rest = rest[rest.index(after: close)...]
    }
    return found
  }
}
