# Roadmap

## Purpose

This document records potential development stages beyond the current project scope. It is directional rather than a commitment to implementation order or delivery dates.

The authoritative definition of the current scope is maintained in [MVP.md](MVP.md). A roadmap item becomes part of the active scope only when it is explicitly incorporated into that document.

## Live hardware discovery

Replace simulated topology data with read-only information discovered from a real engineering environment.

The generic core should remain unchanged, and discovered systems should be normalized into the canonical representation defined for the active project scope.

## Agent-generated connector

Provide the agent with an engineering environment for which no project-specific connector has been prepared.

The agent should identify a suitable programmatic access path, generate or adapt an isolated connector, validate its behavior, preserve raw discovery results, and return normalized discovery data.

## Cross-platform validation

Repeat the discovery and normalization workflow on an additional automation platform.

The normalization, matching, and commissioning logic should require no vendor-specific changes. Environment-specific behavior should remain isolated in replaceable connector artifacts.

## Brownfield reconstruction

Combine live discovery with existing engineering artifacts, runtime observations, documentation, and optional semantic models.

The result should be a reconstructed system model that preserves provenance, represents uncertainty, and identifies missing or conflicting information explicitly.

## Commissioning artifact generation

Use validated canonical models and mappings to generate engineering artifacts through explicit, controlled workflows.

Any future path that writes configuration, deploys code, changes controller state, or interacts with physical outputs must introduce a documented safety boundary and require human approval.
