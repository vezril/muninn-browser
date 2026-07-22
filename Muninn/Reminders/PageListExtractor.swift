import Foundation

/// Structured extraction of list-like content from a page, for "Create Reminders List from Page".
/// The deterministic path reads schema.org `Recipe` JSON-LD (`recipeIngredient` / `recipeInstructions`);
/// if there's no recipe data, the caller falls back to the local model.
enum PageListExtractor {
    /// JS returning JSON: `{ title, recipeName?, ingredients:[String], steps:[String] }`.
    static let script = #"""
    (function () {
      var result = { title: document.title || "", ingredients: [], steps: [] };
      function pushText(arr, v) {
        if (typeof v === "string") { var s = v.trim(); if (s) arr.push(s); }
      }
      function collect(node) {
        if (!node) return;
        if (Array.isArray(node)) { node.forEach(collect); return; }
        if (typeof node !== "object") return;
        var t = node["@type"];
        var types = Array.isArray(t) ? t : [t];
        if (types.indexOf("Recipe") >= 0) {
          if (node.name && !result.recipeName) result.recipeName = String(node.name).trim();
          var ing = node.recipeIngredient || node.ingredients;
          if (Array.isArray(ing)) ing.forEach(function (x) { pushText(result.ingredients, x); });
          else pushText(result.ingredients, ing);
          var ins = node.recipeInstructions;
          (function walkIns(v) {
            if (!v) return;
            if (typeof v === "string") { pushText(result.steps, v); return; }
            if (Array.isArray(v)) { v.forEach(walkIns); return; }
            if (typeof v === "object") {
              if (v.text) pushText(result.steps, v.text);
              else if (v.name) pushText(result.steps, v.name);
              if (Array.isArray(v.itemListElement)) v.itemListElement.forEach(walkIns);
            }
          })(ins);
        }
        if (node["@graph"]) collect(node["@graph"]);
      }
      var scripts = document.querySelectorAll('script[type="application/ld+json"]');
      for (var i = 0; i < scripts.length; i++) {
        try { collect(JSON.parse(scripts[i].textContent)); } catch (e) {}
      }
      // de-dupe while preserving order
      function uniq(a) { var seen = {}, out = []; a.forEach(function (x) { if (!seen[x]) { seen[x] = 1; out.push(x); } }); return out; }
      result.ingredients = uniq(result.ingredients);
      result.steps = uniq(result.steps);
      return JSON.stringify(result);
    })()
    """#

    /// Decoded shape of `script`'s output.
    struct Recipe: Decodable {
        let title: String
        let recipeName: String?
        let ingredients: [String]
        let steps: [String]

        var listName: String { (recipeName?.isEmpty == false ? recipeName! : title) }
        var hasStructuredData: Bool { !ingredients.isEmpty || !steps.isEmpty }
    }

    static func decode(_ json: String) -> Recipe? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(Recipe.self, from: data)
    }

    /// A `{name, items}` list produced by the local-model fallback. Tolerates ```json fences.
    struct ModelList: Decodable { let name: String; let items: [String] }

    static func decodeModelList(_ raw: String) -> ModelList? {
        // Isolate the JSON object even if the model wraps it in prose or ```json fences.
        guard let open = raw.firstIndex(of: "{"), let close = raw.lastIndex(of: "}"), open < close
        else { return nil }
        let s = String(raw[open...close])
        guard let data = s.data(using: .utf8),
              let list = try? JSONDecoder().decode(ModelList.self, from: data),
              !list.items.isEmpty else { return nil }
        return list
    }
}
