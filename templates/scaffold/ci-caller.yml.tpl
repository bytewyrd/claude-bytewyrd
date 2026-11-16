name: CI
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
permissions:
  contents: read
jobs:
@@job@@   @@job_id@@:
@@job@@     uses: bytewyrd/claude-bytewyrd/.github/workflows/lang-ci-@@job_language@@.yml@ae97f77274601ab3da301a9ffe353e438d2927ae
@@job@@     with:
@@job@@       directory: "@@job_directory@@"
