// Turns the GitHub `production` environment into what `wrangler deploy` needs, and refuses to deploy a
// half-configured API. Run by .github/workflows/deploy-api.yml; see apps/api/README.md, "Deploying".
//
//   node scripts/production-config.mjs <secrets-file> <vars-file>
//
// Writes the Worker's secrets as JSON to <secrets-file> (for `--secrets-file`) and its plain settings to
// <vars-file>, one `NAME:value` per line (for `--var`). Nothing is printed but names.

import { writeFileSync } from "node:fs";

/** Always needed. */
const required = {
  secrets: ["DATABASE_URL", "BETTER_AUTH_SECRET"],
  vars: ["BETTER_AUTH_URL"],
};

/** Each group is all or nothing, so a provider is never half set up. */
const groups = [
  { name: "R2", secrets: ["R2_ACCESS_KEY_ID", "R2_SECRET_ACCESS_KEY"], vars: ["R2_BUCKET", "R2_ACCOUNT_ID"] },
  { name: "Resend", secrets: ["RESEND_API_KEY"], vars: ["EMAIL_FROM"] },
];

/**
 * Works out the Worker's secrets and vars from the environment.
 * @param {Record<string, string | undefined>} env
 * @returns {{ secrets: Record<string, string>, vars: Record<string, string>, problems: string[], skipped: string[] }}
 */
export function productionConfig(env) {
  const value = (name) => {
    const v = env[name]?.trim();
    return v ? v : undefined;
  };
  const secrets = {};
  const vars = {};
  const problems = [];
  const skipped = [];

  for (const name of required.secrets) {
    if (value(name)) secrets[name] = value(name);
    else problems.push(`${name} is not set`);
  }
  for (const name of required.vars) {
    if (value(name)) vars[name] = value(name);
    else problems.push(`${name} is not set`);
  }

  for (const group of groups) {
    const names = [...group.secrets, ...group.vars];
    const missing = names.filter((name) => !value(name));
    if (missing.length === names.length) {
      skipped.push(group.name);
      continue;
    }
    if (missing.length > 0) {
      problems.push(`${group.name} is half set up: ${missing.join(", ")} missing`);
      continue;
    }
    for (const name of group.secrets) secrets[name] = value(name);
    for (const name of group.vars) vars[name] = value(name);
  }

  const url = vars.BETTER_AUTH_URL;
  if (url && !/^https:\/\/[^/]+$/.test(url)) {
    problems.push("BETTER_AUTH_URL must be https://host with no path or trailing slash");
  }
  if (secrets.DATABASE_URL && !secrets.DATABASE_URL.includes("-pooler")) {
    problems.push("DATABASE_URL should be Neon's pooled connection string (its host contains -pooler)");
  }

  return { secrets, vars, problems, skipped };
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const [secretsFile, varsFile] = process.argv.slice(2);
  if (!secretsFile || !varsFile) {
    console.error("usage: node scripts/production-config.mjs <secrets-file> <vars-file>");
    process.exit(2);
  }
  const { secrets, vars, problems, skipped } = productionConfig(process.env);
  if (problems.length > 0) {
    for (const problem of problems) console.error(`::error::${problem}`);
    console.error("Run scripts/setup-production.sh to fill in the GitHub production environment.");
    process.exit(1);
  }
  writeFileSync(secretsFile, JSON.stringify(secrets), { mode: 0o600 });
  writeFileSync(varsFile, Object.entries(vars).map(([k, v]) => `${k}:${v}`).join("\n") + "\n");
  console.log(`Worker secrets: ${Object.keys(secrets).join(", ")}`);
  console.log(`Worker vars: ${Object.keys(vars).join(", ")}`);
  for (const name of skipped) console.log(`::warning::${name} is not set up, so the API runs without it`);
}
