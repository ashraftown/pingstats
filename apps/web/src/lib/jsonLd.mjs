// Serializes JSON-LD payloads for embedding in a <script type="application/ld+json">
// tag. Escapes "<" as \u003c so a value containing "</script>" can never close the
// script tag early. See BaseLayout.astro for the data source.

/**
 * @param {Record<string, unknown>} values JSON-safe payload.
 * @returns {string} JSON text safe to pass to set:html in a JSON-LD script tag.
 */
export function serializeJsonLd(values) {
	return JSON.stringify(values).replace(/</g, "\\u003c");
}
