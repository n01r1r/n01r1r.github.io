#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"

tmp_dir="$(mktemp -d)"
tmp_source="${tmp_dir}/source"
tmp_override="${tmp_dir}/distill-override.yml"
tmp_site="${tmp_dir}/site"
tmp_log="${tmp_dir}/build.log"

cleanup() {
  rm -rf -- "${tmp_dir}"
}
trap cleanup EXIT

# Build a disposable copy so the integration fixture never becomes a public post.
mkdir -p "${tmp_source}"
tar -C "${repo_root}" \
  --exclude='./.git' --exclude='./.bundle' \
  --exclude='./vendor' --exclude='./node_modules' --exclude='./_site' \
  --exclude='./.jekyll-cache' --exclude='./.jekyll-metadata' \
  -cf - . | tar -C "${tmp_source}" -xf -

mkdir -p "${tmp_source}/_posts"
cat >"${tmp_source}/_posts/2000-01-03-ci-distill.md" <<'MARKDOWN'
---
layout: distill
title: CI Distill fixture
permalink: /__ci__/distill/
published: true
giscus_comments: true
mermaid:
  enabled: true
tikzjax: true
authors:
  - name: CI Fixture
---

## Fixture

This page exercises the Distill layout and its gated assets.
MARKDOWN

cat >"${tmp_override}" <<'YAML'
al_folio:
  features:
    distill:
      enabled: true
giscus:
  repo: alshedivat/al-folio
  repo_id: R_kgDOExample
  category: Comments
  category_id: DIC_kwDOExample
YAML

if BUNDLE_GEMFILE="${repo_root}/Gemfile" bundle exec jekyll build \
  --source "${tmp_source}" \
  --config "${repo_root}/_config.yml,${tmp_override}" \
  -d "${tmp_site}" >"${tmp_log}" 2>&1; then
  :
else
  status=$?
  cat "${tmp_log}" >&2
  exit "${status}"
fi

distill_page="${tmp_site}/__ci__/distill/index.html"

if [ ! -r "${distill_page}" ]; then
  echo "expected readable Distill fixture at ${distill_page}" >&2
  cat "${tmp_log}" >&2
  exit 1
fi

assert_contains() {
  if ! grep -Fq -- "$1" "$2"; then
    echo "expected '$1' in $2" >&2
    cat "${tmp_log}" >&2
    exit 1
  fi
}

assert_contains 'd-front-matter' "${distill_page}"
assert_contains '/assets/js/distillpub/template.v2.js' "${distill_page}"
assert_contains '/assets/js/distillpub/transforms.v2.js' "${distill_page}"
assert_contains '/assets/js/distillpub/overrides.js' "${distill_page}"
assert_contains '/assets/al_charts/js/mermaid-setup.js' "${distill_page}"
assert_contains 'https://cdn.jsdelivr.net/npm/@planktimerr/tikzjax@1.0.8/dist/fonts.css' "${distill_page}"
assert_contains 'https://cdn.jsdelivr.net/npm/@planktimerr/tikzjax@1.0.8/dist/tikzjax.js' "${distill_page}"
assert_contains 'id="giscus_thread"' "${distill_page}"

transforms_runtime="${tmp_site}/assets/js/distillpub/transforms.v2.js"
distill_runtime="$(PATH="$HOME/.rbenv/shims:$PATH" BUNDLE_GEMFILE="${repo_root}/Gemfile" bundle exec ruby -e 'spec = Gem.loaded_specs["al_folio_distill"]; puts(spec ? File.join(spec.full_gem_path, "assets/js/distillpub/transforms.v2.js") : "")')"
if [ -f "${distill_runtime}" ]; then
  # Prefer the packaged gem runtime for deterministic parity checks.
  transforms_runtime="${distill_runtime}"
elif [ ! -f "${transforms_runtime}" ]; then
  echo "distill transforms runtime missing at ${transforms_runtime} (and not found in installed al_folio_distill gem)" >&2
  exit 1
fi

expected_transforms_hash="5d85590f5652b910ab2411019749c83ef5a5a3fbb9b739adc92b4557b6bf3d39"
actual_transforms_hash="$(ruby -rdigest -e 'print Digest::SHA256.file(ARGV[0]).hexdigest' "${transforms_runtime}")"
if [ "${actual_transforms_hash}" != "${expected_transforms_hash}" ]; then
  echo "unexpected distill transforms runtime hash: ${actual_transforms_hash}" >&2
  exit 1
fi

echo "distill integration checks passed"
