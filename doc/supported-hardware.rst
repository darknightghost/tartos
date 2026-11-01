==================
Supported Hardware
==================

Hardware supported by tartos, organized per target: what each part
provides, **how the families differ**, and **what those differences do
to the drivers**.

Kernel design decisions themselves are recorded in
``doc/kernel-design.rst``; this document records hardware facts and the
consequences they impose.  Where a hardware fact contradicts a design
assumption, the contradiction is stated here and the corresponding
decision is tracked in the open-questions list of
``doc/kernel-design.rst``.

Status legend (same as ``doc/kernel-design.rst``): *[settled]* decided;
*[draft]* written, open to change; *[TODO]* undecided; *[deferred]*
postponed on purpose.

How to read an entry
====================

Each family entry records, in this order:

* parts and their memory sizes (what the datasheet's ordering table
  prints, per density code);
* core, maximum clock, FPU/DSP/MPU presence as **documented** (the
  wording matters — several facts are absent from the documents);
* memory map specifics that change code: TCM, DMA-reachable RAM,
  caches and their coherency consequences;
* NVIC priority width and shared interrupt vectors;
* GPIO / pin-muxing register generation and who owns EXTI source
  selection;
* DMA architecture (channels vs. streams, request mux, FIFO);
* clock tree (RCU) and power/voltage ordering rules;
* external memory (EXMC vs. QSPI/OSPI/SQPI, package gating);
* peripheral capability deltas that break driver sharing.

Facts are taken from the GigaDevice datasheets and user manuals supplied
to the project; the reference-document location is machine-specific and
lives in ``AGENTS.local.md``.  Revisions on disk are recorded under
“Documented revisions” because several conclusions changed between
revisions.

Target baseline
===============

* Scope *[settled]*: the **GigaDevice GD32 / GD32H7 / GD32W5 lines**
  whose datasheets and user manuals are part of the reference set —
  F101/F103/F105/F107, F130/F150 (F1x0), F205/F207 (F2), F303/F305/F307
  (F30x), F310/F330/F350 (F3x0), F403/F405/F407/F425/F427/F450/F470
  (F4xx), F502/F503/F505/F527/F5HC (F5), H737/H757/H759/H75E (H7) and
  GD32W51x.  An entry is added as support for a specific part lands.
* Cores *[settled]*: the family spans **Cortex-M3** (all of F1, F1x0,
  F2), **Cortex-M4** (F30x, F3x0, F4xx), **Cortex-M33** (F5, W51x) and
  **Cortex-M7** (H7).  There is **no Cortex-M0/M0+ part in scope** — the
  F1x0 line is Cortex-M3, not M0+.  Architecture is Armv7-M up to the
  F4xx/H7 lines and Armv8-M Mainline for F5/W51x.
* The **address-space layout is identical across all of them** — the
  MPU and the privilege split change only how the user/kernel boundary
  is *protected*, never where regions sit (see “Layout vs. protection”
  in ``doc/kernel-design.rst``).
* Floating point *[settled]*: user threads may use the FPU where the
  part has one; kernel code never does.  FPU presence is **not** uniform
  (see “FPU and the thread context” below) and is probed at boot.
* SRAM baseline *[settled]*: **16 KiB or more** is the target; smaller
  parts are a goal, not a requirement.  The audit shows the small parts
  are a large share of the family — F101 from **4 KiB**, F103 from
  6 KiB, F130/F150 4–8 KiB, F310/F330/F350 4–16 KiB — so the tiny-RAM
  profile is a real configuration, not a contingency.
* External RAM *[settled]*: parts that need expansion memory are in
  scope, **but the bus is not one thing** — EXMC is present on some
  families and absent on others, SDRAM only on certain packages, and
  F5HC/W51x attach external RAM or code over SQPI/QSPI instead
  (see “External memory and its gating”).
* Single core *[settled]*: every part in scope is single-core, and the
  kernel design stays multi-core-ready.
* TrustZone *[settled]*: only GD32F5HC and GD32W51x implement it; the
  kernel is built with ``TZEN`` de-activated so the core runs in a
  single security state (see “TrustZone-capable parts”).

Family summary
==============

Cortex-M3 parts implement the MPU as a core feature; the datasheets of
F1/F2 list it, those of F1x0/F3x0 do not.

.. list-table::
   :header-rows: 1
   :widths: auto

   * - Family
     - Core / max clock
     - Flash
     - SRAM
     - FPU
     - MPU documented
     - Cache
     - DMA architecture
     - Pin-mux generation
   * - GD32F101
     - M3 / 56 MHz
     - 16 KiB – 3 MiB
     - 4 – 80 KiB
     - no
     - yes (core bullet)
     - none
     - 2 ctrl / 12 fixed channels
     - AFIO remap
   * - GD32F103
     - M3 / 108 MHz
     - 16 KiB – 3 MiB
     - 6 – 96 KiB
     - no
     - yes
     - none
     - 2 ctrl / 12 fixed channels
     - AFIO remap
   * - GD32F105 / F107
     - M3 / 108 MHz
     - 64 – 1024 KiB
     - 64 – 96 KiB
     - no
     - yes
     - none
     - 2 ctrl / 12 fixed channels
     - AFIO remap
   * - GD32F130 / F150 (F1x0)
     - M3 / 48, 72 MHz
     - 16 – 64 KiB
     - 4 – 8 KiB
     - no
     - **not claimed**
     - none
     - 1 ctrl / 7 fixed channels
     - SYSCFG AFSEL
   * - GD32F205 / F207
     - M3 / 120 MHz
     - 256 KiB – 3 MiB
     - 128 / 256 KiB
     - no
     - yes
     - none
     - 2 ctrl / 14 fixed channels
     - AFIO remap
   * - GD32F303/305/307 (F30x)
     - M4 / 120 MHz
     - 128 – 3072 KiB
     - 48 – 96 KiB
     - yes + DSP
     - yes
     - none
     - 2 ctrl / 12 fixed channels
     - AFIO remap
   * - GD32F310/330/350 (F3x0)
     - M4 / 72, 84, 108 MHz
     - 16 – 128 KiB
     - 4 – 16 KiB
     - claimed + DSP
     - **not claimed**
     - none
     - 1 ctrl / 7 fixed channels
     - SYSCFG AFSEL
   * - GD32F403
     - M4 / 168 MHz
     - 256 – 3072 KiB
     - 64 – 128 KiB
     - single + DSP
     - yes
     - none
     - 2 ctrl / 16 ch (PERIEN mux, FIFO)
     - AFIO remap
   * - GD32F405–F470
     - M4 / 168–240 MHz
     - 512 KiB – 3 MiB
     - 192 – 768 KiB (TCM 64 KiB)
     - single + DSP
     - yes
     - none
     - 2 ctrl / 16 ch (PERIEN mux, FIFO)
     - SYSCFG AFSEL
   * - GD32F502 / F503 / F505
     - M33 / 200, 252, 280 MHz
     - 128 – 1024 KiB
     - 64 – 192 KiB
     - yes (precision not stated)
     - yes (count not stated)
     - none
     - 2 ctrl / 12 ch + DMAMUX
     - AFIO_EXTISS
   * - GD32F527
     - M33 / 200 MHz
     - 4 – 7.5 MiB
     - 512/1024 KiB + TCM 64 KiB
     - yes
     - yes
     - none
     - 2 ctrl / 16 ch, FIFO
     - SYSCFG AFSEL
   * - GD32F5HC
     - M33 / 200 MHz
     - 2 MiB
     - 320 KiB
     - yes
     - yes, **8 + 8 regions**
     - 32 KiB I-cache
     - 2 ctrl / 16 ch, fixed request table
     - SYSCFG AFSEL
   * - GD32H73x / H75x / H75E
     - M7 / 600 MHz
     - 1 – 3.75 MiB
     - 1 MiB (+4 KiB backup)
     - yes (single, double per DS)
     - yes (count not stated)
     - I- and D-cache, **sizes not documented**
     - 2 ctrl / 16 ch + DMAMUX + MDMA
     - SYSCFG AFSEL
   * - GD32W515
     - M33 / 180 MHz
     - (no DS on disk)
     - 448 KiB (per UM)
     - yes
     - 8 + 8 regions
     - 32 KiB I-cache
     - 2 ctrl / 16 ch, fixed request table
     - SYSCFG AFSEL

Families, part by part
======================

GD32F1 — F101 / F103 / F105 / F107
-----------------------------------

* Memory (datasheet ordering tables, density code → flash / SRAM)
  *[draft]*:

  - **F101** (M3, 56 MHz): ``4`` 16/4, ``6`` 32/6, ``8`` 64/10,
    ``B`` 128/16, ``C`` 256/32, ``D`` 384/48, ``E`` 512/48, ``F``
    768/80, ``G`` 1024/80, ``I`` 2048/80, ``K`` 3072/80 KiB.
    Single SRAM block; no backup-SRAM split documented.
  - **F103** (M3, 108 MHz): ``4`` 16/6, ``6`` 32/10, ``8`` 64/20,
    ``B`` 128/20, ``C`` 256/48, ``D`` 384/64, ``E`` 512/64, ``F``
    768/96, ``G`` 1024/96, ``I`` 2048/96, ``K`` 3072/96 KiB.
  - **F105 / F107** (M3, 108 MHz): 64–1024 KiB flash, 64–96 KiB SRAM;
    F107 adds Ethernet on every listed part; both carry USB FS and
    2× CAN 2.0B.  Core naming: see the caveat below.
  - Packages run QFN36/TSSOP20 up to LQFP144, GPIO PA–PG (up to 112
    pins); supply 2.6–3.6 V, industrial −40…+85 °C only in these
    datasheets.
* No FPU and no DSP is mentioned anywhere in the F1 datasheets: these
  parts are **soft-float only**, so user threads that use floating point
  link a software FP library (size cost, not a correctness problem).
* Core naming *[TODO]*: the F105/F107, F130 and F150 datasheets label
  the core **Cortex-M3** — in the feature list *and* in the clock-tree
  diagram, consistently across the revisions on disk — while these lines
  are commonly described elsewhere as Cortex-M4.  Nothing in the
  reference set resolves it.  The entries above therefore follow the
  datasheets, and the rule that comes out of the discrepancy is a
  general one: **the core is read from ``CPUID`` at boot**, and M4-only
  paths (DSP instructions, FPU context) are never enabled on the
  strength of a family name.
* DMA: two controllers with **7 (DMA0) + 5 (DMA1) fixed-mapping
  channels**, no request mux, no FIFO; channels 3 and 4 share one
  interrupt vector.
* Pin mux: **AFIO remap** registers (see “GPIO and pin muxing”).
* EXMC is gated by package: the ordering tables show it on the 100-pin
  (``V``) and 144-pin (``Z``) parts only, never on T/C/R packages.
* MPU is listed as a Cortex-M3 core feature without density caveat;
  whether the small-density silicon implements it **is not documented**
  anywhere in these datasheets — see “MPU region budget”.

GD32F1x0 — F130 / F150
-----------------------

* Cortex-**M3** (not M0+) at 48 MHz (F130) / 72 MHz (F150); flash
  16/32/64 KiB (``x8`` parts split 32 code + 32 data), SRAM **4–8 KiB**
  only, packages TSSOP20 … LQFP64, 15–55 GPIO.
* **Neither an MPU nor an FPU is claimed** in these datasheets: the
  unprivileged/MPU degradation chain has to assume “no MPU” here and
  fall back to privilege level plus logical isolation.
* One 7-channel DMA controller, fixed request mapping, no EXMC.
* Pin mux is the GD-style in-block AF selection with EXTI source
  selection in SYSCFG — **register-incompatible with F101/F103**.

GD32F2 — F205 / F207
--------------------

* Cortex-M3 at 120 MHz, **no FPU**, flash 256 KiB–3 MiB, SRAM
  128 KiB (``C``/``E``) or 256 KiB (``G``/``K``), split SRAM0 112 +
  SRAM1 16 (+ SRAM2 128 KiB on the 256 KiB parts); packages LQFP64 …
  LQFP176, up to 140 GPIO (PA–PI).
* DMA: two controllers, **7 + 7 = 14 channels**, fixed request mapping.
* EXMC on ``V``/``Z``/``I`` packages, **SDRAM only on 144/176-pin**
  parts; a TLI display interface appears on the ``V``/``Z``/``I`` parts.
* Register generation matches F1 (AFIO remap, CTL0/CTL1 GPIO).

GD32F30x — F303 / F305 / F307
------------------------------

* Cortex-M4 with **single-precision FPU + DSP + MPU**, 120 MHz; flash
  128–3072 KiB; SRAM 48–96 KiB; GPIO PA–PG, LQFP48 … LQFP144;
  VDD 2.6–3.6 V (F303 also documents VBAT 1.8–3.6 V).
* Density detail (datasheet tables): ``C`` 256/48, ``R`` up to
  3072/96, ``V``/``Z`` up to 3072/96 KiB flash/SRAM; F305 adds a second
  CAN and USB FS; F307 adds Ethernet.
* EXMC on ``V``/``Z`` packages **without SDRAM support** (the EXMC
  chapter lists SRAM/PSRAM/NOR/NAND/PC card only).
* DMA: 7 + 5 fixed channels, no mux, no FIFO — the F1/F2/F30x shape.
* Pin mux: **AFIO remap generation**, same as F1/F2 — so the F303 GPIO
  driver is *not* the F330 GPIO driver (verified incompatible), even
  though both are Cortex-M4.

GD32F3x0 — F310 / F330 / F350
------------------------------

* Cortex-M4 at 72 (F310) / 84 (F330) / 108 MHz (F350); flash
  16–128 KiB; SRAM **4–16 KiB**; packages TSSOP20 … LQFP64, 15–55 GPIO;
  ports A, B, C, D, F only (no GPIOE/G).
* The F3x0 datasheets claim an **FPU** in the Cortex-M4 core bullet but
  **omit the MPU bullet** that F30x/F4xx include; MPU presence on this
  silicon is therefore *not documented* and must be read at runtime.
* One 7-channel DMA controller, fixed mapping, **no EXMC at all**.
* F350 carries USB FS OTG; no CAN in this line.
* Pin mux: GD-style AFSEL with EXTI source select in SYSCFG.

GD32F4xx — F403 / F405 / F407 / F425 / F427 / F450 / F470
----------------------------------------------------------

* All **Cortex-M4** — there is no Cortex-M7 in the F4 line, and **no
  cache on any F4 part**.  Single-precision FPU, DSP, MPU claimed
  family-wide; 168 MHz (F403/F405/F407), 200 MHz (F425/F427/F450),
  240 MHz (F470).
* Memory (as printed): F403 64–128 KiB SRAM; F405/F407 **192 KiB =
  SRAM0 112 + SRAM1 16 + TCM 64** (+4 KiB backup); F425/F427 256 KiB
  (= 112 + 16 + 64 + TCM 64); F450 256/512 KiB and F470 256/512/768 KiB
  with ADDSRAM on the largest parts.  Flash 256 KiB–3 MiB.  Two oddities
  are reported as printed and not explained by the datasheets: the
  3072 KiB-flash parts list **less** SRAM than the 2048 KiB ones, and
  F403 ``RCT6`` (64 KiB) vs ``RCT7`` (128 KiB) differ.
* **TCM is CPU-only**: nothing documented lets a DMA controller reach
  the 64 KiB TCM, and F4 has IPA (LCD timer DMA assist) rather than
  MDMA.  DMA buffers must be placed in SRAM0/1/2 by the linker map.
* DMA: two controllers × **8 channels with a programmable request
  field (``PERIEN``) and a per-channel FIFO**; memory-to-memory runs on
  DMA1 only.  This is a different driver from the F1/F2/F30x fixed
  channel block.
* EXMC: **absent on F405 and F425** (no EXMC text at all), present on
  F403 without SDRAM, and on F407/F427/F450/F470 gated by package
  (``V`` = EXMC without SDRAM, ``Z``/``I`` = with SDRAM).
* USB: FS plus **HS OTG on F405 and later** (HS needs an external
  PHY); Ethernet on F407/F427/F450/F470; CAN is **2.0B only — no CAN FD
  anywhere in F4**.
* USART: **oversampling is documented, RX FIFO is not** — the reverse of
  F3x0/H7.  Pin mux on F405 and later is the SYSCFG/AFSEL generation,
  while **F403 stays on the AFIO-remap generation**: the F4 line itself
  spans two GPIO driver families.

GD32F5 — F502 / F503 / F505 / F527 / F5HC
-------------------------------------------

* Cortex-**M33**; 200 MHz (F502, F527, F5HC), 252 MHz (F503), 280 MHz
  (F505).  FPU and DSP are claimed; **FPU precision is not documented**.
  VDD 2.6–3.6 V (F502/503/505) and 1.71–3.6 V (F527), 2.7–3.63 V
  (F5HC).
* Memory: F502 64 KiB SRAM (the general description says 128 KiB while
  the per-part table says 64 — reported as printed); F503 64 KiB, 128
  KiB on the 1024 KiB-flash parts; F505 128–192 KiB; F527 512 KiB
  (1024 KiB on ``M`` densities) **+ 64 KiB TCM**; F5HC 320 KiB
  (SRAM0/1/2 64 KiB each + SRAM3 128 KiB) **plus a 32 KiB instruction
  cache**.  Flash: F502 up to 1 MiB, F503/F505 up to 1 MiB, F527
  4–7.5 MiB, F5HC 2 MiB.
* **F502/F503/F505 have a DMAMUX** (12 channels, free programmable
  request mapping) — a third DMA shape; F527 has 2 × 8 = 16 channels
  with FIFO but **no DMAMUX**; F5HC has 16 channels with a **fixed
  request table**.  No MDMA in any F5 part.
* F5HC is the only TrustZone part in this line (with the MPU split
  8 secure + 8 non-secure regions, SAU 8 regions, TZPCU); F527
  documents "system security" (secure boot, trusted area) but no
  TrustZone, and the F502/503/505 datasheets do not mention it.
* F503/F505/F527 carry **2× CAN FD**; F502 is CAN 2.0B.
* External memory: EXMC on F503/F505 ``R``/``V`` (no SDRAM claimed),
  on F527 only ``Z``/``I`` packages have EXMC **with** SDRAM; F502 and
  F5HC have none, F5HC instead has QSPI + SQPI.
* PMU: LDOVS selects VCORE (1.1–1.2 V); a voltage-before-frequency
  **ordering rule is not documented** in the datasheets.
* Pin mux: F502 uses ``AFIO_EXTISS`` registers while F527/F5HC use
  SYSCFG — the EXTI source owner moves even inside one family.
* The F502/F503/F505 datasheets on disk are **0.9RC revisions** (and one
  of them contradicts itself about the DMA channel split, "7+5" vs
  "7+7"): treat F5 numbers as provisional.

GD32H7 — H737 / H757 / H759 / H75E
------------------------------------

* Cortex-**M7** at **600 MHz** (400 MHz under a lower supply condition —
  the datasheet table prints the threshold mangled, verify visually
  before quoting); DSP plus FPU; MPU present, region count not stated;
  **no TrustZone at all** (security means secure boot, DCRP and the
  secure-user flash regions).
* Memory: **1 MiB SRAM** = 512 KiB AXI SRAM at ``0x2400_0000`` plus a
  512 KiB pool re-partitionable into ITCM / D0TCM / D1TCM / AXI
  (ITCM window ``0x0000_0000``, DTCM ``0x2000_0000``), + SRAM0/SRAM1
  16 KiB each at ``0x3000_xxxx`` + 4 KiB backup SRAM at
  ``0x3880_0000`` (retained with VDD off); ECC per region and a
  programmable TCM wait state.  Flash 1/2/3.75 MiB at ``0x0800_0000``,
  4 KiB sectors.
* **Caches: an instruction cache and a write-back-capable data cache
  exist** (block diagram, and SYSCFG ``CPUICAC``/``CPUDCAC`` error-status
  registers whose fields are described only as “provided by the CPU”).
  **Neither datasheet nor user manual states their size, associativity
  or line length** — the Cortex-M7 implementation is configurable, so
  geometry must be read from the CPU registers at boot, not quoted from
  a datasheet.  There is also **no cache-coherency, memory-attribute or
  maintenance guidance anywhere in the manuals** (see “Absent from the
  documents”).
* DMA reachability: TCM is core-connected; **plain DMA ↔ TCM is not
  documented**.  MDMA has an extra AHB port into TCM with burst
  restrictions (increment equal to data size, no wider than 32 bits).
* NVIC: **4 priority bits, 16 levels**; **217 maskable IRQs**
  (H75E: 215); shared vectors include ADC0+ADC1, HAU+TRNG, CMP0+CMP1,
  and each USART merges its global and wake interrupts; 38 EXTI lines.
* DMA: 2 × 8 channels **plus a DMAMUX** (16 request-router channels,
  ``MUXID``, 8 request generators) **plus MDMA** (16 channels).
* Pin mux: GD-style ``CTL/OMODE/OSPD/PUD/AFSEL`` — **register-compatible
  with F4** (a superset: new input-filter registers), ports up to K;
  bases moved onto AHB4 at ``0x5802_xxxx``.
* RCU/PMU: IRC64M/IRC48M/LPIRC4M/IRC32K, HXTAL 4–50 MHz, PLL0/PLL1/PLL2
  (fractional) plus USBHS PLLs; **``LDOVS`` is writable only with the
  PLL disabled and voltage must be raised before frequency, lowered
  after** — a hard boot-ordering rule; VCORE may be fed by SMPS, LDO or
  external bypass, with ``VDD > VCORE`` required.
* External memory: EXMC everywhere (SRAM/NOR/NAND/PSRAM + SDRAM up to
  2 banks), **but SDRAM is package-gated** (``V``/100-pin parts listed
  without SDRAM, ``Z``/``I`` with it; H75E lists EXMC with no SDRAM
  claim); OSPI ×1–2 with memory-mapped (read-only) XIP windows.
* Peripherals new versus F4 and therefore needing their own drivers:
  USB HS 480 Mbps, 2× Ethernet 10/100 (H75E instead has an EtherCAT
  ESC plus two internal PHYs), **CAN FD on H757/759/75E but explicitly
  not on H737**, SPI with 16×32-bit FIFOs, ADC 2×14-bit + 1×12-bit with
  oversampling, I2C FM+ with SMBus 3.0/PMBus 1.3, SDIO with DDR50 and
  IDMA double buffering, TLI/DCI/CAU/HAU/TMU/HPDF/FAC/RTDEC blocks, and
  the TRIGSEL mux that now routes timer break inputs.  **TSI is absent
  on all H7 parts.**
* Low power: Sleep; Deep-sleep (all VCORE clocks off, **all SRAM and
  registers retained**, WFI or WFE/event wake, IRC64M resumes as system
  clock); Standby (VCORE domain off, its SRAM and registers lost, wake
  by NRST/RTC/FWDGT/WKUP → POR, refetch at ``0x0000_0000``).
* The manuals twice instruct the reader to consult a **separate
  GD32H73x/75x errata sheet**, which is not in the reference set.

GD32W51x and the TrustZone-capable parts
-----------------------------------------

* GD32W515 (single-stream 802.11b/g/n MAC/baseband/radio with PA/LNA
  and an integrated TCP/IP block) is a Cortex-M33 at 180 MHz with
  **448 KiB SRAM** (per the shared user manual) and TrustZone.
* **No standalone W51x datasheet exists in the reference set**: electrical
  limits, per-part flash/SRAM and packaging for W515 are *not
  documented*; everything known about it comes from the shared
  ``GD32W51x_F5HC`` user manual.
* TrustZone facts (also valid for GD32F5HC): enabled by
  ``EFUSE_TZCTL.TZEN`` or the ``TZEN`` option byte; **TZEN = 0 is fully
  supported** (separate non-TrustZone boot address in EFUSE); SAU has
  8 regions plus a fixed IDAU partition; **MPU is 8 regions per
  security state**; after reset the CPU is secure and boots from a
  secure address, and SRAM/flash/peripherals/GPIO/NVIC all start secure.
* TZPCU (TZSPC + TZBMPC + TZIAC) makes peripheral and block-SRAM
  accessibility a **configured attribute**: clocks and reset bits of
  secure peripherals are locked away from non-secure code, and illegal
  accesses raise a secure NVIC event.  DMA channels carry
  ``SECM/PRIV/SSEC/DSEC`` attributes — a non-secure driver cannot
  configure a secure channel, and secure↔non-secure transfers must go
  through a secure channel.
* Interrupts: 102 maskable IRQs (vector 117), **4 priority bits / 16
  levels**, no FIQ, and each interrupt is bound to a security state via
  ``NVIC_ITNS``; shared lines: HAU+TRNG, EXTI 5–9, EXTI 10–15.
* Memory (F5HC): 320 KiB SRAM aliased secure/non-secure (non-secure
  base ``0x2000_0000``, secure ``0x3000_0000``), 2 MiB main flash
  (non-secure ``0x0800_0000``, secure ``0x0C00_0000``), 256 KiB boot
  ROM, EFUSE 256 B, GSSA 16 KiB.  **No EXMC**; external code/RAM via
  QSPI (``QSPI_FLASH(MEM)`` at ``0x9000_0000``, XIP) and
  ``SQPI_PSRAM(MEM)`` at ``0x6000_0000``.
* Cache: **32 KiB instruction cache only, 2-way, 16-byte lines, code
  region only, no write-back D-cache**; software must invalidate before
  enabling and after writes to cached aliases; per-region bypass via
  ``ICACHE_CFGx``.  The coherency obligation on these parts is
  therefore *instruction*-cache invalidation after loading code, not
  data clean/invalidate.
* Peripheral deltas: USART has an **RX FIFO plus oversampling**; I2C
  adds FM+ 1 MHz and SMBus/PMBus/CRC; crypto blocks CAU/HAU/PKCAU/TRNG;
  DCI/TSI/HPDF/SDIO appear on W515.  **No CAN and no Ethernet** in
  either part.
* The **host↔Wi-Fi interface is not documented** in the user manual's
  Wi-Fi chapter (no mailbox, shared-RAM layout or firmware-provisioning
  description) even though the Wi-Fi block is an AHB bus master with its
  own interrupt lines and a ``WIFI_ON``/``WIFI_OFF`` VCORE domain.
  Until that interface is known, the driver/device model cannot be
  assumed to fit the Wi-Fi subsystem — see “Unmodelled hardware”.
* Power modes: Sleep; Deep-sleep (retains SRAM0 + 64 KiB plus
  FMC/PMU/RCU/EXTI/GPIO/CPU/``WIFI_ON``); Standby (all SRAM and the
  1.2 V domain registers lost, boot from ``0x0``); per-SRAM power gating
  through ``PMU_CTL1``.

Cross-family differences
========================

NVIC and priorities
-------------------

**Every part in scope implements 4 priority bits — 16 NVIC levels.**
SysTick uses the same width and HardFault is fixed at -1, below every
real-time thread.  There is no 8-bit-priority NVIC in this family, so
the kernel's 256-level U8 thread priority scale cannot map 1:1 onto
interrupt hardware (the design records the consequence in
“Priority scheme” of ``doc/kernel-design.rst``).

Cortex-M3/M4/M7 give **8 MPU regions**; Cortex-M33 gives 8 per security
state.  **No GigaDevice document states a region count** — the manuals
defer to the Arm core description — and the datasheets claim an MPU for
F1/F2/F30x/F4xx/F5/H7 while **F130/F150 and F310/F330/F350 do not claim
one at all**.  So:

* the design's nine-region target needs merging on every part (8 is the
  ceiling);
* on F1x0/F3x0 (and possibly low-density F1) the MPU may be absent
  entirely, which is exactly the documented degradation path —
  but the layout must not *depend* on the MPU, per
  ``doc/kernel-design.rst`` “Layout vs. protection”;
* region presence must be read at runtime (``MPU_TYPER``) rather than
  assumed from the family name.

FPU and the thread context
--------------------------

Soft-float only: **F1, F1x0, F2**.  Single precision: most F30x/F4xx.
Claimed but unquantified: **F3x0** (FPU listed, MPU not — mixed silicon)
and **F5** (precision not documented).  F5HC/W515: single precision plus
TrustZone.  H7: DSP and FPU, and the datasheets describe both single and
double precision depending on the part.  Consequently the FP context
size and the lazy-stacking behaviour are **per-part runtime properties**
(read ``CPUID``/CPACR-style presence bits), not compile-time family
assumptions.  Kernel code never uses FP, so only user thread contexts
are affected.

GPIO and pin muxing
-------------------

Two incompatible register generations are in scope, and they do not
follow the family numbering:

* **AFIO-remap generation** — ``GPIOx_CTL0/CTL1`` plus a *separate*
  AFIO block owning remap, EXTI source select and SWJ disable:
  **F1, F2, F30x, F403**.
* **GD-style generation** — ``CTL/OMODE/OSPD/PUD/AFSEL`` with AF
  selection inside the GPIO block and EXTI source selection in
  **SYSCFG** (``SYSCFG_EXTISS0-3``): **F1x0, F3x0, F405 and later, F5,
  H7, W51x**.
* Inside that second generation the EXTI mux owner still moves: F502
  puts the input-select registers in an **AFIO** block while F527/F5HC
  and H7 put them in **SYSCFG**.
* H7 GPIO is a superset of F4 GPIO (same names plus input-filter
  registers) — an address-only difference, hence shareable; F403 versus
  F405 is not.

Since AFIO and SYSCFG also carry other system bits, the pin-mux device
and the GPIO device are coupled differently in each generation, which is
what the “one driver may expose two device kinds” rule in
``doc/kernel-design.rst`` is for.

DMA
---

Four distinct architectures:

#. **Fixed-mapping channels, no FIFO** — F1/F1x0/F2/F30x/F3x0
   (7+5, 7, or 7+7 channels).  Request source per channel is hard-wired
   by the datasheet tables; shared vectors (ch 3/4).
#. **F4 channels with programmable request (``PERIEN``), per-channel
   FIFO, 8+8** — memory-to-memory on DMA1 only; TCM is unreachable
   (F405 and later).
#. **DMAMUX-based** — F502/F503/F505 (12 channels + free request mux)
   and H7 (16 channels + 16 mux channels + 8 request generators) —
   request routing becomes data, not code.
#. **F527 (16 ch, FIFO, no mux) and F5HC (16 ch, fixed table)**, which
   resemble each other but neither of the above.

MDMA exists only on H7.  F4's IPA is not a general-purpose DMA
accelerator.  On F5HC/W515 every channel additionally carries security
and privilege attributes.

Clock tree and power sequencing
-------------------------------

RCU cannot be shared across series: different PLL counts and names
(F105/F107 PLL1/PLL2; F2 3+2 PLLs; F30x PLL1/PLL2 with an audio path;
F4 ``PLL``/``PLLI2S``/``PLLSAI``; F5 ``PLL``/``PLLDIG``/``PLLI2S``),
different base addresses (F502 ``0x4002_1000`` vs F527/F5HC
``0x4002_3800``) and different oscillator sets (HXTAL ranges, IRC16M /
IRC48M / IRC64M / LPIRC4M / LIRC32K by family).  Each series is its own
RCU driver with its own device data.  **PMU is likewise not shareable**:
H7 mandates the LDOVS/SMPS voltage-vs-frequency ordering with PLL-off
write restriction, and F5 documents a programmable VCORE without
documenting the ordering rule.

External memory and its gating
------------------------------

* **EXMC (parallel)**: F1 and F2 gated by package (≥100 pins; F2 SDRAM
  only on 144/176-pin parts), F30x present without SDRAM on ``V``/``Z``,
  **absent on F3x0**, **absent on F405 and F425**, F403 without SDRAM,
  F407/F427/F450/F470 package-gated with SDRAM, F503/F505 on ``R``/``V``
  (SDRAM not claimed), F502 **absent**, F527 on ``Z``/``I`` only, F5HC
  and W515 **absent**, H7 present with SDRAM package-gated.
* **Serial XIP**: QSPI/OSPI/SQPI with memory-mapped read windows on F5HC
  (``0x9000_0000`` QSPI, ``0x6000_0000`` SQPI PSRAM), H7 (OSPI
  ``0x7000_0000``/``0x9000_0000``, read-only XIP) and W515.  External
  code from these windows interacts with the instruction cache and, on
  F5HC/W515, with the SAU/security attribution.
* So “supports external SRAM” must be a per-part property with a bus
  kind attached, not a family statement.

Interrupt vector collisions
---------------------------

Several peripherals share one vector, which the threaded-interrupt model
handles by waking a handler thread per vector rather than per
peripheral: F105/F107-class USB FS and CAN0 (they cannot coexist),
EXTI 5–9 and EXTI 10–15, DMA channel pairs, F5HC/W515 HAU+TRNG, H7
ADC0+ADC1, HAU+TRNG, CMP0+CMP1 and the merged USART global/wake
interrupts.  Vector counts range from ~43 (F1x0) to 217 (H7), which
bounds the interrupt-handler thread table.

Differences and their driver impact
===================================

Applying the “Driver splitting rules” of ``doc/kernel-design.rst``:

.. list-table::
   :header-rows: 1
   :widths: auto

   * - Function
     - Distinct drivers needed
     - Why
   * - GPIO / pin mux
     - 2 (+ F303 vs F330 check)
     - CTL0/CTL1 + AFIO remap vs. ``OMODE/PUD/AFSEL`` + SYSCFG; not
       register-compatible
   * - EXTI / SYSCFG / AFIO system block
     - 3–4
     - source-select registers move between AFIO and SYSCFG; H7 adds
       TCM wait state, cache-error and 38-line EXTI; F502 differs from
       F527/F5HC
   * - DMA
     - 4 (+1 secure-aware variant)
     - fixed channels vs. FIFO plus a programmable ``PERIEN`` request
       field vs. DMAMUX vs. the F527/F5HC
       shapes; F5HC/W515 add channel security attributes
   * - MDMA
     - 1 (H7 only)
     - H7-only block with TCM access and burst restrictions
   * - RCU (clock tree)
     - 1 per series
     - different PLL sets, names, bit fields and base addresses
   * - PMU / power
     - ≥3 (H7, F5, F4/F3)
     - LDOVS/SMPS ordering rule is H7-mandatory, undocumented on F5,
       absent on the older parts
   * - USART
     - ≥4
     - capability masks (UART3/UART4 lack smartcard and synchronous
       modes; UART4 has no DMA); F3x0 RX FIFO + 8/16 oversampling; F4xx
       oversampling **without** FIFO; F5HC/W515/H7 RX FIFO; H7 ISO7816
       and multi-buffer DMA
   * - SPI
     - ≥2
     - F4/F3 style (8/16-bit frames) vs. H7 16×32-bit FIFOs
   * - ADC
     - ≥3
     - 12-bit vs. H7 2×14-bit + 1×12-bit with oversampling; ADC clock
       ceilings differ (14/28/36/40 MHz by family) and constrain the
       RCU divider, so the ADC driver is coupled to the series clock
       tree
   * - CAN
     - 2 (+ absent on F3x0/F5HC/W515)
     - CAN 2.0B (F1–F4, F502) vs. CAN FD (F503/F505/F527, H757/759/75E)
       — and H737 shares the H7 manual but has **no** CAN FD
   * - I2C
     - 2–3
     - FM (400 kHz) vs. FM+ 1 MHz plus SMBus/PMBus/CRC on F5HC/H7
   * - Timers
     - ≥2 + a mux dependency
     - H7 adds TIMER40-44, 32/64-bit basics, composite PWM and routes
       break inputs through **TRIGSEL**; HALL input availability differs
   * - USB
     - ≥3
     - USBFS device-only (AFIO-remap era), USB FS+HS OTG (F405+),
       USBHS 480 Mbps with new IP (H7), and none on F3x0/F5 (except
       F350/F502 USBFS)
   * - Ethernet
     - 2
     - F107/F307/F407 10/100 vs. H7 dual-MAC 10/100; H75E has an
       EtherCAT ESC and internal PHYs instead
   * - External memory
     - 3 (EXMC, QSPI/OSPI/SQPI, none)
     - per-series gating and completely different buses on F5HC/W515
   * - Crypto / hash / random (CAU/HAU/TRNG/PKCAU)
     - 1–2 (F5HC/W515/H7)
     - absent on everything older; H7 shares the HAU+TRNG vector
   * - Display (TLI/DCI/IPA/RSPDIF/HPDF), TSI, RTDEC, TMU, FAC, EtherCAT
     - per part, no sharing
     - H7/F527/W515-only blocks; **TSI does not exist on H7 at all**

Unmodelled hardware
===================

Two cases the current driver/device model does not obviously cover; both
need a design answer before the corresponding part can be listed as a
target:

* **Wi-Fi subsystem (GD32W515)** — an AHB bus master with its own radio,
  baseband, MAC and integrated TCP/IP, several interrupt lines and a
  dedicated power domain.  If it requires vendor firmware loaded by the
  host and communicates through shared memory or mailboxes, then “a
  driver is code linked into the image and a device owns the register
  block” is not sufficient: there is a firmware blob with its own
  provenance, placement and lifecycle.  The host interface is **not
  documented**, so this stays open rather than decided.
* **TrustZone parts (F5HC, W515)** — modeled out of scope by
  ``TZEN = 0`` (see “Privilege and memory isolation” in
  ``doc/kernel-design.rst``).  Running them with ``TZEN = 1`` would add
  a third, orthogonal isolation axis (security state) and make DMA
  channel configuration, peripheral clocks and interrupt routing
  security-attributed.

Absent from the documents
=========================

Recorded as gaps because the design or a driver has to fall back on the
Arm core documentation, a runtime probe, or a document we do not have:

* **MPU region count** — no GigaDevice document states it for any part;
  per-part presence for F1x0/F3x0 and low-density F1 is unclaimed.
  Fallback: read ``MPU_TYPER`` (and treat “no MPU” as a valid answer).
* **H7 cache behaviour** — no coherency, memory-attribute or
  clean/invalidate guidance, and no default MPU attribute table.  The
  cache **geometry is absent too**: no datasheet or user manual states
  the I/D-cache size, associativity or line length (the only cache
  registers documented are the ``SYSCFG_CPUICAC``/``CPUDCAC`` error
  status ones, whose fields are described as “provided by the CPU”), so
  the cache-line size that every clean/invalidate loop must step by can
  only come from the Arm core registers at runtime.
* **DMA reachability of TCM** (F405+, H7) — never stated; assumed
  unreachable for ordinary DMA channels until proven otherwise.
* **Errata sheets** for GD32H73x/75x (referenced twice by the manual)
  and for any other family — not in the reference set.
* **Core revisions / stepping** for every part — not documented, so
  errata cannot be applied by revision.
* **Flash wait-state tables** — not extracted for H7; needed per family.
* **F5 FPU precision**, **F3x0 MPU presence**, and the F502 SRAM and
  DMA channel-split contradictions (both reported as printed).
* **GD32W51x datasheet** — absent; no electrical limits for W515.
* **Wi-Fi host interface** — absent from the user manual chapter.
* The voltage-before-frequency ordering rule is documented **only** for
  H7 (in the manual, not the datasheet); for F5 it is undocumented.
* **Core identity of GD32F105/F107 and of GD32F130/F150** — the
  datasheets say Cortex-M3, other sources say Cortex-M4; nothing on disk
  settles it (see the caveat under “GD32F1” and “GD32F1x0”).  The core
  is read from ``CPUID`` at boot.

Documented revisions
====================

Revisions of the reference documents the entries above were read from —
recorded because several claims differ between revisions:

* F1: F101/F103/F105/F107 datasheets; ``GD32F10x`` user manual Rev 2.9.
* F1x0: F130/F150 datasheets; ``GD32F1x0`` user manual Rev 4.1 (Rev 4.0
  also on disk).
* F2: F205/F207 datasheets; ``GD32F20x`` user manual Rev 3.3.
* F30x: F303 Rev 3.3 (+ F303xB Rev 1.1, Rev 3.1), F305 Rev 3.1/3.0,
  F307 Rev 3.1; ``GD32F30x`` user manual Rev 3.4 (Rev 3.3 also on disk).
* F3x0: F310 Rev 2.2, F330 Rev 3.5, F350 Rev 3.3; ``GD32F3x0`` user
  manual Rev 3.2.
* F4xx: F403 Rev 3.3, F405 Rev 2.8, F407 Rev 3.0, F425 Rev 1.8,
  F427 Rev 1.9, F450 Rev 2.9, F470 Rev 2.2; ``GD32F4xx`` user manual
  Rev 3.4 (plus a separate F403 manual Rev 3.2).
* F5: F502/F503 Rev 0.9RC6 and F505 Rev 0.9RC5 (pre-release), F527
  Rev 1.8, F5HC Rev 1.0; ``GD32F50x`` user manual Rev 1.4, ``GD32F527xx``
  user manual Rev 1.4.
* H7: H737 Rev 2.0, H757 Rev 2.1, H759 Rev 2.3, H75E Rev 1.5;
  ``GD32H73x_75x`` user manual Rev 1.8 (covers H75E as well; Rev 1.6
  and a dedicated H75E Rev 1.3 manual also on disk).
* W5: ``GD32W51x_F5HC`` user manual Rev 2.1; **no W51x datasheet**.

Priority targets
================

*[settled]* The first parts to be brought up are **GD32F303**,
**GD32F330** and the **GD32H7 line** (H737 / H757 / H759 / H75E), with
H7 at the same priority as the two Cortex-M4 parts.  What the
combination is expected to prove, per ``doc/kernel-design.rst``:

* **Two GPIO/pin-mux generations at once.**  F303 is on the
  ``GPIOx_CTL0/CTL1`` + separate-AFIO side, F330 on the
  ``OMODE/OSPD/PUD/AFSEL`` + SYSCFG side, so the driver-splitting rule
  (“address-only difference shares, anything deeper splits”) is
  exercised immediately rather than assumed.
* **The weak-isolation end.**  F330 densities run 4–16 KiB SRAM — at or
  below the footprint baseline — and the F3x0 documents claim an FPU but
  **not** an MPU, so this is where the tiny-RAM profile and the
  “MPU absent → privilege level + logical isolation” path get their
  numbers.
* **The strong-features end.**  H7 is the only priority target with a
  write-back **D-cache**, with **TCM** the ordinary DMA channels are not
  documented to reach, with **ECC** SRAM, with a **DMAMUX/MDMA** request
  model instead of fixed channels, and with a **mandatory voltage
  before frequency** boot step.  Everything the design currently marks
  *[TODO]* about DMA-visible placement, cache maintenance, MPU region
  convergence and the NVIC priority fold therefore has to be answered
  for the first release, not deferred to a later chip.
* **The 600 MHz / 1 MiB corner** also inverts the sizing assumptions:
  page size, thread count and stack sizing that are constrained by 48
  KiB on F303 are unconstrained on H7, so the build configuration has
  to stay per-target rather than global.

GD32F303 profile
----------------

Verified against ``GD32F303xx`` datasheet Rev 3.3.

* Core: Cortex-M4, **Armv7-M**, 120 MHz; the core feature list
  explicitly claims both an **MPU** and a **single-precision FPU**, so
  this is the priority target on which an MPU can be assumed present
  (region count still read from ``MPU_TYPER``).
* Map: main flash ``0x0800_0000`` – ``0x082F_FFFF`` (up to 3072 KiB),
  SRAM ``0x2000_0000`` – ``0x2001_7FFF`` (96 KiB maximum; densities
  print 48/48/64/96 and 48/64/96/96 KiB across the two package groups),
  and a ``0x0000_0000`` – ``0x0001_FFFF`` window **aliased to main
  flash or to the bootloader** depending on boot mode — an alias the
  linker map has to know about, not just a second name for flash.
* DMA: ``DMA0`` 7 channels + ``DMA1`` 5 channels, fixed request
  mapping, no mux and no FIFO.
* Pin mux: **AFIO remap generation** (``GPIOx_CTL0/CTL1`` plus the
  separate AFIO block).  The ports sit on **APB2** — ``AFIO``
  ``0x4001_0000``, ``EXTI`` ``0x4001_0400``, ``GPIOA`` ``0x4001_0800``
  … ``GPIOG`` ``0x4001_2000``, ``USART0`` ``0x4001_3800``, ``FMC``
  ``0x4002_2000`` — whereas the F330 moved its ports to **AHB2** at
  ``0x4800_xxxx``.  Bus, base, register layout *and* the muxing owner
  all differ, which is exactly the “deeper than an address difference”
  case.
* EXMC exists only on the 80/112-GPIO columns — the 37/51-GPIO columns
  print ``EXMC 0`` — and **never with SDRAM**.
* Communication/timer set the drivers have to cover: up to 3 SPI +
  2 I2S, 2 I2C, 3 USART + 2 UART, 1 CAN, USBD, SDIO, 3 ADC units (12-bit)
  with up to 21 channels, 1 DAC, 10 general 16-bit + 2 advanced + 2
  basic timers, up to 112 GPIO.

GD32F330 profile
----------------

Verified against ``GD32F330xx`` datasheet Rev 3.5.

* Core: Cortex-M4, Armv7-M, **84 MHz**; the core feature list claims an
  **FPU**, DSP instructions, NVIC and a 24-bit SysTick — and **no MPU
  bullet**, the documentation gap already recorded under “Absent from
  the documents”.
* Map: flash ``0x0800_0000`` – ``0x0801_FFFF`` (128 KiB maximum), SRAM
  ``0x2000_0000`` – ``0x2000_3FFF`` (16 KiB maximum; the per-part table
  prints 4 / 8 / 16 KiB).  These are the numbers that set the
  tiny-RAM profile.
* Peripheral bases (all of them, since the map is small): ``DMA``
  ``0x4002_0000``, ``RCU`` ``0x4002_1000``, ``FMC`` ``0x4002_2000``,
  ``CRC`` ``0x4002_3000``, ``SYSCFG`` ``0x4001_0000``, ``EXTI``
  ``0x4001_0400``, ``ADC`` ``0x4001_2400``, ``TIMER0`` ``0x4001_2C00``,
  ``SPI0`` ``0x4001_3000``, ``USART0`` ``0x4001_3800``, ``TIMER14/15/16``
  ``0x4001_4000`` – ``0x4001_4BFF``, ``PMU`` ``0x4000_7000``, ``CTC``
  ``0x4000_C800``; **GPIO on AHB2** at ``0x4800_0000`` –
  ``0x4800_17FF`` (ports A, B, C, D, F only).
* DMA: **one 7-channel controller**, fixed request mapping, no EXMC,
  no USB, no CAN, no Ethernet, no DAC.
* Densities (part-table): code area 16/32/64 KiB, with ``CBT6``/``RBT6``
  reaching 128 KiB total by adding a 64 KiB **data area** — a second,
  separately erased flash region the page allocator and the linker map
  must treat as its own area, not as extra text space; GPIO 15 (TSSOP20)
  to 55 (LQFP64); EXTI 12–16 lines; ADC 1 unit with 9/10/16 external +
  3 internal channels; 1–2 USART, 1–2 I2C, 1–2 SPI; 1 32-bit + 4–5
  16-bit general + 1 advanced timer; 2 watchdogs; RTC.
* Documentation oddity worth knowing before writing a driver: the
  F330 part-feature tables have **no DMA row at all** — the channel
  count only appears in the prose of section 3.7.

GD32H7 profile
--------------

Verified against the H737 Rev 2.0, H757 Rev 2.1, H759 Rev 2.3 and H75E
Rev 2.0 datasheets.

* Core: Cortex-M7, **Armv7-M**, 600 MHz; the core feature list claims an
  **MPU** and a **double-precision FPU**.  I- and D-cache are present in
  the block diagram but **their geometry is not documented** (see
  “Absent from the documents”), so cache-line size and default region
  attributes come from the Arm core registers at runtime.
* Memory: **1024 KiB SRAM on every H7 density** — 512 KiB AXI SRAM at
  ``0x2400_0000`` – ``0x2407_FFFF``, plus a 512 KiB pool
  re-partitionable into ITCM / D0TCM / D1TCM / AXI (DTCM slices in
  ``0x2000_0000`` – ``0x2001_FFFF``, ITCM its own ``0x0001_xxxx``
  window), SRAM0 and SRAM1 16 KiB each at ``0x3000_0000`` and
  ``0x3000_4000``, and 4 KiB backup SRAM at ``0x3880_0000``.
  ECC is monitored per region (``RAMECCMU`` blocks at ``0x5200_9000``
  and ``0x4802_3000``).  Flash 1024 / 2048 / 3840 KiB by density letter
  (``G``/``I``/``M``), 960 × 4 KiB sectors plus a 64 KiB information
  block; H75E is 3840 KiB only.
* DMA: ``DMA0``/``DMA1`` 8 channels each feeding a **DMAMUX**
  (``0x4002_0800``: 16 request-router channels, ``MUXID``, 8 request
  generators) **plus MDMA** (``0x5200_0000``: 16 channels) — the MDMA is
  the only master with a documented path into TCM.
* GPIO and pin mux: GD-style ``CTL/OMODE/OSPD/PUD/AFSEL`` on **AHB4**,
  ``GPIOA``–``GPIOK`` from ``0x5802_0000`` in 1 KiB steps; ``RCU``
  ``0x5802_4400``, ``CRC`` ``0x5802_4C00``, ``HWSEM`` ``0x5802_6400``.
  Up to 135 GPIOs, all mappable onto 16 EXTI lines (38 EXTI lines in
  total).
* Differences **inside** the H7 line, so a single “H7” device
  description is not enough: H737 advertises **three CANs where
  H757/H759/H75E advertise three CAN-FDs**; USB/ENET counts differ
  (H757: 1 USBHS + 1 ENET; H737/H759: 2 USBHS + 2 ENET; H75E: 1 USBFS +
  1 USBHS); and the timer counts depend on the density/package column
  (H737 ``V`` columns list 10 general 16-bit timers where ``Z``/``I``
  list 12).
* Power: 600 MHz with all peripherals enabled is documented around
  161 mA and with peripherals disabled around 47.5 mA (H757 table),
  which is the budget the idle/sleep policy (``doc/kernel-design.rst``
  open question 13) has to spend against; the PMU
  voltage-before-frequency step remains mandatory before raising the
  clock.

Driver-variant verdicts
-----------------------

Applying the splitting rules of ``doc/kernel-design.rst`` (“Driver model”)
to the facts above:

* **GPIO/pin muxing: three drivers, not one.**  F303 is the
  ``CTL0/CTL1`` + AFIO-remap shape, F330 the GD-style
  ``OMODE/OSPD/PUD/AFSEL`` + SYSCFG shape, H7 a register-compatible
  superset of the F4 shape on a different bus and with more ports.  None
  of these is an address-only difference, so no amount of device data
  collapses them.
* **Pin-mux device ownership differs per generation.**  On F303 the
  muxing registers live in a block *next to* the ports, so the GPIO
  driver exposes both port devices and pin-mux devices; on F330 and H7
  AF selection sits inside the port block and only the EXTI source
  select is in SYSCFG.
* **Fixed-channel DMA: F303 and F330 share one driver.**  Same register
  layout and same programming model; base address, controller count,
  channel count and the request enumeration are device data.  H7 needs
  its **own DMAMUX driver** plus a separate **MDMA driver**, and the
  request-to-channel binding is a runtime configuration there rather
  than a constant table.
* **RCU/PMU: one driver per series, plus a PMU driver with teeth on
  H7.**  The clock trees are not the same IP across F30x / F3x0 / H7, and
  on H7 the voltage setting is part of the required boot sequence.
* **NVIC: shared.**  All three expose 4 priority bits, so the priority
  fold (open question 21) is one table for the whole priority set, not
  three.

* *[TODO]* exact part numbers and densities per target (``F303VB``-class
  vs ``F303RE``-class, which F330 density, which H7 package — package
  matters because it gates EXMC SDRAM, ENET count and GPIO ports), and
  their ``mem.h`` / linker maps.
* *[TODO]* bring-up checklist per target, and how a part's data (base
  addresses, vector numbers, DMA request codes, package-gated blocks)
  is expressed once tdtsi/tdts resumes.
