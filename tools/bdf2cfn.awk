# Bake a BDF bitmap font into the engine's CFN format on stdout.
#   LC_ALL=C gawk -f tools/bdf2cfn.awk font.bdf > ui.cfn
# CFN: 'CFN1', u8 cellH, u8 asc, u8 lo, u8 hi, u8 rowBytes,
#      adv[lo..hi] (u8 each), then bits[lo..hi] (cellH*rowBytes bytes each,
#      bit 7 of the first byte = leftmost column). Covers ASCII 32..126.
# Run under LC_ALL=C so printf "%c" writes raw bytes, not UTF-8.
BEGIN { lo=32; hi=126; asc=0; desc=0; rowBytes=1 }
/^STARTCHAR/ { enc=-1; adv=0; bw=0; bh=0; bx=0; by=0; nb=0; bitmap=0; next }
/^ENCODING/  { enc=$2+0; next }
/^DWIDTH/    { adv=$2+0; next }
/^BBX/       { bw=$2+0; bh=$3+0; bx=$4+0; by=$5+0; next }
/^BITMAP/    { bitmap=1; nb=0; next }
/^ENDCHAR/   {
  bitmap=0
  if (enc>=lo && enc<=hi) {
    A[enc]=adv; BW[enc]=bw; BH[enc]=bh; BX[enc]=bx; BY[enc]=by
    for (i=0;i<nb;i++) ROW[enc,i]=RH[i]
    t=by+bh; if (t>asc) asc=t
    dd=-by; if (dd>desc) desc=dd
  }
  next
}
{ if (bitmap==1) { RH[nb]=$0; nb++ } }
END {
  cellH=asc+desc
  printf("%c%c%c%c", 67, 70, 78, 49)          # 'CFN1'
  printf("%c%c%c%c%c", cellH, asc, lo, hi, rowBytes)
  for (c=lo;c<=hi;c++) printf("%c", (c in A)?A[c]:0)
  for (c=lo;c<=hi;c++) {
    top = asc - (BY[c]+BH[c])
    for (r=0;r<cellH;r++) {
      v=0; gr=r-top
      if (c in A && gr>=0 && gr<BH[c]) {
        raw = strtonum("0x" ROW[c,gr])
        if (BX[c]>=0) v = rshift(raw, BX[c]); else v = lshift(raw, -BX[c])
        v = and(v, 255)
      }
      printf("%c", v)
    }
  }
}
