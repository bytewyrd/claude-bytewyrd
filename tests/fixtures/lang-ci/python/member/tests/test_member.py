def test_member():
    # Importable only when `uv sync --all-packages` installed the workspace member.
    import lang_ci_member

    assert lang_ci_member.__name__ == "lang_ci_member"
