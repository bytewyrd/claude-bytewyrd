name: CI
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
permissions:
  contents: read
jobs:
  checks:
    runs-on: ubuntu-latest
    steps:
      - run: echo "bytewyrd scaffold found no language markers; replace this job with real checks."
