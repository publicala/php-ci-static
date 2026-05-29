#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workspace="$(mktemp -d "${TMPDIR:-/tmp}/php-ci-static-shellcheck.XXXXXX")"

cleanup() {
  rm -rf "$workspace"
}

trap cleanup EXIT

ruby --disable=gems -ryaml -e '
  out = ARGV.shift

  ARGV.each do |path|
    action = YAML.load_file(path)
    action.fetch("runs").fetch("steps").each_with_index do |step, index|
      next unless step["run"]

      action_name = path
        .sub(%r{\A.*/php-ci-static/?}, "")
        .sub(%r{/action\.yml\z}, "")
        .sub(%r{\Aaction\.yml\z}, "root")
        .gsub(/[^a-zA-Z0-9]+/, "-")
        .gsub(/^-|-$/, "")

      step_name = step.fetch("name", "step-#{index + 1}")
        .downcase
        .gsub(/[^a-z0-9]+/, "-")
        .gsub(/^-|-$/, "")

      File.write(
        File.join(out, "#{action_name}-#{format("%02d", index + 1)}-#{step_name}.bash"),
        "#!/usr/bin/env bash\n# shellcheck disable=SC2016\n#{step.fetch("run")}\n",
      )
    end
  end
' "$workspace" "$root/action.yml" "$root/setup-php-vendor/action.yml"

shellcheck "$workspace"/*.bash
