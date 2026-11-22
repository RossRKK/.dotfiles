# Just the font files Neovide's font.normal falls back to for symbols 0xProto lacks.
{
  runCommand,
  dejavu_fonts,
  noto-fonts,
}:

runCommand "symbol-fallback-fonts" { } ''
  install -Dm644 -t $out/share/fonts/truetype ${dejavu_fonts}/share/fonts/truetype/DejaVuSansMono{,-Bold}.ttf
  install -Dm644 -t $out/share/fonts/opentype ${noto-fonts}/share/fonts/noto/NotoSansSymbols2-Regular.otf
''
