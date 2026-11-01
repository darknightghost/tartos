=============
Kernel Design
=============

Design document for the tartos kernel.  Machine-readable interface
contracts live in the DSL (see ``dsl/README.rst``); this document records
the architecture and the rationale behind it.

Status legend: *[settled]* decided; *[draft]* written, open to change;
*[TODO]* undecided — contributor input required.

Overview
========

* tartos is an embedded RTOS for MCU-class targets (ARM Cortex-M class,
  e.g. GigaDevice GD32; see ``doc/supported-hardware.rst``). *[draft]*
* The kernel sources live in ``kernel/`` (GPLv3); the application-facing
  interface library lives in ``lib/`` (LGPLv3), so kernel-adjacent code and
  application linkage stay license-separated. *[settled]*
* Drivers communicate with each other and with the kernel through the
  driver-IPC interface, described by ``.tiface`` DSL sources and compiled
  to C++ and Rust definitions. *[settled]*
* Language split: **C++26** for core kernel code, **Rust 1.99.1
  (edition 2024) for drivers** and for the Rust interface of ``lib/``,
  Python 3.14 for the DSL tooling.  Kernel C++ runs without exceptions
  and RTTI. *[settled]*
* Scale and shape: single-core implementation (multi-core-ready design)
  on MCUs with **16 KiB SRAM or more** as the baseline, user program
  being one non-exiting process started by the kernel from an ELF image
  in flash. *[settled]*
* First targets *[settled]*: **GD32F303**, **GD32F330** and the
  **GD32H7 line (H737 / H757 / H759 / H75E)** — H7 has the same
  priority as the two Cortex-M4 parts, it is not a later stretch goal.
  The F3 pair was chosen across the two GPIO/pin-mux generations
  (F303 = ``CTL0/CTL1`` + AFIO remap, F330 = ``OMODE/PUD/AFSEL`` +
  SYSCFG), so the driver-splitting rules are exercised by the very first
  bring-up instead of being discovered later; most F330 densities sit
  **below** the 16 KiB baseline (4–16 KiB SRAM) and the F3x0 line does
  not document an MPU, which also covers the tiny-RAM profile and the
  “no MPU → privilege + logical isolation” degradation path.
  H7 deliberately pulls the opposite extremes into the same first
  round: 600 MHz Cortex-M7 with **instruction and data caches whose
  size, associativity and line length GigaDevice never states**, a
  re-partitionable **TCM** pool that the ordinary DMA channels are not
  documented to reach, **ECC** SRAM, a **DMAMUX + MDMA** programming
  model, a mandatory **PMU voltage-before-frequency** boot step, and
  1 MiB of SRAM.  Consequence: “Constraints” items *DMA-visible memory
  placement*, *Cache and DMA*, *MPU region layout* convergence, the
  NVIC priority fold (open question 21) and the boot power sequencing
  are **first-bring-up questions, not deferred ones**.  Per-part facts:
  ``doc/supported-hardware.rst``.

Architecture
============

Kernel type
-----------

* tartos is a **monolithic kernel**: kernel and driver code run in one
  image; driver-IPC serves driver-to-driver and application-to-kernel
  collaboration at process level. *[settled]*

Privilege and memory isolation
------------------------------

* *[settled]* Exactly **two privilege levels: kernel and user**; no
  intermediate levels are used.

* User space and kernel space are always logically separated; the
  enforcement mechanism degrades by hardware capability, in order of
  preference: *[settled]*

  #. **Privilege levels** — when the core provides them (MSP/PSP +
     Handler/Thread mode on Cortex-M, or equivalent), the kernel runs
     privileged and user tasks run unprivileged.
  #. **MPU** — when no usable privilege split exists but an MPU is
     present, region permissions enforce the user/kernel boundary.
  #. **Logical isolation** — on targets with neither, the boundary is
     enforced by convention and checked at build/review time; the
     separation must still be structurally present in the code.

* User code can never access kernel memory; kernel memory is outside the
  user-accessible map by every enforcement mechanism above. *[settled]*
* Peripheral register space (memory-mapped addresses) is mapped into
  **kernel memory only**; user programs reach hardware exclusively through
  system calls into the owning driver. *[settled]*
* **TrustZone extensions are out of scope** *[settled]*: the two
  TrustZone-capable lines in the target set (GD32F5HC, GD32W51x) are
  built with ``TZEN`` de-activated, so the core runs in a single
  security state and kernel/user stays the only isolation axis.
  Secure/non-secure is orthogonal to kernel/user — a third dimension
  the design does not model (it would multiply the MPU region budget,
  bind every interrupt and DMA channel to a security state and gate
  peripheral clocks through TZPCU).  Enabling it later is a design
  change, not a configuration option; the per-part constraints are in
  ``doc/supported-hardware.rst``.

Threading model
---------------

* **Single process, multiple threads**: user programs run as threads of
  one user process; there is no user-side process separation. *[settled]*
* **Single-core implementation, multi-core-ready design** *[settled]*:
  only one core is brought up for now, but no design may assume it.
  Scheduler state, run queues, per-thread kernel stacks and the
  interrupt stack must live behind a CPU index (per-CPU structures),
  spinlocks must stay valid once a second core exists, and nothing may
  rely on "there is only one core" for correctness.  Adding a second
  core is a later, non-structural change.
* No memory isolation between user threads — they share the user address
  space; isolation exists only between user space and kernel space. *[settled]*
* Stacks: *[settled]*

  - A **user thread** owns two stacks: its own **kernel stack** (used
    while executing in the kernel on that thread's behalf) and its own
    **user stack**.
  - A **kernel thread** owns only its own **kernel stack**.
  - The **interrupt stack**: one dedicated stack per core (taken via
    the MSP on exception entry).  Every part in the current target set
    is single-core, so in practice there is exactly one; the
    "otherwise run interrupts on the current thread's kernel stack"
    fallback is for cores with no separate privileged stack and is
    dead code for every target in scope.  Allocated in whole **pages**
    of the page allocator. *[settled]*
* Stack sizes: *[settled]* thread stacks — including each user thread's
  user stack — take their size from the **creation-time parameter** of
  the thread-creation API.
* Thread lifecycle: *[settled]* threads are created **dynamically**,
  carry a **name**, and their **priority is adjustable at runtime**.
* Tasks: *[deferred]* exact task/thread API shape and thread-count
  limit — postponed; the skeleton/framework is built first, the API is
  designed against real call sites.
* Scheduling policy: *[settled]*

  - **Real-time threads**: priority scheduling.  A thread is
    real-time when its priority is **above a configured level**
    (threshold: the RT band boundary, see “Priority scheme” below).
  - **Non-real-time threads**: round-robin time slicing.
  - When no thread is runnable, the scheduler runs the **idle
    thread**, which is thread **0**.
* Interrupt handling: *[settled]* **threaded interrupts** — the
  interrupt handler does nothing but (1) set the flag and wake the
  corresponding handler thread, then (2) invoke the scheduler.  The
  SysTick handler additionally updates the system **tick counter**.
  (Stack selection rule is settled, see “Stacks” above.)

Priority scheme
---------------

*[settled]* Thread priority is an **unsigned 8-bit** value — **lower
value = higher priority**:

=========== ============================== ==================================
Band        Range                          Policy
=========== ============================== ==================================
Real-time   ``0x00`` – ``0x20``            fixed priority, **FIFO** within
                                           an equal level (no slicing)
Non-RT      ``0x21`` – ``0xEF``            **round-robin time slicing**
Idle band   ``0xF0`` – ``0xFE``            scheduled (round-robin) only when
                                           no thread above ``0xEF`` is
                                           runnable
IDLE        ``0xFF``                       reserved for the idle thread
                                           (thread 0); runs only when
                                           nothing else is runnable
=========== ============================== ==================================

Real-time sub-bands (within ``0x00``–``0x20``) *[settled]*:

* ``0x00`` — reserved exclusively for the **exception-handler
  thread** (thread 1).
* ``0x01`` – ``0x10`` — **kernel threads only** (drivers and other
  in-kernel service threads).
* ``0x11`` – ``0x20`` — general real-time threads, usable by **both
  kernel and user threads**; **the whole range is available to user
  threads**.  The API restriction on user threads is exactly this
  band boundary: a user-side request (at creation or on runtime
  priority change) is rejected below ``0x11``, i.e. from ``0x01``
  (``0x00`` being the exception thread's) up to ``0x10``.  The split
  is therefore enforced by the thread API's check, not by the
  scheduler.
* The RT threshold is the band boundary: the RT band ends at ``0x20``
  — priorities ≤ ``0x20`` are real-time threads.

**Mapping onto the hardware** *[TODO]*: no Cortex-M part in the target
set implements more than **4 priority bits — 16 NVIC levels** (checked
across GD32F1, F1x0, F2, F30x, F3x0, F4xx, F5, H7 and W51x; SysTick
carries the same width and HardFault is fixed at priority -1, i.e.
below every RT thread).  Thread priority is therefore a **software
concept**: the 256-level U8 scale lives in the scheduler and is never
written to a hardware register.  What remains to be decided is the fold
from the U8 scale onto the 16 hardware levels — for ``BASEPRI`` masking
during kernel critical sections and for the NVIC priorities of threaded
handlers — and the consequence that the priority-ceiling protocol
**saturates**: several thread priorities share one mask value, so
raising a ceiling can protect less than its nominal level.  The
scheduler's 33-level RT band and the 16-level hardware band must not be
confused in either the code or the reasoning.

Synchronization
---------------

* *[settled]* **Spinlocks carry a priority (priority-ceiling
  protocol).**  On acquire: if the acquiring thread's priority is
  **below** the lock's priority, it runs at the lock's ceiling until
  release, then reverts; if the thread's priority is **above** the
  lock's priority, acquisition triggers **panic** (usage error).
  *[TODO]* on hardware this ceiling is enforced by masking interrupts,
  and the mask has only 16 levels on every target (see “Priority
  scheme”): the ceiling→``BASEPRI`` mapping and the resulting
  over/under-protection must be decided together with that fold.
* *[settled]* **Mutexes are forbidden in real-time threads.**
* *[settled]* **Blocking primitives exist** — the kernel provides the
  usual waiting objects (semaphore, condition variable, event, message
  queue) on top of the priority scheme, not only spinlocks and mutexes.
  *[deferred]* which system calls expose them to user threads — the API
  is postponed together with the thread API (Open questions, item 1).

Timekeeping
-----------

*[settled]* Time is split across two subsystems:

* **clock** — owns the tick: the SysTick handler maintains the system
  tick counter and the **sleep timers** (kernel-internal relative-time
  deadlines used by the scheduler, driver timeouts and blocking waits).
* **date_time** — owns absolute time: the **UTC timestamp** and the
  **boot time** (wall-clock instant of the last start).
* ``gettimeofday`` is **not** a kernel service: it is assembled in the
  application layer (``lib/``) from the values the two subsystems
  expose.  *[draft]* how user code reads them (syscall number(s) and
  structure layout) follows the deferred syscall API above.
* *[TODO]* interaction with power modes (does the idle thread enter
  sleep / ``WFI``, is the tick kept during sleep, tickless idle).

System-call entry
-----------------

*[settled]*

* Cortex-M has **no dedicated system-call instruction**: every target in
  scope (Armv7-M: F1/F1x0/F2/F30x/F3x0/F4xx/H7; Armv8-M Mainline:
  F5/W51x) enters the kernel through ``SVC``, with the call number and
  arguments carried in the argument registers.  A hardware
  ``syscall``-class instruction is used only if a future target
  actually provides one.
* The handler dispatches on the **call number** through the kernel-side
  **syscall table** and jumps to the mapped implementation.
* Arguments and the return value follow the platform **C calling
  convention**; what exactly is returned is **per-syscall**. *[settled]*

*[settled]* No — the syscall table is written directly in C++; the DSL
does not generate it.

* Device surface *[draft]*: the user-facing path to hardware is
  ``open_device`` (by device path) followed by ``ioctl`` on the
  returned handle; both are ordinary entries in the hand-written
  syscall table (see “Driver model”).
* Ownership wrappers are **not** passed through a system call — a trap
  boundary cannot carry a C++/Rust destructor.  Syscall parameters are
  therefore **annotated individually per call** (direction and
  validity: which side reads/writes, how long the referenced memory
  must stay valid) in the declaration's Doxygen ``@param`` block,
  instead of being typed as owning wrappers.  The borrow convention of
  “Resource ownership” keeps its meaning for the **interfaces** that
  kernel threads and drivers use inside the kernel, and for the
  generated ``.tiface`` code. *[settled]*

Memory management
-----------------

* *[settled]* Boundary content is fixed by “Privilege and memory
  isolation”: kernel memory and MMIO are never user-accessible; user
  threads share one address space with no inter-thread isolation.

Two-layer allocator
-------------------

*[settled]* The allocator has two layers: a page allocator at the bottom
and stack/heap allocators on top.

**Layer 1 — page allocator.**  The address space is split into pages
according to **configuration**: the page size is a build-time choice
bounded by the real memory of the target.  The **MPU does not shape the
layout** — it only enforces protection over whatever layout the
configuration and linker map define; region granularity constrains how
protection can be expressed, never where a region sits.
Page categories:

* kernel free pages / user free pages — neither readable nor writable
  while free; become read/write once allocated; free and allocated pages
  convert back and forth at runtime.
* kernel read-only pages / user read-only pages.
* kernel code pages / user code pages — readable and executable,
  **writes forbidden**; when MPU regions are insufficient, read-only
  pages are merged into the code pages.
* kernel reserved pages — DMA reservation memory and device register
  addresses; read/write from boot.  The DMA reservation part must sit in
  memory the target's DMA controllers can actually reach, which is a
  property of the platform map, not of this allocator (see “Constraints”
  and ``doc/supported-hardware.rst``).  A further flash-side reservation
  holds the **user program image** (see “User program image”); it is
  read-only to the kernel and is the user code region for execution.

**Layer 2 — stack allocator.**  Carves per-thread stacks out of the stack
area.  Implemented in kernel mode for both kernel and user threads.
Sizing rules *[settled]*: thread stacks (user and kernel) use the size
passed at thread creation; the interrupt stack is allocated in whole
**pages** (page size — a configuration choice, not an MPU limit) of the
page allocator.

**Layer 2 — heap allocator.**  The kernel implements only the kernel
heap allocator; the user heap is implemented by the userspace interface
library (``lib/``, LGPLv3).

**Grow/shrink policy** *[settled]*: the page allocator owns no growth
policy of its own.  Growing or shrinking the stack and data areas is
decided by the layer above — the stack allocator requests/releases pages
as thread stacks move, the heap allocator does the same for the heap —
and the page allocator only services those requests against the page
categories above.

Address-space layout
--------------------

*[settled]* With stacks growing downward, in each address space (kernel
and user alike) the allocatable memory spans from the **start of the data
area** (lowest address) to the **start of the stack area** (highest
address); the two regions grow towards each other.  Within the data area,
static data starts at the base address and the heap area follows it.

MPU region layout
-----------------

*[settled]* — with the MPU as the second-priority mechanism (privilege
levels are the first), the **target** region set is the nine regions
below.  The hardware ceiling is lower: GigaDevice's manuals never state
a region count — they defer to the Arm core description — so the limit
is the core's: **8 regions** on Cortex-M3/M4/M7 and 8 per security state
on Cortex-M33.  Region 1 (reserved: DMA memory **plus all device
registers**) has to be planned explicitly, because MMIO is spread over
several AHB windows on the bigger parts.  The set therefore converges
at boot to the count the part reports in ``MPU_TYPER``, applying the
merge rules below, and the parts with no MPU at all skip this section.

+----+------------------------+--------------------------------------+
| #  | Region                 | Access                               |
+====+========================+======================================+
| 1  | Reserved (kernel)      | kernel read/write — DMA reservation  |
|    |                        | memory and device registers          |
+----+------------------------+--------------------------------------+
| 2  | Kernel stack           | kernel stack area                    |
+----+------------------------+--------------------------------------+
| 3  | Kernel heap            | kernel heap area                     |
+----+------------------------+--------------------------------------+
| 4  | User stack             | user stack area                      |
+----+------------------------+--------------------------------------+
| 5  | User heap              | user heap area                       |
+----+------------------------+--------------------------------------+
| 6  | Kernel read-only       | kernel RO data                       |
+----+------------------------+--------------------------------------+
| 7  | User read-only         | user RO data                         |
+----+------------------------+--------------------------------------+
| 8  | Kernel code            | read + execute, writes forbidden     |
+----+------------------------+--------------------------------------+
| 9  | User code              | read + execute, writes forbidden     |
+----+------------------------+--------------------------------------+

* Code regions **forbid writes**.
* When region count is insufficient, **read-only regions merge into
  the code regions** (consistent with the page-category merge rule in
  “Two-layer allocator”).  On an 8-region core this merge is the
  **normal path, not the fallback**; where even that does not fit, the
  next merges are kernel heap+kernel stack into one read/write region
  and user heap+user stack into one read/write region (both grow
  towards each other anyway, see “Address-space layout”).  The exact
  converged table per part is *[TODO]* — it is fixed by ``mem.h`` /
  ``mpu_regions.h`` once a concrete chip is chosen.
* *[settled]* Unprivileged access: every region tagged **kernel** —
  reserved (1), kernel stack (2), kernel heap (3), kernel read-only (6)
  and kernel code (8) — is **inaccessible from user mode**; only the
  user regions (4, 5, 7, 9) are reachable at unprivileged level, with
  the attributes listed above.  The same rule holds on targets where
  isolation is enforced by privilege level alone.
* *[settled]* **Layout vs. protection.**  The address-space layout above
  is fixed by configuration and the linker map; the presence, absence or
  region granularity of an MPU changes **only how the boundary is
  protected**, never where regions sit or how pages are sized.  A target
  without an MPU therefore keeps the identical layout and degrades to
  privilege-level or logical enforcement.

Constraints
-----------

* *[settled]* **Memory footprint target.**  The baseline is a part with
  **16 KiB SRAM or more**; fitting smaller devices is a design goal
  rather than a hard requirement, so the static footprint must stay
  tunable (thread count, page size, interrupt stack size, subsystem
  selection).  The parts below the baseline are real, not hypothetical
  — GD32F101 starts at 4 KiB and the F1x0/F3x0 lines run 4–16 KiB — so
  a **tiny-RAM profile** has to be an explicit configuration.  The
  naive sizing shows why: eight threads at a 512 B stack each already
  consume 4 KiB, the whole SRAM of the smallest parts.  *[TODO]* that
  profile's numbers (minimum thread count, smallest usable page,
  static kernel ceiling).
* *[TODO]* **External RAM is gated per series** — “in scope” cannot be a
  blanket claim.  EXMC appears only on some parts and some packages
  (GD32F1: 100/144-pin parts only; GD32F2: SDRAM on ``Z`` packages;
  F3x0: no EXMC at all; F405/F425: no EXMC; F403: EXMC without SDRAM;
  F502/F5HC: no EXMC), and the newer lines attach expansion memory or
  external code over **QSPI / OSPI / SQPI** instead — XIP-capable, with
  its own cache interaction.  Which bus, the region it occupies and
  whether the page allocator treats it exactly like internal SRAM stay
  open; the per-part facts are in ``doc/supported-hardware.rst``.
* *[settled]* Thread-local storage is forbidden in kernel code.  User
  code may use it; TLS variables are placed at the start of the owning
  user stack.
* *[settled]* **Floating point is forbidden in kernel code** — no FPU
  use, no floating-point ABI in kernel paths, so no lazy-stacking or
  FP-save concerns on the kernel side.  User threads **may** use
  floating point; the kernel saves/restores the FP register context
  with their thread state.
* *[settled]* **FPU presence is probed, never assumed.**  The target
  set mixes parts with no FPU at all (GD32F1, F1x0, F2 — soft-float
  only), single-precision parts (the Armv7-M Cortex-M4 parts: F30x,
  F3x0, F4xx), double-precision parts (GD32H7) and families whose
  datasheets claim an FPU without stating its precision (F5, W51x).
  The kernel therefore reads the presence and depth of the FP unit at
  boot (``CPUID``/``CPACR``) and sizes the user thread context
  accordingly, instead of compiling the FP context in or out per
  family.  The architectural register file alone is 32 × 32-bit
  (16 × 64-bit of the same storage when double precision is used) plus
  ``FPSCR``, which on the smallest priority target (GD32F330 densities
  with **4 KiB** SRAM, whose datasheet claims an FPU) is a material
  fraction of RAM per user thread.  *[TODO]* whether the tiny-RAM
  profile may compile the FP context out **even where the unit is
  present**, as a configuration choice rather than a hardware fact.
* *[TODO]* **DMA-visible memory placement is a hard constraint, not a
  hint.**  On the parts with TCM (GD32F405 and later, GD32H7) the
  tightly-coupled RAM is connected to the core and plain DMA channels
  are not documented to reach it (H7 offers MDMA with an extra AHB port
  and burst restrictions; F4 has IPA rather than MDMA).  The kernel
  reserved DMA pages must therefore be pinned to a DMA-reachable region
  by the per-platform linker map — the region lists live in
  ``doc/supported-hardware.rst``.
* *[TODO]* **Cache and DMA.**  Only GD32H7 (instruction + data cache,
  geometry **not documented** by the vendor — read it from the CPU at
  boot) and GD32F5HC/W51x (32 KiB instruction cache, 2-way, 16-byte
  lines, no write-back D-cache) have caches; every other target is
  uncached.  The H7
  manuals give **no cache-maintenance or memory-attribute guidance at
  all**, so the write-back case must be driven from the Arm core
  documentation: DMA buffers need an explicitly non-cacheable mapping
  or clean/invalidate around each transfer, decided per platform, and
  loaded or XIP code needs an instruction-cache invalidate.  The policy
  is settled (“the provider owns coherency”, see “Driver model”); the
  mechanism is not.
* *[settled]* **Memory exhaustion is an error, not a fault.**  When the
  page, stack or heap allocator cannot satisfy a request it returns an
  error (``NULL`` / negative status) and never panics; the caller
  decides.  Consequently ``new`` in kernel code uses the non-throwing
  form and every allocation site checks its result.
* *[settled]* **Language subset.**  Kernel C++: exceptions and RTTI are
  forbidden (``-fno-exceptions -fno-rtti``); `new`/delete and static
  initialization with global constructors **are** allowed — with
  global-constructor order tied to the boot phases below.  **Drivers are
  written in Rust**; the userspace library (``lib/``) **supports Rust**
  bindings/interface as well as C++.  *[TODO]* the Rust side's details:
  ``no_std`` crate layout, panic strategy and its hook into the kernel
  panic path, FFI boundary rules with C++, and which toolchain profile
  each target uses.

Resource ownership
------------------

*[settled]* Kernel resources (memory blocks, driver-IPC buffers, device
handles, queue slots — anything the allocator hands out) do **not**
follow “whoever requested it releases it”.  Two separate concerns are
kept apart:

* **Release policy belongs to the allocator.**  The component that
  *owns* the resource pool decides how and when a resource goes back —
  the consumer has no say in the free path and never frees another
  component's resource.
* **Lifetime is expressed by ownership kind, following Rust
  semantics.**  Every handed-out resource is passed under one of three
  explicitly labeled kinds, which decide who may extend the lifetime:

  - **single** — ``Box`` / owned value with move semantics.  One owner
    for the whole lifetime; assigning or passing the resource *moves*
    ownership and the release obligation with it.
  - **shared** — ``Rc`` / ``Arc``.  Any number of holders; the lifetime
    ends when the last strong reference is dropped.
  - **borrow** — ``&T`` / ``&mut T``.  A temporary view valid only while
    the owner keeps the resource alive.  Exactly the Rust aliasing rule:
    shared borrows coexist, a mutable borrow excludes every other access
    for its whole extent, and a borrow never outlives its owner.  A
    borrower may neither store nor release what it borrowed.
* **Type-level encoding** *[settled]*: a raw pointer or a reference
  that appears **without** an ownership wrapper always means a borrow —
  the kernel never expresses ownership with ``T *`` / ``T &``.  The
  exceptions are very low-level code
  (allocator internals, page/MPU table setup, startup glue) where no
  alternative exists, and the **system-call boundary**, where a wrapper
  cannot be passed at all (see “System-call entry”); every such site
  says so in a comment.
  Ownership is expressed exclusively by the **cross-language wrapper
  types**, named in the DSL and used consistently in C++ and Rust:

  - ``Unique<T>`` — single ownership; ``Box<T>`` in Rust, a move-only
    handle in C++ (no copy; assignment transfers the release
    obligation).
  - ``Shared<T>`` — shared ownership; ``Arc<T>`` in Rust, an intrusive
    reference-counted handle in C++ (the lifetime ends with the last
    strong reference).
  - a bare ``T*`` / ``T&`` — borrow, per the rule above.

  ``Unique`` / ``Shared`` / “pointer means borrow” are the settled names
  and meanings; the exact C++ type definitions and their Rust mirrors are
  still to be written.  The DSL type system carries ``Unique<T>`` and
  ``Shared<T>`` directly, so hand-written kernel code, ``lib/`` and
  generated ``.tiface`` interfaces share one vocabulary (see
  ``dsl/README.rst``).
  Where the borrow checker cannot be reproduced (lifetimes are not
  expressible in C++), the rule is documented at the boundary as a
  ``@note`` caller obligation and checked in debug builds.  *[TODO]* the
  debug-build checks and the concrete C++/Rust rendering of each wrapper.
* *[TODO]* Which of the three each driver-IPC buffer direction
  (request payload, completion payload, shared-memory zero-copy buffer)
  uses; zero-copy vs copy per payload.

Driver model
------------

* **Driver and device are two separate objects** *[settled]*:

  - A **driver** is a kernel module — code only, **written in Rust**.
    It carries no per-instance state beyond what the devices bound to
    it own.
  - A **device** is the management object for a piece of hardware
    (a peripheral instance: register base, interrupt line, DMA
    channel, configuration).  Devices are the things that come and
    go at runtime; drivers do not.

* **Driver splitting rules** *[settled]*:

  - **Split by function inside one MCU.**  Pin assignment, GPIO,
    timers, USART/UART and so on are *separate drivers* — a driver owns
    one kind of function, not one chip's whole peripheral block.
  - **One driver may expose two device kinds when the hardware binds
    them tightly.**  Where pin multiplexing cannot be configured
    sensibly apart from the pin's electrical state — e.g. the AFIO
    remap registers sitting next to the GPIO port configuration, or the
    AF-selection registers living inside the GPIO block — the GPIO
    driver provides both the port devices and the pin-muxing devices.
    The coupling is decided by the hardware, not by taste.
  - **Same device, address-only difference → one shared driver.**  When
    two MCUs expose the same peripheral with an identical register
    layout and operating logic and differ only in the base address at
    which it is mapped, the driver is shared and the difference is
    device data (register base, interrupt number, DMA request routing).
  - **Anything deeper than an address difference → separate drivers.**
    Different register layout, different bit meanings, different
    programming sequence, different capability, or an erratum that
    changes required sequencing all mean a distinct driver.  Sharing is
    only ever about identical logic.

  Consequence: a driver is a **function × register-layout family**, and
  the device instance carries the per-part coordinates (base address,
  IRQ, request mapping).  Whether a given part instantiates the shared
  driver or a variant driver is decided from the chip description
  (tdtsi), see “Device description” below.  Applying this rule to the
  GD32 line produces the split recorded in
  ``doc/supported-hardware.rst`` (“Differences and their driver
  impact”): two incompatible GPIO/pin-mux families, four incompatible
  DMA architectures, one RCU driver per series, and peripheral driver
  forks wherever a FIFO, a request mux, CAN FD or a different
  programming sequence appeared — **none of those differences is
  address-only**.

* Driver module set: *[settled]* a driver is **linked into the kernel
  image** — dynamic loading of driver code is not supported and not
  planned.  The set of drivers present in an image is fixed at
  **compile time from the board description (tdts)**; there is no
  runtime probe and no dynamic registration table for driver code.
  Once initialized, a driver lives for the **entire lifetime of the
  kernel** (no unload, no hot restart).  Initialization order and
  dependencies between driver modules are derived from the device tree.
* Device lifecycle: *[settled]* devices are created **and destroyed
  dynamically** at runtime; drivers never come and go.
* Device initializers: *[settled]* device creation is not owned by a
  single component.  Any number of **device initializers** may create
  and manage devices through the same device API — e.g. the **tdts
  loader** (static board inventory, run during boot) and a **PnP
  manager** (bus-enumerated devices, run at any time).  *[TODO]* the
  common initializer interface, the device table/list and its locking,
  the driver↔device match/bind procedure, and teardown ordering (who
  must quiesce before a device is destroyed).
* Device addressing: *[settled]* a device is addressed by its
  **device path** — its position in the bus hierarchy, “device *n* on
  bus *x*” — not by a name assigned to it.  A caller resolves that path
  with ``open_device``, which returns a handle; every operation on the
  opened device then goes through **ioctl** on that handle.  *[TODO]*
  path syntax and encoding (string vs. packed bus/index tuple), handle
  type, the ioctl number/argument registry (which ``.tiface`` supplies
  per-interface commands and structures), and what happens to an open
  handle when the device behind it is destroyed (path stability across
  dynamic create/destroy).
* *[settled]* Drivers own MMIO access; all user-side hardware access goes
  through system calls dispatched to the owning driver.
* DMA ownership *[settled]*: the party that **ends up providing the DMA
  interface owns its coherency** — cache clean/invalidate, buffer
  alignment and the DMA-visible memory placement are that provider's
  duty, not the requester's.  A driver that hands out a DMA interface to
  another driver or to user code keeps that responsibility for the
  transfers it executes; a caller that runs its own DMA (e.g. a
  Scatter-Gather engine driver given a buffer) owns maintenance for it.
  Coherency is a **per-platform mechanism**, not a portable
  abstraction: whether the target is cached at all, which RAM a
  controller can reach and what maintenance a cached target needs all
  differ across the family (see the cache / TCM entries under
  “Constraints” and ``doc/supported-hardware.rst``).
  *[TODO]* the concrete API surface: which ``.tiface`` interface carries
  DMA, alignment/size constraints published to callers, and how user-side
  buffers are made DMA-coherent given that kernel memory is not user
  accessible.
* Driver-IPC: interface contracts are ``.tiface`` DSL files; generated
  definitions land in ``output/<isa>/<arch>/<platform>/include/`` (C++ app
  headers) and the kernel/lib build trees.  Message payloads are POD
  structs from the DSL type system; command/feature sets are compile-time
  constants/flags from the DSL. *[draft]*
* Interface pointers *[settled]*: every bare pointer in a generated
  ``.tiface`` interface is a **borrow** — the callee may not keep it or
  free what it points to.  Ownership that is meant to travel is written
  with ``Unique<T>`` / ``Shared<T>``, which the DSL type system carries
  directly (see “Resource ownership” and ``dsl/README.rst``).
  *[TODO]* For asynchronous requests the borrow must stay valid until
  the completion callback fires, so “duration of the call” is not the
  right extent: how an async buffer borrow is expressed and when the
  caller may recycle it.
* Call semantics *[settled]*: driver-to-driver read/write is **always
  asynchronous** — there is no blocking driver call.  Requests are
  submitted as asynchronous I/O and completed through **event
  callbacks** registered by the caller.
* *[TODO]* Queue depth and backpressure behavior when a driver's
  pending-request capacity is exhausted.
* *[TODO]* Delivery path of an asynchronous completion to a **user**
  thread: the callback runs in user context, so the kernel needs an
  upcall/notification mechanism (which syscall the caller waits on,
  how the callback thread is woken, reentrancy rules).
* Device description: *[TODO]* the paused tdtsi (chip) / tdts (board) DSL
  supplies the hardware inventory — i.e. the **devices** (peripheral
  instances and address maps) that the compile-time drivers are
  selected against and bound to at runtime.  Until that design lands,
  the exact device-creation input is undecided.

Boot and lifecycle
==================

User program image
------------------

*[settled]*

* The user program is an **ELF image**, flashed into the region of
  **flash reserved for the user** (see “Two-layer allocator”).  The
  kernel locates and reads it from flash; there is no file system, no
  loader stream and no runtime program installation.
* The user process/threads are **created by the kernel**.  *[TODO]*
  exact phase (after scheduler up, before or as part of driver init) and
  whether the ELF is copied to RAM or executed from flash.
* The user program is **not allowed to exit** — there is no exit syscall
  and no teardown path.  When it dies or panics it is **restarted**, and
  restart is carried out by the **exception-handler thread (thread 1)**,
  the same actor that owns the panic policy (see “Fault handling (panic
  policy)”).  Restart re-creates the user process from the flashed image.
* *[TODO]* restart accounting: how many restarts before the kernel
  escalates to a full restart, and whether restart state (stack content,
  device handles held by the dead process) is explicitly torn down.

Remaining open points
---------------------

* Boot phase order is drafted under “Framework skeleton (draft)”;
  *[TODO]* which component owns each phase and where board-specific
  bring-up comes from.
* Panic policy is settled (see “Fault handling (panic policy)”);
  *[TODO]* fault-handler ownership and the watchdog's role during
  restart.

Fault handling (panic policy)
=============================

Kernel panic *[settled]*:

* A panic is raised either **deliberately** (software trigger) or by
  an **exception interrupt**; the panic path runs on the **highest
  priority exception-handler thread — thread 1** (idle is thread 0).
* Detect whether a debugger is attached; if so, **hand control to the
  debugger**.  Debugger-presence detection is **platform-specific**
  (implemented per hardware target).
* Without a debugger: **restart** the system.

User-process panic *[settled]* — depends on the isolation available
(see “Privilege and memory isolation”):

* With **MPU/MMU privilege-mode isolation** in place: debugger
  attached → debugger takes over; otherwise **restart the user
  process** only.
* Without sufficient isolation: handle **as a kernel panic** (the
  fault cannot be contained away from kernel state).

*[TODO]* Watchdog role during restart; panic-time context capture on
the exception-handler thread.

Build configuration
===================

* Cross builds are parameterized by ``<isa>/<arch>/<platform>``; CMake
  toolchain files are selected at configure time (``cmake --toolchain`` or
  CMakePresets), never from ``CMakeLists.txt``. *[settled]*
* Generated artifacts follow the layout in ``AGENTS.md`` (build/…
  intermediate; output/…/{kernel,include,lib,doc}). *[settled]*
* *[settled]* Which ``.tiface`` files take part in a build depends on
  the **subsystems the configuration uses**, not on the platform string
  itself; the DSL run is **integrated into the CMake flow** (generated
  sources feed the kernel/lib/include trees as build outputs).

Framework skeleton (draft)
==========================

Proposed module and directory shape for the kernel tree — structure
only, no implementation yet, and no code written until this skeleton is
agreed.  *[draft]*

``kernel/`` layout
------------------

.. code-block:: text

    kernel/
      kernel.c                     entry: kernel_main() after early init
      include/kernel/
        types.h                    U8…U64, S8…S64, Size, SSize,
                                   IntPtr, UIntPtr
        boot.h                     boot-phase entry points
        thread.h                   TCB, thread states, priority scheme
                                   (U8 bands — settled; API deferred)
        sched.h                    enqueue/select/reswitch interface
                                   (API deferred)
        ipc.h                      driver-IPC endpoints: async request
                                   submission + event callbacks
        syscall.h                  syscall-table declaration, numbers
                                   (incl. open_device / ioctl)
        panic.h                    panic raise/handoff
        spinlock.h                 priority-ceiling spinlock
        device.h                   device objects (dynamic, per
                                   hardware instance) + driver↔device
                                   bind interface
        driver.h                   driver module descriptor
                                   (compile-time set, from tdts)
        sync.h                     mutex / semaphore / condvar / event /
                                   message queue (syscall surface deferred)
        time.h                     clock (tick, sleep timers) and
                                   date_time (UTC, boot time)
        user.h                     user image location, create / restart
        ownership.h                Unique<T>, Shared<T>, borrow types
                                   (see “Resource ownership”)
      thread/
        thread.c                   dynamic create, name, runtime
                                   priority change
        sched.c                    RT: fixed-priority; non-RT: RR time
                                   slice; idle = thread 0
      irq/
        irq.c                      threaded-interrupt bridge: flag set,
                                   wake handler thread, schedule
      ipc/
        ipc.c                      driver-IPC transport: async I/O,
                                   callback dispatch (queue depth TODO)
      device/
        device.c                   dynamic device create/destroy,
                                   device list, initializer API
                                   (bind/teardown policy TODO)
        driver.c                   driver table linked into the kernel
                                   image, fixed at compile time from
                                   tdts, init ordering
      syscall/
        syscall.c                  table dispatch by call number
      mm/
        page.c                     L1 page allocator: categories,
                                   free↔alloc conversion
        stack.c                    L2 stack allocator (thread stacks,
                                   interrupt stack)
        heap.c                     L2 kernel heap allocator
        mpu.c                      MPU region programming incl.
                                   RO→code merge fallback
      sync/
        spinlock.c                 ceiling protocol, panic on
                                   above-ceiling acquire
        blocking.c                 mutex, semaphore, condition variable,
                                   event, message queue
      time/
        clock.c                    tick counter, sleep timers
                                   (SysTick handler lives here)
        date_time.c                UTC timestamp, boot time
      user/
        image.c                    ELF from the user flash region:
                                   create, restart by thread 1
      driver/                      drivers are Rust crates linked into
                                   the kernel image, one directory per
                                   driver; no dynamic loading
        gd32_uart/
          Cargo.toml
          src/lib.rs
      panic/
        panic.c                    handoff to exception thread (1);
                                   debugger detect → takeover,
                                   else restart
      platform/
        arm/armv7-m/               Cortex-M3 / M4 / M7 — one directory
                                   per chip family below
          gd32f303/                first target (Cortex-M4, AFIO
                                   pin-mux generation)
            startup.S              vector table, Reset_Handler:
                                   .data/.bss setup → kernel_main
            mem.h                  linker symbols: region bounds,
                                   stack-area / data-area bases, and
                                   the DMA-reachable region list
            mpu_regions.h          target table of “MPU region
                                   layout”, converged to the count the
                                   core reports (M3/M4/M7 = 8)
            gd32f303.ld            linker script (memory map is a
                                   chip decision — TODO)
          gd32f330/                first target (Cortex-M4, GD-style
                                   SYSCFG pin-mux generation, much
                                   smaller RAM than the F303, and with
                                   MPU presence undocumented in its
                                   manual — the tiny-footprint end
                                   where isolation may degrade to
                                   privilege level only, see
                                   “Priority targets”)
          gd32h7xx/                first target (Cortex-M7 with
                                   I/D-cache, TCM, DMAMUX + MDMA,
                                   PMU voltage sequencing)
          <family>/                one such directory per part family
                                   whose map, cache or core differs
                                   materially
        arm/armv8-m-main/          same shape for the Armv8-M
                                   Mainline parts (GD32F5, W51x);
                                   platform dirs are per core
                                   generation because context
                                   save/restore and the FP state
                                   differ

Boot phase order (draft)
------------------------

#. Reset → ``startup.S``: vector table, SP setup, ``.data`` copy,
   ``.bss`` zero (platform code).
#. Early platform init: **power first, then clocks** — on parts where
   the core voltage and the clock frequency are coupled the voltage
   setting must be raised before the frequency and lowered after it,
   and some of those registers are writable only while the PLL is off
   (GD32H7 ``LDOVS``/SMPS sequencing; GD32F5 similarly), so the order
   ``voltage → PLL/clock tree → bus dividers`` is a hardware rule, not
   a style.  Then MPU region table and vector-table placement (kernel
   side).  *[TODO]* which of these belong to platform glue and which to
   the RCU/PMU drivers, given that drivers only initialize later, in
   phase 4.
#. Kernel core init: page allocator → stack allocator → **idle
   (thread 0)** and **exception handler (thread 1)** → scheduler up →
   clock (tick) up.
#. Driver init (compile-time set from tdts; order from the device
   tree).
#. Device creation — device initializers run and bind devices to
   their drivers.  The **tdts loader** is the boot-time initializer;
   other initializers (e.g. a PnP manager) may create and destroy
   devices at any later time.  (When each runs: TODO.)
#. Start the user program: the kernel loads the **ELF** from the
   user flash region and creates its threads (unprivileged).  It never
   exits; on death it is restarted by thread 1.

Corresponding build trees: ``build/arm/armv7-m/gd32f303/``,
``build/arm/armv7-m/gd32f330/`` and ``build/arm/armv7-m/gd32h7xx/``, each
with ``output/arm/armv7-m/<platform>/{kernel,include,lib,doc}/`` per
``AGENTS.md``.  Toolchain files are provided via ``cmake --toolchain``
/ CMakePresets (file location: to be added under ``cmake/`` when the
build skeleton lands).

Testing
=======

* Host-side tests (algorithms, DSL parsing) run from ``test/`` on the
  development machine. *[settled]*
* *[TODO]* On-target test/harness strategy.

Open questions (summary for the maintainer)
===========================================

Settled — record only, nothing to decide
==========================================

* **Syscall entry**: ``SVC`` on every target in scope (no Cortex-M part
  has a syscall-class instruction); dispatch by call number through a
  hand-written C++ table; arguments and results follow the platform C
  calling convention, per-syscall.
* **Scheduling**: fixed priority + FIFO for real-time threads,
  round-robin slicing above the RT band, idle band round-robin, idle =
  thread 0; threaded interrupts (ISR only flags, wakes the handler
  thread, triggers schedule); SysTick maintains the tick counter.
* **Priority scheme**: U8, lower = higher; RT ``0x00``–``0x20``
  (``0x00`` exception thread, ``0x01``–``0x10`` kernel-only,
  ``0x11``–``0x20`` kernel and user — the whole range open to user
  threads, with the API rejecting user requests below ``0x11``);
  non-RT ``0x21``–``0xEF`` RR; idle band ``0xF0``–``0xFE``; ``0xFF``
  = thread 0.  The scale is **software-only** — hardware offers 16
  NVIC levels at most on every target (fold: open question 21).
* **Locking**: priority-ceiling spinlocks (ceiling violation → panic);
  mutexes forbidden in RT threads; blocking objects exist.
* **Isolation**: two privilege levels, **TrustZone not modelled** (built
  with ``TZEN`` off on the parts that have it); kernel-side regions are
  never user-accessible; **the MPU changes protection only, the
  address-space layout is the same with or without it**; code regions
  forbid writes; RO merges into code whenever regions run short — which
  is the normal case, since no core in scope offers more than 8.
* **Allocator**: two layers; growth/shrink is decided by the upper
  (stack/heap) layer; page categories include kernel/user free, RO and
  code pages plus kernel reserved.
* **Ownership**: release is the allocator's duty, never the consumer's;
  lifetime typed as ``Unique<T>`` / ``Shared<T>`` / borrow, with Rust
  semantics; a bare pointer or reference always means a borrow.
* **Drivers vs. devices**: drivers are kernel modules linked into the
  image, fixed at compile time from tdts, alive for the kernel's whole
  lifetime; devices are separate dynamic objects created and destroyed
  by multiple initializers; devices are addressed by path →
  ``open_device`` → ioctl; driver-to-driver I/O is fully asynchronous
  with event-callback completion.
* **Resources**: memory exhaustion returns an error, never a panic; the
  party providing the DMA interface owns its coherency.
* **Threading surface**: single process with multiple threads, dynamic
  thread creation, runtime priority change, naming, creation-time stack
  sizes; single-core now, multi-core-ready.
* **Panic policy**: debugger takeover if a debugger is present, else
  restart; weakly isolated user panics escalate to the kernel path; the
  exception-handler thread (thread 1) runs the panic path.
* **Language constraints**: kernel C++ has no exceptions and no RTTI but
  allows ``new`` and global constructors; no floating point in the
  kernel, FP allowed for user threads; drivers in Rust, ``lib/``
  supports Rust.
* **User program**: ELF image flashed into the user-reserved flash
  region, created by the kernel, never allowed to exit; the
  exception-handler thread restarts it.
* **Build**: ``<isa>/<arch>/<platform>`` parameterization, toolchain
  files chosen at configure time, the DSL run driven by the subsystems a
  configuration uses and integrated into CMake.

Open questions
==============
1. **Thread API** *[deferred]*: exact shape of the thread-creation /
   priority / naming calls and the thread-count limit — postponed until the
   framework exists, then designed against real call sites.

2. **Syscall API surface** *[deferred]*: which system calls expose the
   blocking objects (semaphore, condition variable, event, message queue)
   and timekeeping (``clock`` tick/timer reads, ``date_time`` UTC and boot
   time) to user threads.

3. **Driver-IPC buffers**: which ownership kind each direction carries
   (request payload, completion payload, shared-memory buffer), and
   zero-copy vs. copy per payload.

4. **Queue depth and backpressure**: what happens when a driver's
   pending-request capacity is exhausted (reject, block, coalesce?).

5. **Async completion → user thread**: which syscall the caller waits
   on, how the callback thread is woken, reentrancy rules for completion
   callbacks, and the **borrow extent** of an asynchronous buffer (it must
   outlive the call until the callback fires — how that is expressed and
   when the caller may recycle the buffer).

6. **Device model**: the common device-initializer interface, the device
   table and its locking, the driver↔device match/bind procedure, and
   teardown ordering (who must quiesce before a device is destroyed).

7. **Device addressing details**: path syntax/encoding (string vs. packed
   bus/index), the handle type and its lifetime, the ioctl number/argument
   registry, and the fate of an open handle when the device behind it is
   destroyed (path stability across dynamic create/destroy).

8. **Ownership wrappers**: the concrete C++ definitions and their Rust
   mirrors, refcount and drop-order rules for the shared case, which
   low-level sites are exempted from the borrow-by-default rule, and
   whether ``Unique<T>`` carries its allocator (stateful deleter) so a drop
   returns the resource to the pool that owns it.  Also the debug-build
   checks that stand in for the borrow checker.

9. **Rust side**: ``no_std`` crate layout for drivers, the Rust panic
   strategy and how it hooks into the kernel panic path, FFI boundary rules
   against C++, and the per-target toolchain profile.

10. **DMA interface**: which ``.tiface`` carries DMA, the alignment and
    size constraints published to callers, and how user-side buffers are
    made DMA-coherent given that kernel memory is not user-accessible.

11. **Boot**: which component owns each boot phase, where board-specific
    bring-up comes from, per-platform debugger detection, the watchdog's
    role during restart, panic-time context capture, and where in the boot
    sequence the user image is created (copied to RAM vs. executed from
    flash).

12. **Restart accounting**: how many user-process restarts before the
    kernel escalates to a full restart, and whether state held by the dead
    process (stacks, device handles) is explicitly torn down.

13. **Power and idle**: whether the idle thread enters sleep/``WFI``,
    whether the tick survives sleep, and whether tickless idle is
    required.  Hardware context: every family documents Sleep and
    Deep-sleep (SRAM retained, clocks off — so SysTick stops and the
    tick must be recovered from the RTC) and Standby (core-domain SRAM
    lost, restart from address ``0x0000_0000``, i.e. a *boot*, not a
    resume).  A wake-from-standby restart therefore lands on the same
    path as a reset, which has to be reconciled with the user-image
    creation phase.

14. **User input validation**: how user pointers are checked before the
    kernel uses them (a ``copy_from_user``-style boundary, range checks
    against the user regions) — undecided.

15. **Logging and assertions**: kernel log/printk equivalent, ``assert``
    and ``BUG()`` policy, static-assert usage — undecided.

16. **Concrete part and density per target.**  The families and their
    maps are recorded in ``doc/supported-hardware.rst`` (“GD32F303
    profile”, “GD32F330 profile”, “GD32H7 profile”) — flash/SRAM bases,
    DMA shape, pin-mux generation and the F303 ↔ F330 ↔ H7
    driver-variant verdicts are settled.  Open: the exact part number
    and density per target (package matters — it gates EXMC, ENET count
    and GPIO ports), the resulting region sizes in ``mem.h`` and the
    ``.ld``, and the F330 “data area” as a separately erased flash
    region.

17. **External RAM**: expansion memory is **not one bus** across the
    target set — EXMC (part- and package-gated, SDRAM only on some),
    QSPI/OSPI/SQPI with memory-mapped XIP on the newer lines, or
    nothing at all on most small parts.  Which of these the kernel
    supports first, the region it occupies, whether the page allocator
    treats it exactly like internal SRAM, and (for a cached XIP path)
    how instruction-cache invalidation is handled on code load.

18. **On-target testing**: the harness and strategy for running tests on
    real hardware (host-side tests under ``test/`` are settled).

19. **tdtsi / tdts** *[deferred]*: the chip and board description DSL
    (paused, waiting for background).  It gates the compile-time driver set,
    device creation, the peripheral address maps and the ioctl registry.

20. **DSL code generation** *[deferred]*: which syscall-table entries the
    DSL generates, how ``Unique<T>`` / ``Shared<T>`` render into C++ and
    Rust, whether an owning wrapper may be a ``struct`` member (the DSL
    otherwise emits compile-time constants and POD data only) and where else
    it is allowed, and the per-interface ioctl command/argument registry.

21. **Priority fold onto the NVIC** *[TODO]*: mapping the U8 thread scale
    (and the 33-level RT band) onto the **16 hardware levels** every target
    provides — the ``BASEPRI`` value for each kernel critical section, the
    NVIC priority of each interrupt source, and how the priority-ceiling
    protocol behaves where several thread levels share one mask value.
    SysTick and HardFault priorities are part of this decision (HardFault
    is fixed at -1, below every RT thread).

22. **DMA placement and cache maintenance mechanism** *[TODO]*: the policy
    is settled (the interface provider owns coherency); what is missing is
    the per-platform *mechanism* — which RAM region a controller can
    actually reach (TCM is not reachable by the ordinary DMA channels on
    F405+/H7), whether DMA buffers live in a permanently non-cacheable
    region or in a cacheable one wrapped by clean/invalidate, and for the
    H7's data cache (write-back capable, geometry unreadable from the
    vendor documents) what operation each transfer direction
    requires.  Recorded as one item because every answer is a platform
    table entry, and the table is what ``doc/supported-hardware.rst``
    feeds.
