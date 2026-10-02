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
  bench.sh/.ps1       benchmark (llama-bench): KV f16 vs q8_0, krótki i długi kontekst
  tune-gpu.sh/.ps1    maks. zegary aplikacyjne, limit mocy, persistence mode
  update-llama.sh     podmiana kopii llama.cpp na nowszy tag upstream
models/               tu wrzucasz pliki .gguf (ignorowane przez git)
```

## Co jest zoptymalizowane

| Ustawienie | Wartość | Dlaczego |
|---|---|---|
| `CMAKE_CUDA_ARCHITECTURES` | `70-real` | Kod maszynowy tylko dla V100: brak kompilacji JIT PTX przy starcie, mniejsze binarki, kilkukrotnie krótszy build. ggml wybiera ścieżki kodu specyficzne dla Volty (MMQ, MMVQ, FlashAttention na tensor core'ach). |
| `GGML_CUDA_FA` + `GGML_CUDA_FA_QUANTS` | `f16, q8_0, q4_0, q5_0, q8_0/q4_0, q8_0/f16` | FlashAttention z kwantyzowanym KV cache. Pominięte `bf16` — V100 nie ma sprzętowego BF16. |
| `GGML_CUDA_GRAPHS` | `ON` | CUDA graphs zmniejszają narzut uruchamiania kerneli przy generowaniu tokenów. |
| `GGML_CUDA_COMPRESSION_MODE` | `none` | Jedna architektura — kompresja fatbina nic nie daje, a spowalnia start. |
| `GGML_NATIVE` | `ON` | Kod CPU zoptymalizowany pod procesor hosta (warstwy na CPU, sampling). |
| Domyślne parametry uruchomienia | `-ngl 999 -fa on -ctk f16 -ctv f16 -c 32768 -b 2048 -ub 512` | Cały model na GPU, FlashAttention, KV cache w f16 — najszybszy wariant na Volcie (szczegóły niżej). |
| Zegary GPU (`tune-gpu`) | maks. *application clocks* i limit mocy | GPU od razu pracuje na najwyższych zegarach zamiast startować z domyślnych; persistence mode usuwa 1–2 s inicjalizacji sterownika przy każdym starcie (Linux). |

### KV cache na V100: f16 zamiast q8_0

Z analizy `ggml/src/ggml-cuda/fattn.cu`: na Volcie przy generowaniu tokenów dla modeli z GQA ≥ 4
(Llama 3, Qwen 2.5/3, Mistral i większość współczesnych) wybierany jest kernel `TILE`,
który działa wyłącznie na danych f16. (Przy GQA ≤ 2, np. Gemma 3 27B, używany jest kernel `VEC`,
który czyta q8_0 bezpośrednio — tam q8_0 nie jest wolniejsze.) Kwantyzowany KV cache (q8_0/q4_0) jest więc przy
**każdym tokenie i każdej warstwie w całości konwertowany do f16** (`fattn-common.cuh`), co
przy długim kontekście kosztuje ok. 2–2,5× więcej transferu pamięci w attention niż f16.
Na Turingu/Ampere tego problemu nie ma, dlatego popularna rada „zawsze q8_0” nie pasuje do V100.

* **f16** — domyślnie, najszybciej.
* **q8_0 / q4_0** — tylko gdy model + kontekst nie mieszczą się w 32 GB.

Sprawdź na swoim modelu: `./scripts/bench.sh model.gguf` porównuje f16 i q8_0 przy pustym
kontekście i przy 16k tokenów (`-d 16384`) — różnica rośnie z długością kontekstu.

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
sudo ./scripts/tune-gpu.sh                # opcjonalnie: maks. zegary (do restartu)
```

Uruchomienie:

```bash
./scripts/run-server.sh models/Qwen3-32B-Q4_K_M.gguf
# otwórz http://127.0.0.1:8080  (API zgodne z OpenAI: /v1/chat/completions)

CTX=65536 KV=q8_0 HOST=0.0.0.0 ./scripts/run-server.sh models/model.gguf --parallel 2
./scripts/bench.sh models/model.gguf
```

## Windows 11

1. Zainstaluj **Visual Studio 2022** (lub *Build Tools for Visual Studio 2022*) z obciążeniem
   **„Programowanie aplikacji klasycznych w języku C++”** i komponentem
   **„Narzędzia CMake języka C++ dla systemu Windows”** (*C++ CMake tools for Windows* — daje CMake
   i Ninja). Do budowania z HTTPS potrzebny jest też **Git** (`winget install Git.Git`).
   VS 2022 jest oficjalnie wspierane przez CUDA 12.x; z nowszym VS skrypt doda
   `-allow-unsupported-compiler`.
2. Zainstaluj sterownik NVIDIA dla Tesla V100 z gałęzi **R580** (Data Center / Tesla driver).
3. Zainstaluj **CUDA Toolkit 12.9** (po Visual Studio).
4. Jednorazowo zezwól na uruchamianie lokalnych skryptów PowerShell (Windows 11 domyślnie
   je blokuje). Jeśli repo pobrano jako ZIP, odblokuj też pliki:

   ```powershell
   Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
   Get-ChildItem -Recurse scripts | Unblock-File   # tylko dla repo pobranego jako ZIP
   ```

   Zbuduj (PowerShell w katalogu repo albo dwuklik na `scripts\build-windows.bat`):

   ```powershell
   powershell -ExecutionPolicy Bypass -File scripts\build-windows.ps1
   ```

   Binarki trafią do `build\bin`, razem z potrzebnymi DLL-ami CUDA (cudart, cuBLAS).
   Domyślnie budowany jest dołączony BoringSSL (pobierany podczas budowania), żeby działało
   pobieranie modeli przez `-hf`; flaga `-NoHttps` to wyłącza (bez Gita wyłącza się sama).
5. Uruchom:

   ```powershell
   .\scripts\run-server.ps1 -Model models\Qwen3-32B-Q4_K_M.gguf
   .\scripts\run-server.ps1 -Model models\model.gguf -Ctx 65536 -Kv q8_0 -Extra "--parallel","2"
   .\scripts\bench.ps1 models\model.gguf
   ```

   Opcjonalnie, w PowerShell uruchomionym jako Administrator: `.\scripts\tune-gpu.ps1`.
   Skrypt Windows uruchamia serwer z `-lm none` (bez mmap) — ładowanie przez mmap jest pod Windows
   wolne i trzyma drugą kopię wag w RAM, mimo że wszystkie warstwy są na GPU.

Uwaga: V100 pod Windows domyślnie działa w trybie **TCC** (karta obliczeniowa, bez wyjścia
obrazu) — to dobry tryb dla llama.cpp. Sprawdzisz go w `nvidia-smi` (kolumna *TCC/WDDM*).

## Co zmieści się w 32 GB

Orientacyjnie, z FlashAttention. Kontekst podany dla KV q8_0 — z f16 (szybciej) zmieści się
mniej więcej o połowę mniejszy:

| Model | Kwantyzacja | Plik | Kontekst |
|---|---|---|---|
| 7–14B | Q8_0 | 8–16 GB | 64k–128k |
| 27–32B (Qwen3-32B, Gemma 3 27B) | Q4_K_M / Q5_K_M | 17–23 GB | 32k–64k |
| 30B MoE (Qwen3-30B-A3B) | Q5_K_M / Q6_K | 22–25 GB | 16k–32k (Q8_0 ≈ 32,5 GB — nie mieści się) |
| 70B | Q2_K / IQ3_XXS | 26–28 GB | 4k–8k (lub `-ngl` < 999 i część na CPU) |
| duże MoE (gpt-oss-120b itp.) | MXFP4 / Q4 | > 32 GB | `--n-cpu-moe N` — eksperci na CPU, reszta na GPU |

Wskazówki dla Volty:

* Wybieraj kwantyzacje `Q4_K_M`, `Q5_K_M`, `Q6_K`, `Q8_0` lub `F16`. Unikaj modeli/KV cache
  w **BF16** — V100 nie ma sprzętowego BF16 i jest to wyraźnie wolniejsze.
* Brakuje pamięci → najpierw `KV=q8_0` / `-Kv q8_0`, potem `q4_0`, potem mniejszy kontekst,
  dopiero na końcu mniejsza kwantyzacja modelu.
* Do przetestowania: `GGML_CUDA_GRAPH_OPT=1` (eksperymentalne w llama.cpp — równoległe
  wykonywanie niezależnych gałęzi grafu na kilku strumieniach CUDA). Porównaj `bench.sh` z i bez.
* `-ub 1024` może przyspieszyć przetwarzanie długich promptów kosztem ~1–2 GB VRAM — sprawdź
  `bench.sh` / `bench.ps1`.
* Kilka V100 (np. NVLink w serwerach SXM2): model jest dzielony automatycznie;
  na Ubuntu `setup-ubuntu.sh` instaluje NCCL, który to przyspiesza.
* Opcjonalnie dla modeli MoE: `./scripts/build-ubuntu.sh -DGGML_CUDA_CCCL_VERSION=v3.4.3`
  (Windows: `-CMakeArgs "-DGGML_CUDA_CCCL_VERSION=v3.4.3"`) pobiera nowszą bibliotekę CCCL
  z szybszym top-k na GPU — tak budowane są oficjalne wydania llama.cpp dla CUDA 12.

## Uwagi do budowania

* Ustawienia z `cmake/v100.cmake` trafiają do cache CMake tylko przy **pierwszej** konfiguracji
  katalogu `build/`. Po zmianie tego pliku (lub opcji `-D...`) usuń `build/` i zbuduj od nowa.
* Na Ubuntu można budować przed instalacją sterownika (skrypt linkuje wtedy do zaślepki
  `libcuda` i wypisuje ostrzeżenie) — do uruchomienia sterownik 580 jest oczywiście potrzebny.
* Przy kilku zainstalowanych wersjach CUDA wskaż właściwą: `CUDA_HOME=/usr/local/cuda-12.9`
  (Linux) lub `-CudaPath "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.9"` (Windows).
* Kompilacja kerneli CUDA jest pamięciożerna — przy małej ilości RAM ogranicz liczbę wątków,
  np. `cmake --build build -j 4`.

## Aktualizacja llama.cpp

```bash
./scripts/update-llama.sh b11400   # dowolny tag z https://github.com/ggml-org/llama.cpp/tags
rm -rf build && ./scripts/build-ubuntu.sh
git add -A -f llama.cpp && git add LLAMA_CPP_VERSION && git commit -m "Update llama.cpp to b11400"
```

Konfiguracja V100 jest w `cmake/v100.cmake`, a nie w źródłach llama.cpp, więc aktualizacja
nie wymaga nanoszenia żadnych łatek.

## Licencja

llama.cpp jest na licencji MIT — patrz [`llama.cpp/LICENSE`](llama.cpp/LICENSE).
