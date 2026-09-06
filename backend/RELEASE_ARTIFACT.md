# Reproducible backend release artifact

`cmd/releasepack` is the canonical build and packaging specification for the
backend production artifact. It builds only these Linux runtime commands:

- `api`
- `migrator`
- `worker_ai`
- `worker_jobs`
- `worker_whatsapp`

The tool requires an exact, clean source commit and Go 1.24.0 with
`GOTOOLCHAIN=local`. Every binary is built for `linux/amd64` with
`GOAMD64=v1`, CGO disabled, and these flags:

```text
-mod=readonly -trimpath -buildvcs=true -ldflags=-buildid=
```

The empty Go build ID is intentional. Go action IDs can depend on the absolute
source path even with `-trimpath`; removing only that ID makes builds from
different paths byte-identical while retaining Go build info and the required
VCS revision, time, and clean/dirty status.

Build output and `GOCACHE` must be outside the source worktree. The tool rejects
a dirty source, a different commit or source branch ref, another Go patch
version, an incorrect migration sequence, and missing or dirty VCS build info.
It does not read provider configuration or credentials.

## Reproducibility proof

Create two standalone checkouts at the same source SHA, then invoke the same
tool twice with different output and `GOCACHE` directories. Linked Git
worktrees are unsuitable for this proof because Go may omit VCS build info when
`.git` is a worktree pointer file (golang/go#58218). The release tooling may live
on a later release-engineering commit; `--source-root` identifies the stable
source commit whose VCS revision must be embedded in the binaries.

```text
go run ./cmd/releasepack build \
  --source-root <detached-source-a> \
  --output-root <external-build-a> \
  --gocache <external-cache-a> \
  --expected-sha <full-40-character-sha> \
  --source-branch <origin-branch>

go run ./cmd/releasepack build \
  --source-root <detached-source-b> \
  --output-root <external-build-b> \
  --gocache <external-cache-b> \
  --expected-sha <full-40-character-sha> \
  --source-branch <origin-branch>

go run ./cmd/releasepack compare \
  --build-a <external-build-a> \
  --build-b <external-build-b>
```

Use an explicit `--go <command>` when the exact Go binary is not named `go`.
The GitHub Actions workflow uses this same command and is the authoritative
Ubuntu proof.

Each build produces the deterministic archive, an adjacent copy of
`RELEASE_MANIFEST.json`, and `ARTIFACT_SHA256.txt`. The manifest describes the
archive contents but intentionally does not include the archive's own hash;
that non-recursive hash is stored in `ARTIFACT_SHA256.txt`.

Migration contents are read from the commit's Git blobs rather than the checked
out files. This prevents `core.autocrlf` or another checkout policy from changing
their packaged bytes across operating systems.

The canonical package contains exactly eleven ordered migrations, `0001` through
`0011`. Migration `0011` validates existing assistant message content and enforces
that every assistant message has the same student owner as its session. It does
not add a default for `assistant_messages.content`: the active repository writes
both `text_content` and `content`, while an unknown direct SQL writer from before
`0009` is not a supported runtime contract. Such a writer must be updated before
using this schema; this is a known direct-writer compatibility limitation, not a
rollback blocker for the verified rollback runtime.
