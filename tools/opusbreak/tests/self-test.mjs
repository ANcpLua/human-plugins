import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const output = execFileSync(join(root, "bin", "opusbreak"), ["self-test"], {
  encoding: "utf8",
});
if (!output.includes("self-test: ok")) throw new Error("self-test output missing");
