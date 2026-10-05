import assert from "node:assert/strict";
import test from "node:test";
import { serializeJsonLd } from "./jsonLd.mjs";

test("escapes < so a value cannot close the script tag", () => {
	const output = serializeJsonLd({ name: "</script><script>alert(1)</script>" });
	assert.ok(output.includes("\\u003c/script>"));
	assert.ok(!output.includes("</script>"));
});

test("output stays valid JSON and round-trips values", () => {
	const values = { name: "PingStats</script>", nested: { a: 1 } };
	const output = serializeJsonLd(values);
	assert.deepEqual(JSON.parse(output), values);
});
