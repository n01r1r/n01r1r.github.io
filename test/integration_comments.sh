#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"

tmp_dir="$(mktemp -d)"
tmp_source="${tmp_dir}/source"
tmp_override="${tmp_dir}/comments-test-override.yml"
tmp_site="${tmp_dir}/site"
tmp_log="${tmp_dir}/build.log"

cleanup() {
  rm -rf -- "${tmp_dir}"
}
trap cleanup EXIT

# Build a disposable copy so test posts cannot reach the production source.
# Keep Bundler in the original checkout, where CI installed the dependencies.
mkdir -p "${tmp_source}"
tar -C "${repo_root}" \
  --exclude='./.git' --exclude='./.bundle' \
  --exclude='./vendor' --exclude='./node_modules' --exclude='./_site' \
  --exclude='./.jekyll-cache' --exclude='./.jekyll-metadata' \
  -cf - . | tar -C "${tmp_source}" -xf -

mkdir -p "${tmp_source}/_posts"
cat >"${tmp_source}/_posts/2000-01-01-ci-giscus-comments.md" <<'MARKDOWN'
---
layout: post
title: CI Giscus comments fixture
permalink: /__ci__/comments/giscus/
published: true
giscus_comments: true
disqus_comments: false
---
Giscus rendering fixture.
MARKDOWN

cat >"${tmp_source}/_posts/2000-01-02-ci-disqus-comments.md" <<'MARKDOWN'
---
layout: post
title: CI Disqus comments fixture
permalink: /__ci__/comments/disqus/
published: true
giscus_comments: false
disqus_comments: true
---
Disqus rendering fixture.
MARKDOWN

# Placeholder values only test HTML generation, not the live services.
cat >"${tmp_override}" <<'YAML'
giscus:
  repo: alshedivat/al-folio
  repo_id: R_kgDOExample
  category: Comments
  category_id: DIC_kwDOExample
disqus_shortname: ci-comments
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

giscus_page="${tmp_site}/__ci__/comments/giscus/index.html"
disqus_page="${tmp_site}/__ci__/comments/disqus/index.html"

for page in "${giscus_page}" "${disqus_page}"; do
  if [ ! -r "${page}" ]; then
    echo "expected readable comments fixture at ${page}" >&2
    cat "${tmp_log}" >&2
    exit 1
  fi
done

assert_contains() {
  if ! grep -Fq -- "$1" "$2"; then
    echo "expected '$1' in $2" >&2
    cat "${tmp_log}" >&2
    exit 1
  fi
}

assert_contains 'https://giscus.app/client.js' "${giscus_page}"
if grep -Fq -- 'giscus comments misconfigured' "${giscus_page}"; then
  echo "unexpected giscus misconfiguration warning in ${giscus_page}" >&2
  exit 1
fi

assert_contains 'id="disqus_thread"' "${disqus_page}"
assert_contains '.disqus.com/embed.js' "${disqus_page}"

echo "comments integration checks passed"
