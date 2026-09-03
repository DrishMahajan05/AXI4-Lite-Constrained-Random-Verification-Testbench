# AXI4-Lite Constrained Random Verification Testbench

This repository contains a SystemVerilog constrained-random verification environment for a simple AXI4-Lite slave model.  
The testbench generates randomized read and write traffic, drives AXI4-Lite handshakes, monitors bus activity, and checks read data against a reference model.

## What is AXI?

AXI (Advanced eXtensible Interface) is part of ARM’s AMBA protocol family and is widely used for on-chip communication between masters (initiators) and slaves (targets).

### Why AXI is used
- High-throughput and scalable interconnect standard.
- Clear valid/ready handshake mechanism.
- Independent channels allow efficient pipelining.
- Standardized responses and sideband attributes.

### AXI4-Lite in this project
This project focuses on **AXI4-Lite**, a simplified AXI variant for low-bandwidth control/status register accesses.

AXI4-Lite characteristics:
- Single-beat transactions only (no bursts).
- Typically 32-bit address and data buses (as used here).
- Separate channels for read and write paths.
- Lightweight protocol suitable for register-mapped peripherals.

## AXI4-Lite Channel Overview

AXI4-Lite uses five independent channels:

1. **Write Address (AW)**  
   Carries write address and protection attributes (`awaddr`, `awprot`, `awvalid`, `awready`).

2. **Write Data (W)**  
   Carries write payload and byte strobes (`wdata`, `wstrb`, `wvalid`, `wready`).

3. **Write Response (B)**  
   Slave returns write completion status (`bresp`, `bvalid`, `bready`).

4. **Read Address (AR)**  
   Carries read address and attributes (`araddr`, `arprot`, `arvalid`, `arready`).

5. **Read Data (R)**  
   Slave returns read data and status (`rdata`, `rresp`, `rvalid`, `rready`).

Each transfer on a channel completes when both `VALID` and `READY` are high on the same rising clock edge.

## Repository Contents

- `tb.sv` — Full verification environment and dummy AXI4-Lite slave DUT.
- `README.md` — Project documentation.

## Testbench Architecture

The testbench in `tb.sv` includes:

- **`transaction` class**  
  Defines randomized stimulus fields (`is_write`, `addr`, `data`, `wstrb`, `prot`) and captured outputs (`rdata`, `bresp`, `rresp`).

- **Constrained random generation**  
  Enforces word alignment (`addr % 4 == 0`) and bounded address space (`addr < 0xFF`).

- **`generator`**  
  Produces randomized transactions and sends deep copies to the driver through a mailbox.

- **`driver` (AXI master emulator)**  
  Executes AXI4-Lite handshakes for write or read transactions.

- **`monitor`**  
  Passively observes bus activity and reconstructs transactions for checking.

- **`scoreboard`**  
  Maintains a reference memory model and compares read data against expected values.

- **`axi_slave_dummy` DUT**  
  A simple slave memory model used to exercise handshake and response behavior.

- **Top-level `tb` module**  
  Instantiates components, connects mailboxes/interfaces, generates clock/reset, and controls simulation end.

## Verification Strategy

The environment follows a standard mailbox-based flow:

1. Generator randomizes transactions.
2. Driver consumes transactions and drives bus protocol.
3. Monitor observes completed bus handshakes.
4. Scoreboard checks DUT behavior against a reference model.

This approach gives:
- Broad stimulus coverage from randomized traffic.
- Protocol-level visibility through monitor reconstruction.
- Functional correctness checks via scoreboard comparison.

## Current Constraints and Behaviors

- Addresses are constrained to a small memory region.
- Word alignment is enforced for normal transactions.
- An additional `error` class exists for fault-style stimuli (misalignment/zero strobe).
- Dummy DUT is always ready (`awready`, `wready`, `arready` set high).
- DUT currently writes full words and ignores `wstrb` masking for simplicity.

## How to Run

Use any SystemVerilog simulator that supports classes, interfaces, and `always_ff`.

Example flow:
1. Compile `tb.sv`.
2. Run simulation.
3. Inspect console logs for generator/driver/monitor/scoreboard messages.
4. Open `dump.vcd` in a waveform viewer to inspect AXI channel timing.

## Expected Output Behavior

During simulation, you should see:
- Generator sending randomized transactions.
- Driver logs for read/write operations with addresses/data.
- Monitor forwarding observed transactions.
- Scoreboard `PASS/FAIL/INFO` messages on read checks.

If the slave and scoreboard model agree, readbacks at initialized addresses should pass.

## Possible Extensions

- Add functional coverage for protocol scenarios and field distributions.
- Add assertions for handshake/response timing rules.
- Model backpressure by randomizing `ready` behavior in DUT or BFM.
- Implement proper `wstrb` byte-lane handling in the slave and checker.
- Integrate with UVM-style components/sequences for scaling.

## License

No license file is currently included in this repository.
