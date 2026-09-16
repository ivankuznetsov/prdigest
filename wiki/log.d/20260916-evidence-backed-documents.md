# Evidence-backed documents

PRDigest facts now carry bounded pull-request descriptions and file patches
with explicit truncation and omission metadata. `Prdigest::Document` provides
the shared provider-free prose prompt and generator interface used by the
standalone runner and embedders. Prompt construction caps total evidence by
trimming patches first and refuses metadata that cannot fit.

Real fleet validation also found a renamed repository whose old search qualifier
was rejected. Resolve canonical repository names before searching and deduplicate
aliases; the package smoke stub now supplies the evidence endpoints too.
