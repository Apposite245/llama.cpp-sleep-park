# llama.cpp sleep-park

A patch for [llama.cpp](https://github.com/ggml-org/llama.cpp) `llama-server` that lets a sleeping model
keep its weights in pinned RAM instead of freeing them. The GPU memory is released just the same, but
waking copies the weights back over PCIe instead of loading the GGUF file again.

It is made for a GPU shared between an LLM and something else (for example ComfyUI generating video):
the LLM must give back its VRAM between requests, but reloading it every time costs seconds.

Patch against llama.cpp **b11946** (commit `8ca4060`). Not submitted upstream. A daily GitHub Actions job
applies it to the newest llama.cpp release and publishes a build (see [Release binaries](#release-binaries)).

## Measured

RTX 5090, Windows 11, llama-server in router mode, `--sleep-idle-seconds 1 --sleep-park-keep-ram`.

| | Fresh load | Wake from park |
|---|---|---|
| Qwen3.8-27B Q6_K (20.9 GiB on the GPU), weights | 8–9 s with the projector | 1.1 s |
| its vision projector (mmproj F16) | ~0.7 s | 0.05 s |
| MiniCPM-V 4.7 35B-A3B Q5_K_M, ready to generate | 8.7 s median (6.3–14.9) | 1.2–1.8 s |

Going to sleep takes 0.8 s with `--sleep-park-keep-ram` (only a copy), 3–5 s without it (the pinned
memory is allocated each time). Outputs are identical before and after a park.

## Usage

```
llama-server -m model.gguf --sleep-idle-seconds 1 --sleep-park
```

| Flag | |
|---|---|
| `--sleep-park` | When the server sleeps (`--sleep-idle-seconds`), park the weights in pinned RAM instead of freeing them. The RAM is locked only while asleep. |
| `--sleep-park-keep-ram` | Implies `--sleep-park`, and keeps the pinned RAM while awake too, so the next park is only a copy. The RAM (the size of the model's GPU weights) stays locked as long as the server runs. |

In router mode put them in the model's preset (`sleep-idle-seconds = 1`, `sleep-park-keep-ram = 1`); the
router then reports the model as `sleeping` while it is parked, and a request to it wakes it.
`LLAMA_PARK_CHUNK_MB` sets the size of the pinned chunks (default 256).

[LLM Switchboard](https://github.com/Apposite245/llm-switchboard) has both as per-model settings
("Sleep after idle" and "On sleep").

## How it works

- `llama_model::park()` copies every device weight buffer into pinned host memory in 256 MiB chunks and
  frees the buffer; `unpark()` allocates it again, copies the chunks back and re-points the tensors.
  Chunks matter on Windows: one 20 GB copy ran at 7 GB/s, chunked copies at ~22 GB/s. Without
  keep-RAM the chunks are unpinned on a background thread with short gaps, because one 20 GB
  `cudaFreeHost` stalled other GPU work for over a second.
- A park cache in libllama: with it on, `llama_model_free` parks a model loaded from a file instead of
  deleting it, and the next `llama_model_load_from_file` of the same file and placement returns it.
  A parked copy of the same file with other settings is dropped.
- `--fit` (on by default) would probe free memory again on every wake and could pick another layout, so
  the fitted parameters of the first load are reused while a parked copy exists.
- The server parks the multimodal projector the same way (`clip_park` / `mtmd_park`) and reuses it only
  when the text model it points to was woken rather than reloaded.

New public API: `llama_model_park`, `llama_model_unpark`, `llama_model_park_cache_set`,
`llama_model_park_cache_has`, `llama_model_is_woken`, `mtmd_park`, `mtmd_unpark`.

## Limits

- Tested with CUDA on one GPU, on Windows. The code goes through the ggml backend API, but other
  backends and multi-GPU splits are untested.
- Pinned RAM is locked: other programs cannot use it while it is held.
- A model loaded from split GGUF files (`llama_model_load_from_splits`) is not parked; it is freed as before.
- The reused fit points into the server's own parameters, which live as long as the server.

## Building

```
git clone https://github.com/ggml-org/llama.cpp
cd llama.cpp
git checkout b11946
git -c core.autocrlf=false apply --3way ..\sleep-park.patch
```

Then build as usual with CUDA, or use `build-windows.cmd` (edit the paths at the top first).
On Windows with `core.autocrlf=true`, clone with `-c core.autocrlf=false`, or the patch will not apply.

## Release binaries

Each release is a Windows build of `llama-server` (**RTX 50-series / sm_120 only**) with the CUDA runtime
DLLs it needs. Other GPUs need a build from source.

`.github/workflows/build.yml` checks once a day for a new llama.cpp release. It applies the patch with
`git apply --3way`, builds with CUDA 13.4 and publishes the result as `<tag>-park1`. These builds are
compiled but not tested on a GPU. When the patch no longer applies or the build fails, the job opens an
issue labelled `auto-build` (or comments on the open one) and no release is made until the patch is
rebased. It can also be run by hand from the Actions tab, optionally for a specific tag.

`b11701-park1` was built by hand with CUDA 13.0.

## License

MIT, like llama.cpp (see `LICENSE-llama.cpp`).
