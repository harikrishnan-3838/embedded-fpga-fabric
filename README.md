# 4×4 Embedded FPGA Fabric

A configurable embedded FPGA fabric implemented using Verilog HDL, featuring programmable logic resources, routing interconnects, and configuration memory.

## Overview

This project explores the design and RTL implementation of a small embedded FPGA (eFPGA) fabric. The architecture consists of a 4×4 array of configurable logic tiles connected through programmable routing resources.

The objective is to develop a reconfigurable hardware fabric that can implement different digital logic functions through configuration data.

## Architecture

The fabric is designed around the following components:

- **Configurable Logic Blocks (CLBs):** Logic tiles designed to implement user-defined digital functions.
- **LUT4:** Four-input lookup-table logic for implementing combinational functions.
- **Connection Boxes:** Programmable connections between logic resources and routing tracks.
- **Switch Boxes:** Routing resources that allow signals to travel between interconnected tiles.
- **Configuration Memory:** Configuration data used to control the logic and routing resources.

## Design Specifications

| Feature | Description |
|---|---|
| Fabric organization | 4×4 tile array |
| Number of tiles | 16 |
| Logic element | LUT4-based logic |
| Routing architecture | Island-style programmable interconnect |
| Configuration approach | SRAM-style configuration using shift-register logic |
| HDL | Verilog |
| FPGA development environment | Xilinx Vivado |

*Specifications describe the intended architecture; implementation and verification status will be documented as the design is validated.*

## Verification

The project includes RTL development and functional simulation using Xilinx Vivado.

A ripple-carry adder (RCA) is being used as a demonstration circuit to evaluate configuration and routing functionality.

Simulation results, testbenches, and verification details will be added as the design is organized and validated.

## Project Structure

The repository will be organized into the following directories:

- `rtl/` — RTL source files
- `testbench/` — Simulation testbenches
- `configuration/` — Configuration generation scripts and example bitstreams
- `docs/` — Architecture documentation and diagrams
- `simulation/` — Selected simulation evidence

## Tools and Technologies

- Verilog HDL
- Xilinx Vivado
- RTL Simulation
- FPGA Architecture
- Digital Logic Design

## Project Status

**Status:** Under development.

The project focuses on configurable logic, routing interconnects, configuration generation, and functional verification.

Further documentation and test results will be added as development progresses.

## Future Improvements

- Complete and verify configurable routing.
- Validate configuration loading and logic programming.
- Expand functional verification with additional test circuits.
- Document synthesis results and hardware implementation where applicable.

---

Developed as an embedded FPGA architecture and RTL design project.
