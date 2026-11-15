## Python

- _Python_: Add type annotations as you write code, not after. Retrofitting types into untyped Python is slow and often reveals design issues that are costly to fix late.
- _Python_: Use `uv` for dependency management (`mise.toml` pins the Python version; `uv sync` manages the venv). Mixing pip, venv, and pyenv leads to environment drift across machines.
