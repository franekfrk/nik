"""Shared literal text validation; no command/JSON interpretation."""
import unicodedata

def literal(text):
    assert 1<=len(text)<=512 and text.strip(), 'Tekst musi mieć 1–512 znaków.'
    assert not any(unicodedata.category(c) in {'Cc','Cs'} for c in text), 'Tekst zawiera znak sterujący.'
    return text
