# Project Brief

## Problem

Provides a standardized, opinionated Claude Code setup — skills, agents, and MCP configs — for Bytewyrd projects and teams who want to adopt the same workflow, eliminating the manual work of configuring Claude Code from scratch on each project.

## Goals

Every Bytewyrd project (and any project adopting this workflow) has a consistent, fully-configured Claude Code environment with proven skills, agent delegation patterns, quality gates, and RFC process out of the box.

## Non-Goals

Not a general-purpose Claude Code starter kit for arbitrary workflows — while the conventions are opinionated toward the Bytewyrd stack, the plugin is designed to be adoptable by other teams wanting to follow the same workflow.

## Constraints

Must work within the Claude Code sandbox and permission model; skills must be self-contained and portable across machines without requiring global configuration changes.

This project is both the definition of the Bytewyrd workflow and a live instance of it. All changes follow a promote-through-production model: modifications are made to the project's own `.claude/` configuration first, validated through real usage in this repo, and only then promoted to the exported plugin artifacts that other projects consume. Never edit the plugin export artifacts directly — changes always start in `.claude/`.
