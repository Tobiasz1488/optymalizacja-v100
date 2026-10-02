# llama.cpp dla NVIDIA Tesla V100 32GB

Kopia [llama.cpp](https://github.com/ggml-org/llama.cpp) (wersja w pliku
[`LLAMA_CPP_VERSION`](LLAMA_CPP_VERSION)) z konfiguracją budowania i skryptami
dostrojonymi pod **Tesla V100 32GB (Volta, sm_70)** na **Ubuntu 24.04 LTS** i **Windows 11**.

```
llama.cpp/            niezmieniona kopia źródeł upstream
cmake/v100.cmake      wspólna konfiguracja CMake pod V100 (Linux i Windows)
scripts/
  setup-ubuntu.sh     instalacja narzędzi, CUDA 12.9 (+ opcjonalnie sterownika 580)
  build-ubuntu.sh     budowanie na Ubuntu
  build-windows.ps1   budowanie na Windows 11 (build-windows.bat = to samo z dwukliku)
  run-server.sh/.ps1  llama-server z ustawieniami pod V100 32GB
  bench.sh/.ps1       szybki benchmark (llama-bench)
  update-llama.sh     podmiana kopii llama.cpp na nowszy tag upstream
models/               tu wrzucasz pliki .gguf (ignorowane przez git)
```

## Co jest zoptymalizowane

| Ustawienie | Wartość | Dlaczego |
|---|---|---|
| `CMAKE_CUDA_ARCHITECTURES` | `70-real` | Kod maszynowy tylko dla V100: brak kompilacji JIT PTX przy starcie, mniejsze binarki, kilkukrotnie krótszy build. ggml wybiera ścieżki kodu specyficzne dla Volty (MMQ, MMVQ, FlashAttention na tensor core'ach WMMA). |
| `GGML_CUDA_FA` + `GGML_CUDA_FA_QUANTS` | `f16, q8_0, q4_0, q5_0, q8_0/q4_0, q8_0/f16` | FlashAttention z kwantyzowanym KV cache. Pominięte `bf16` — V100 nie ma sprzętowego BF16. |
| `GGML_CUDA_GRAPHS` | `ON` | CUDA graphs zmniejszają narzut uruchamiania kerneli przy generowaniu tokenów. |
| `GGML_CUDA_COMPRESSION_MODE` | `none` | Jedna architektura — kompresja fatbina nic nie daje, a spowalnia start. |
| `GGML_NATIVE` | `ON` | Kod CPU zoptymalizowany pod procesor hosta (warstwy na CPU, sampling). |
| Domyślne parametry uruchomienia | `-ngl 999 -fa on -ctk q8_0 -ctv q8_0 -c 32768 -b 2048 -ub 512` | Cały model na GPU, FlashAttention, KV cache w q8_0 (≈ połowa pamięci f16 przy minimalnej stracie jakości). |

### Wymagania wersji — ważne dla V100

* **CUDA Toolkit 12.x (zalecane 12.9).** CUDA 13 usunęła wsparcie dla Volty (sm_70) —
  skrypty budowania przerwą pracę, jeśli wykryją nvcc 13+.
* **Sterownik NVIDIA z gałęzi 580 lub starszej.** 580 to ostatnia gałąź wspierająca Voltę;
  nowsze sterowniki nie widzą V100. Nie instaluj meta-pakietów `cuda` / `cuda-drivers`
  (ciągną najnowsze wersje) — instaluj `cuda-toolkit-12-9`.

## Ubuntu 24.04 LTS

```bash
git clone <ten-repo> optymalizacja-v100 && cd optymalizacja-v100

./scripts/setup-ubuntu.sh --with-driver   # pomiń --with-driver, jeśli sterownik 580 już jest
sudo reboot                               # tylko po instalacji sterownika
source /etc/profile.d/cuda-v100.sh

./scripts/build-ubuntu.sh                 # binarki w build/bin
nvidia-smi                                # sprawdź, czy V100 jest widoczna
```

Uruchomienie:

```bash
./scripts/run-server.sh models/Qwen3-32B-Q4_K_M.gguf
# otwórz http://127.0.0.1:8080  (API zgodne z OpenAI: /v1/chat/completions)

CTX=65536 KV=q4_0 HOST=0.0.0.0 ./scripts/run-server.sh models/model.gguf --parallel 2
./scripts/bench.sh models/model.gguf
```

## Windows 11

1. Zainstaluj **Visual Studio 2022** (lub *Build Tools for Visual Studio 2022*) z obciążeniem
   **„Programowanie aplikacji klasycznych w języku C++”** — zawiera CMake i Ninja.
   VS 2022 jest oficjalnie wspierane przez CUDA 12.x; z nowszym VS skrypt doda
   `-allow-unsupported-compiler`.
2. Zainstaluj sterownik NVIDIA dla Tesla V100 z gałęzi **R580** (Data Center / Tesla driver).
3. Zainstaluj **CUDA Toolkit 12.9** (po Visual Studio).
4. Zbuduj (PowerShell w katalogu repo albo dwuklik na `scripts\build-windows.bat`):

   ```powershell
   powershell -ExecutionPolicy Bypass -File scripts\build-windows.ps1
   ```

   Binarki trafią do `build\bin`, razem z potrzebnymi DLL-ami CUDA (cudart, cuBLAS).
   Domyślnie budowany jest dołączony BoringSSL (pobierany podczas budowania), żeby działało
   pobieranie modeli przez `-hf`; flaga `-NoHttps` to wyłącza.
5. Uruchom:

   ```powershell
   .\scripts\run-server.ps1 -Model models\Qwen3-32B-Q4_K_M.gguf
   .\scripts\run-server.ps1 -Model models\model.gguf -Ctx 65536 -Kv q4_0 -Extra "--parallel","2"
   .\scripts\bench.ps1 models\model.gguf
   ```

Uwaga: V100 pod Windows domyślnie działa w trybie **TCC** (karta obliczeniowa, bez wyjścia
obrazu) — to dobry tryb dla llama.cpp. Sprawdzisz go w `nvidia-smi` (kolumna *TCC/WDDM*).

## Co zmieści się w 32 GB

Orientacyjnie, z KV cache q8_0 i FlashAttention:

| Model | Kwantyzacja | Plik | Kontekst |
|---|---|---|---|
| 7–14B | Q8_0 | 8–16 GB | 64k–128k |
| 27–32B (Qwen3-32B, Gemma 3 27B) | Q4_K_M / Q5_K_M | 17–23 GB | 32k–64k |
| 30B MoE (Qwen3-30B-A3B) | Q6_K / Q8_0 | 25–32 GB | 16k–32k |
| 70B | Q2_K / IQ3_XXS | 26–28 GB | 4k–8k (lub `-ngl` < 999 i część na CPU) |
| duże MoE (gpt-oss-120b itp.) | MXFP4 / Q4 | > 32 GB | `--n-cpu-moe N` — eksperci na CPU, reszta na GPU |

Wskazówki dla Volty:

* Wybieraj kwantyzacje `Q4_K_M`, `Q5_K_M`, `Q6_K`, `Q8_0` lub `F16`. Unikaj modeli/KV cache
  w **BF16** — V100 nie ma sprzętowego BF16 i jest to wyraźnie wolniejsze.
* Brakuje pamięci → najpierw `KV=q4_0` / `-Kv q4_0`, potem mniejszy kontekst, dopiero potem
  mniejsza kwantyzacja modelu.
* `-ub 1024` może przyspieszyć przetwarzanie długich promptów kosztem ~1–2 GB VRAM — sprawdź
  `bench.sh` / `bench.ps1`.
* Kilka V100 (np. NVLink w serwerach SXM2): model jest dzielony automatycznie;
  na Ubuntu `setup-ubuntu.sh` instaluje NCCL, który to przyspiesza.

## Aktualizacja llama.cpp

```bash
./scripts/update-llama.sh b11400   # dowolny tag z https://github.com/ggml-org/llama.cpp/tags
./scripts/build-ubuntu.sh
git add -A && git commit -m "Update llama.cpp to b11400"
```

Konfiguracja V100 jest w `cmake/v100.cmake`, a nie w źródłach llama.cpp, więc aktualizacja
nie wymaga nanoszenia żadnych łatek.

## Licencja

llama.cpp jest na licencji MIT — patrz [`llama.cpp/LICENSE`](llama.cpp/LICENSE).
