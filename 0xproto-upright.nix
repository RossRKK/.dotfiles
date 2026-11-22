# 0xProto without its cursive Italic faces, so renderers slant Regular for italics instead.
{ symlinkJoin, nerd-fonts }:

symlinkJoin {
  name = "nerd-fonts-0xproto-upright";
  paths = [ nerd-fonts._0xproto ];
  postBuild = "find $out -name '*Italic*' -delete";
}
