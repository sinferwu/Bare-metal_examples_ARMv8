// ------------------------------------------------------------
// ARMv8 MPCore EL3 AArch64 Startup Code
//
// Basic Vectors, MMU, caches and GICv3 initialization in EL3 AArch64
//
// Exits in EL1 AArch32
//
// Copyright (c) 2014-2016 ARM Ltd.  All rights reserved.
// ------------------------------------------------------------


    .section StartUp, "ax"
    .balign 4


    .global el1_vectors
    .global el2_vectors
    .global el3_vectors

    .global InvalidateUDCaches
    .global ZeroBlock

    .global SetPrivateIntSecurityBlock
    .global SetSPISecurityAll
    .global SetPrivateIntPriority

    .global WakeupGICR
    .global SyncAREinGICD
    .global EnableGICD
    .global EnablePrivateInt
    .global GetPrivateIntPending
    .global ClearPrivateIntPending

    .global __main
    .global A32SetAppStack

    .global drop_primary_to_el1
    .global drop_secondary_to_el1

    .global Image$$EXEC$$RO$$Base
    .global Image$$TTB0_L1$$ZI$$Base
    .global Image$$TTB0_L2_RAM$$ZI$$Base
    .global Image$$TTB0_L2_PERIPH$$ZI$$Base
    .global Image$$TOP_OF_RAM$$ZI$$Base
    .global Image$$GICD$$ZI$$Base
    .global Image$$EL3_STACKS$$ZI$$Limit
    .global Image$$CS3_PERIPHERALS$$ZI$$Base

    .include "startup_64_src/v8_mmu.s"
    .include "startup_64_src/v8_system.s"

    .equ AArch32_Mode_SVC, 0x13

// ------------------------------------------------------------

    .global start64
    .type start64, "function"
start64:

    //
    // program the VBARs
    //
    ldr x1, =el1_vectors
    msr VBAR_EL1, x1

    ldr x1, =el2_vectors
    msr VBAR_EL2, x1

    ldr x1, =el3_vectors
    msr VBAR_EL3, x1


    // GIC-500 comes out of reset in GICv2 compatibility mode - first set
    // system register enables for all relevant exception levels, and
    // select GICv3 operating mode
    //
    msr SCR_EL3, xzr  // Ensure NS bit is initially clear, so secure copy of ICC_SRE_EL1 can be configured
    isb

    mov x0, #15
    msr ICC_SRE_EL3, x0
    isb
    msr ICC_SRE_EL1, x0 // Secure copy of ICC_SRE_EL1

    //
    // set lower exception levels as non-secure, with no access
    // back to EL2 or EL3, and are AArch64 capable
    //
    mov x3, #(SCR_EL3_RW  | \
              SCR_EL3_SMD | \
              SCR_EL3_NS)      // Set NS bit, to access Non-secure registers
    msr SCR_EL3, x3
    isb

    mov x0, #15
    msr ICC_SRE_EL2, x0
    isb
    msr ICC_SRE_EL1, x0 // Non-secure copy of ICC_SRE_EL1


    //
    // no traps or VM modifications from the Hypervisor, EL1 is AArch32
    //
    mrs x2, HCR_EL2
    bfi x2, xzr, #31, #1 // Ensure HCR_EL2.RW is 0 (it is by default), so that EL1 will be AArch32
    msr HCR_EL2, x2

    //
    // VMID is still significant, even when virtualisation is not
    // being used, so ensure VTTBR_EL2 is properly initialised
    //
    msr VTTBR_EL2, xzr

    //
    // VMPIDR_EL2 holds the value of the Virtualization Multiprocessor ID. This is the value returned by Non-secure EL1 reads of MPIDR_EL1.
    //  VPIDR_EL2 holds the value of the Virtualization Processor ID. This is the value returned by Non-secure EL1 reads of MIDR_EL1.
    // Both of these registers are architecturally UNKNOWN at reset, and so they must be set to the correct value
    // (even if EL2/virtualization is not being used), otherwise non-secure EL1 reads of MPIDR_EL1/MIDR_EL1 will return garbage values.
    // This guarantees that any future reads of MPIDR_EL1 and MIDR_EL1 from Non-secure EL1 will return the correct value.
    //
    // keep MPIDR_EL1.Aff0 (i.e. the CPU no. on Cortex-A cores) in
    // x19 (defined by the AAPCS as callee-saved), so we can re-use
    // the number later
    //
    mrs x0, MPIDR_EL1
    ubfx x19, x0, #MPIDR_EL1_AFF0_LSB, #MPIDR_EL1_AFF_WIDTH
    msr VMPIDR_EL2, x0

    mrs x0, MIDR_EL1
    msr VPIDR_EL2, x0

    //
    // neither EL3 nor EL2 trap floating point or accesses to CPACR
    //
    msr CPTR_EL3, xzr
    msr CPTR_EL2, xzr

    //
    // SCTLR_EL3 comes out of reset with a limited set of known fields
    // set; the only significant field is SCTLR_EL3.EE, which comes out
    // of reset with an IMPLEMENTATION DEFINED value. Preserve SCTLR.EE
    // and set the unknowns to 0 (all the other known values are already
    //  0)
    //
    mrs x0, SCTLR_EL3
    and x0, x0, #SCTLR_ELx_EE
    mrs x0, SCTLR_EL3

    //
    // set SCTLRs for lower ELs to safe values
    //
    // note that setting SCTLR_EL2 is not strictly
    // needed, since we're never in EL2
    //
    msr SCTLR_EL1, xzr
    msr SCTLR_EL2, xzr

#ifdef CORTEXA
    //
    // Configure ACTLR_EL[23]
    // ----------------------
    //
    // These bits are IMPLEMENTATION DEFINED, so are different for
    // different processors
    //
    // For Cortex-A57, the controls we set are:
    //
    //  Enable lower level access to CPUACTLR_EL1
    //  Enable lower level access to CPUECTLR_EL1
    //  Enable lower level access to L2CTLR_EL1
    //  Enable lower level access to L2ECTLR_EL1
    //  Enable lower level access to L2ACTLR_EL1
    //
    mov x0, #((1 << 0) | \
              (1 << 1) | \
              (1 << 4) | \
              (1 << 5) | \
              (1 << 6))

    msr ACTLR_EL3, x0
    msr ACTLR_EL2, x0

    //
    // configure CPUECTLR_EL1
    //
    // These bits are IMP DEF, so need to different for different
    // processors
    //
    // SMPEN - bit 6 - Enables the processor to receive cache
    //                 and TLB maintenance operations
    //
    // Note: For Cortex-A57/53 SMPEN should be set before enabling
    //       the caches and MMU, or performing any cache and TLB
    //       maintenance operations.
    //
    //       This register has a defined reset value, so we use a
    //       read-modify-write sequence to set SMPEN
    //
    mrs x0, S3_1_c15_c2_1  // Read EL1 CPU Extended Control Register
    orr x0, x0, #(1 << 6)  // Set the SMPEN bit
    msr S3_1_c15_c2_1, x0  // Write EL1 CPU Extended Control Register

    isb
#endif

    //
    // That's the last of the control settings for now
    //
    // Note: no ISB after all these changes, as registers won't be
    // accessed until after an exception return, which is itself a
    // context synchronisation event
    //

    //
    // Setup some EL3 stack space, ready for calling some subroutines, below.
    //
    // Stack space allocation is CPU-specific, so use CPU
    // number already held in x19
    //
    // 2^12 bytes per CPU for the EL3 stacks
    //
    ldr x0, =Image$$EL3_STACKS$$ZI$$Limit
    sub x0, x0, x19, lsl #12
    mov sp, x0

    //
    // we need to configure the GIC while still in secure mode, specifically
    // all PPIs and SPIs have to be programmed as Group1 interrupts
    //

    //
    // Before the GIC can be reliably programmed, we need to
    // enable Affinity Routing, as this affects where the configuration
    // registers are (with Affinity Routing enabled, some registers are
    // in the Redistributor, whereas those same registers are in the
    // Distributor with Affinity Routing disabled (i.e. when in GICv2
    // compatibility mode).
    //
    mov x0, #(1 << 4) | (1 << 5) // gicdctlr_ARE_S | gicdctlr_ARE_NS
    mov x1, x19
    bl  SyncAREinGICD

    //
    // The Redistributor comes out of reset assuming the processor is
    // asleep - correct that assumption
    //
    mov w0, w19
    bl  WakeupGICR

    //
    // Now we're ready to set security and other initialisations
    //
    // This is a per-CPU configuration for these interrupts
    //
    // for the first cluster, CPU number is the redistributor index
    //
    mov w0, w19
    mov w1, #1    // gicigroupr_G1NS
    bl  SetPrivateIntSecurityBlock

    //
    // While we're in the Secure World, set the priority mask low enough
    // for it to be writable in the Non-Secure World
    //
    mov x0, #16 << 3    // 5 bits of priority in the Secure world
    msr ICC_PMR_EL1, x0

    //
    // there's more GIC setup to do, but only for the primary CPU
    //
    cbnz x19, skip

    //
    // There's more to do to the GIC - call the utility routine to set
    // all SPIs to Group1
    //
    mov w0, #1    // gicigroupr_G1NS
    bl  SetSPISecurityAll

skip:

    //
    // Enable floating point
    //
    mov x0, #CPACR_FPEN
    msr CPACR_EL1, x0

    //
    // Switch on the VFP and NEON hardware
    mov x0, #0x40000000
    msr FPEXC32_EL2, x0                   // Write FPEXC register, EN bit set


    //
    // Invalidate caches and TLBs for all stage 1
    // translations used at EL1
    //
    // Cortex-A processors automatically invalidate their caches on reset
    // (unless suppressed with the DBGL1RSTDISABLE or L2RSTDISABLE pins).
    // It is therefore not necessary for software to invalidate the caches 
    // on startup, however, this is done here in case of a warm reset.
    bl  InvalidateUDCaches
    tlbi VMALLE1


    //
    // Set TTBR0 Base address
    //
    // The CPUs share one set of translation tables that are
    // generated by CPU0 at run-time
    //
    // TTBR1_EL1 is not used in this example
    //
    ldr x1, =Image$$TTB0_L1$$ZI$$Base
    msr TTBR0_EL1, x1


    //
    // Set up memory attributes
    //
    // These equate to:
    //
    // 0 -> 0b01000100 = 0x00000044 = Normal, Inner/Outer Non-Cacheable
    // 1 -> 0b11111111 = 0x0000ff00 = Normal, Inner/Outer WriteBack Read/Write Allocate
    // 2 -> 0b00000100 = 0x00040000 = Device-nGnRE
    //
    mov  x1, #0xff44
    movk x1, #4, LSL #16    // equiv to: movk x1, #0x0000000000040000
    msr MAIR_EL1, x1


    //
    // Set up TCR_EL1
    //
    // We're using only TTBR0 (EPD1 = 1), and the page table entries:
    //  - are using an 8-bit ASID from TTBR0
    //  - have a 4K granularity (TG0 = 0b00)
    //  - are outer-shareable (SH0 = 0b10)
    //  - are using Inner & Outer WBWA Normal memory ([IO]RGN0 = 0b01)
    //  - map
    //      + 32 bits of VA space (T0SZ = 0x20)
    //      + into a 32-bit PA space (IPS = 0b000)
    //
    //     36   32   28   24   20   16   12    8    4    0
    //  -----+----+----+----+----+----+----+----+----+----+
    //       |    |    |OOII|    |    |    |00II|    |    |
    //    TT |    |    |RRRR|E T |   T|    |RRRR|E T |   T|
    //    BB | I I|TTSS|GGGG|P 1 |   1|TTSS|GGGG|P 0 |   0|
    //    IIA| P P|GGHH|NNNN|DAS |   S|GGHH|NNNN|D S |   S|
    //    10S| S-S|1111|1111|11Z-|---Z|0000|0000|0 Z-|---Z|
    //
    //    000 0000 1000 0000 1000 0000 0010 0101 0010 0000
    //
    //          0x    8    0    8    0    2    5    2    0
    // Bit 31 set TTBCR.EAE
    // Note: the ISB is needed to ensure the changes to system
    //       context are before the write of SCTLR_EL1.M to enable
    //       the MMU. It is likely on a "real" implementation that
    //       this setup would work without an ISB, due to the
    //       amount of code that gets executed before enabling the
    //       MMU, but that would not be architecturally correct.
    //
    ldr x1, =0x0000000080802520
    msr TCR_EL1, x1
    isb

    //
    // x19 already contains the CPU number, so branch to secondary
    // code if we're not on CPU0
    //
    cbnz x19, el3_secondary

    //
    // Fall through to primary code
    //


//
// ------------------------------------------------------------
//
// EL3 - primary CPU init code
//
// This code is run on CPU0, while the other CPUs are in the
// holding pen
//

    .global el3_primary
    .type el3_primary, "function"
el3_primary:

    //
    // We're now on the primary processor, so turn on
    // the banked GIC distributor enable, ready for individual CPU
    // enables later
    //
    mov w0, #(1 << 1)  // gicdctlr_EnableGrp1A
    bl  EnableGICD

    //
    // Generate TTBR0 L1
    //
    // at 4KB granularity, 32-bit VA space, table lookup starts at
    // L1, with 1GB regions
    //
    // we are going to create entries pointing to L2 tables for a
    // couple of these 1GB regions, the first of which is the
    // RAM on the VE board model - get the table addresses and
    // start by emptying out the L1 page tables (4 entries at L1
    // for a 4K granularity)
    //
    // x21 = address of L1 tables
    //
    ldr x21, =Image$$TTB0_L1$$ZI$$Base
    mov x0, x21
    mov x1, #(4 << 3)
    bl  ZeroBlock

    //
    // time to start mapping the RAM regions - clear out the
    // L2 tables and point to them from the L1 tables
    //
    // x22 = address of L2 tables, needs to be remembered in case
    //       we want to re-use the tables for mapping peripherals
    //
    ldr x22, =Image$$TTB0_L2_RAM$$ZI$$Base
    mov x1, #(512 << 3)
    mov x0, x22
    bl  ZeroBlock

    //
    // Get the start address of RAM (the EXEC region) into x4
    // and calculate the offset into the L1 table (1GB per region,
    // max 4GB)
    //
    // x23 = L1 table offset, saved for later comparison against
    //       peripheral offset
    //
    ldr x4, =Image$$EXEC$$RO$$Base
    ubfx x23, x4, #30, #2

    orr x1, x22, #TT_S1_ATTR_PAGE
    str x1, [x21, x23, lsl #3]

    //
    // we've already used the RAM start address in x4 - we now need
    // to get this in terms of an offset into the L2 page tables,
    // where each entry covers 2MB
    //
    ubfx x2, x4, #21, #9

    //
    // TOP_OF_RAM in the scatter file marks the end of the
    // Execute region in RAM: convert the end of this region to an
    // offset too, being careful to round up, then calculate the
    // number of entries to write
    //
    ldr x5, =Image$$TOP_OF_RAM$$ZI$$Base
    sub  x3, x5, #1
    ubfx x3, x3, #21, #9
    add  x3, x3, #1
    sub  x3, x3, x2

    //
    // set x1 to the required page table attributes, then orr
    // in the start address (modulo 2MB)
    //
    // L2 tables in our configuration cover 2MB per entry - map
    // memory as Shared, Normal WBWA (MAIR[1]) with a flat
    // VA->PA translation
    //
    bic x4, x4, #((1 << 21) - 1)
    mov x1, #(TT_S1_ATTR_BLOCK | \
             (1 << TT_S1_ATTR_MATTR_LSB) | \
              TT_S1_ATTR_NS | \
              TT_S1_ATTR_AP_RW_PL1 | \
              TT_S1_ATTR_SH_INNER | \
              TT_S1_ATTR_AF | \
              TT_S1_ATTR_nG)
    orr x1, x1, x4

    //
    // factor the offset into the page table address and then write
    // the entries
    //
    add x0, x22, x2, lsl #3

loop1:
    subs x3, x3, #1
    str x1, [x0], #8
    add x1, x1, #0x200, LSL #12    // equiv to add x1, x1, #(1 << 21)  // 2MB per entry
    bne loop1


    //
    // now mapping the Peripheral regions - clear out the
    // L2 tables and point to them from the L1 tables
    //
    // The assumption here is that all peripherals live within
    // a common 1GB region (i.e. that there's a single set of
    // L2 pages for all the peripherals). We only use a UART
    // and the GIC in this example, so the assumption is sound
    //
    // x24 = address of L2 peripheral tables
    //
    ldr x24, =Image$$TTB0_L2_PERIPH$$ZI$$Base

    //
    // get the GICD address into x4 and calculate
    // the offset into the L1 table
    //
    // x25 = L1 table offset
    //
    ldr x4, =Image$$GICD$$ZI$$Base
    ubfx x25, x4, #30, #2

    //
    // here's the tricky bit: it's possible that the peripherals are
    // in the same 1GB region as the RAM, in which case we don't need
    // to prime a separate set of L2 page tables, nor add them to the
    // L1 tables
    //
    // if we're going to re-use the TTB0_L2_RAM tables, get their
    // address into x24, which is used later on to write the PTEs
    //
    cmp x25, x23
    csel x24, x22, x24, EQ
    b.eq nol2setup

    //
    // Peripherals are in a separate 1GB region, and so have their own
    // set of L2 tables - clean out the tables and add them to the L1
    // table
    //
    mov x0, x24
    mov x1, #512 << 3
    bl  ZeroBlock

    orr x1, x24, #TT_S1_ATTR_PAGE
    str x1, [x21, x25, lsl #3]

    //
    // there's only going to be a single 2MB region for GICD (in
    // x4) - get this in terms of an offset into the L2 page tables
    //
    // with larger systems, it is possible that the GIC redistributor
    // registers require extra 2MB pages, in which case extra code
    // would be required here
    //
nol2setup:
    ubfx x2, x4, #21, #9

    //
    // set x1 to the required page table attributes, then orr
    // in the start address (modulo 2MB)
    //
    // L2 tables in our configuration cover 2MB per entry - map
    // memory as NS Device-nGnRE (MAIR[2]) with a flat VA->PA
    // translation
    //
    bic x4, x4, #((1 << 21) - 1)  // start address mod 2MB
    mov x1, #(TT_S1_ATTR_BLOCK | \
             (2 << TT_S1_ATTR_MATTR_LSB) | \
              TT_S1_ATTR_NS | \
              TT_S1_ATTR_AP_RW_PL1 | \
              TT_S1_ATTR_AF | \
              TT_S1_ATTR_nG)
    orr x1, x1, x4

    //
    // only a single L2 entry for this, so no loop as we have for RAM, above
    //
    str x1, [x24, x2, lsl #3]

    //
    // we have CS3_PERIPHERALS that include the UART controller
    //
    // Again, the code is making assumptions - this time that the CS3_PERIPHERALS
    // region uses the same 1GB portion of the address space as the GICD,
    // and thus shares the same set of L2 page tables
    //
    // Get CS3_PERIPHERALS address into x4 and calculate the offset into the
    // L2 tables
    //
    ldr x4, =Image$$CS3_PERIPHERALS$$ZI$$Base
    ubfx x2, x4, #21, #9

    //
    // set x1 to the required page table attributes, then orr
    // in the start address (modulo 2MB)
    //
    // L2 tables in our configuration cover 2MB per entry - map
    // memory as NS Device-nGnRE (MAIR[2]) with a flat VA->PA
    // translation
    //
    bic x4, x4, #((1 << 21) - 1)  // start address mod 2MB
    mov x1, #(TT_S1_ATTR_BLOCK | \
             (2 << TT_S1_ATTR_MATTR_LSB) | \
              TT_S1_ATTR_NS | \
              TT_S1_ATTR_AP_RW_PL1 | \
              TT_S1_ATTR_AF | \
              TT_S1_ATTR_nG)
    orr x1, x1, x4

    //
    // only a single L2 entry again - write it
    //
    str x1, [x24, x2, lsl #3]

    //
    // issue a barrier to ensure all table entry writes are complete
    //
    dsb ish

    //
    // Enable the MMU.  Caches will be enabled later, after scatterloading.
    //
    mrs x1, SCTLR_EL1
    orr x1, x1, #SCTLR_ELx_M
    bic x1, x1, #SCTLR_ELx_A // Disable alignment fault checking.  To enable, change bic to orr
    msr SCTLR_EL1, x1
    isb

    //
    // Set up EL1 entry point for __main() and "dummy" exception return information,
    // then perform exception return to enter EL1N AArch32 SVC
    //
drop_primary_to_el1:
    ldr x1, =__main
    msr ELR_EL3, x1
    mov x1, #(AArch32_Mode_SVC | \
              AARCH64_SPSR_F   | \
              AARCH64_SPSR_I   | \
              AARCH64_SPSR_A)
    msr SPSR_EL3, x1
    eret


// ------------------------------------------------------------
// EL3 - secondary CPU init code
//
// This code is run on CPUs 1, 2, 3 etc....
// ------------------------------------------------------------

    .global el3_secondary
    .type el3_secondary, "function"
el3_secondary:

    //
    // the primary CPU is going to use SGI 15 as a wakeup event
    // to let us know when it is OK to proceed, so prepare for
    // receiving that interrupt
    //
    // NS interrupt priorities run from 0 to 15, with 15 being
    // too low a priority to ever raise an interrupt, so let's
    // use 14
    //
    mov w0, w19
    mov w1, #15
    mov w2, #2
    bl SetPrivateIntPriority

    mov w0, w19
    mov w1, #15
    bl  EnablePrivateInt

    //
    // set priority mask as low as possible; although,being in the
    // NS World, we can't set bit[7] of the priority, we still
    // write all 8-bits of priority to an ICC register
    //
    mov x0, #0xFF
    msr ICC_PMR_EL1, x0

    //
    // set global enable and wait for our interrupt to arrive
    //
    mov x0, #1
    msr ICC_IGRPEN1_EL1, x0

loop_wfi:
    dsb SY      // Clear all pending data accesses
    wfi         // Go to sleep

    //
    // something woke us from our wait, was it the required interrupt?
    //
    mov w0, w19
    mov w1, #15
    bl  GetPrivateIntPending
    cbz w0, loop_wfi

    //
    // it was - there's no need to actually take the interrupt,
    // so just clear it
    //
    mov w0, w19
    mov w1, #15
    bl  ClearPrivateIntPending

    //
    // Enable the MMU and caches
    //
    mrs x1, SCTLR_EL1
    orr x1, x1, #SCTLR_ELx_M
    orr x1, x1, #SCTLR_ELx_C
    orr x1, x1, #SCTLR_ELx_I
    bic x1, x1, #SCTLR_ELx_A // Disable alignment fault checking.  To enable, change bic to orr
    msr SCTLR_EL1, x1
    isb

    //
    // Set up EL1 entry point for A32SetAppStack() and "dummy" exception return information,
    // then perform exception return to enter EL1N AArch32 SVC
    //
drop_secondary_to_el1:
    ldr x1, =A32SetAppStack
    msr ELR_EL3, x1
    mov x1, #(AArch32_Mode_SVC | \
              AARCH64_SPSR_F   | \
              AARCH64_SPSR_I   | \
              AARCH64_SPSR_A)
    msr SPSR_EL3, x1
    eret

