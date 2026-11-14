import sys, json
from pptx import Presentation
from pptx.util import Emu

path = sys.argv[1] if len(sys.argv) > 1 else r"C:\Users\qq959\FocusTimer3\deck_src.pptx"
prs = Presentation(path)
print("SLIDE SIZE:", prs.slide_width, prs.slide_height,
      Emu(prs.slide_width).inches, Emu(prs.slide_height).inches)
print("NUM SLIDES:", len(prs.slides))

def color_of(run):
    try:
        c = run.font.color
        if c and c.type is not None:
            if str(c.type) == "MSO_THEME_COLOR.NOT_THEME_COLOR" or c.rgb is not None:
                return str(c.rgb)
    except Exception:
        pass
    return None

for i, slide in enumerate(prs.slides, 1):
    print("\n" + "=" * 100)
    print(f"SLIDE {i}  layout={slide.slide_layout.name}")
    for sh in slide.shapes:
        info = f"  [{sh.shape_type}] id={sh.shape_id} name={sh.name!r} pos=({Emu(sh.left).inches:.2f},{Emu(sh.top).inches:.2f}) size=({Emu(sh.width).inches:.2f}x{Emu(sh.height).inches:.2f})"
        print(info)
        if sh.has_text_frame:
            for pi, p in enumerate(sh.text_frame.paragraphs):
                txt = "".join(r.text for r in p.runs)
                if not txt.strip():
                    continue
                runs = [(r.text, r.font.size.pt if r.font.size else None, str(r.font.bold), color_of(r), r.font.name) for r in p.runs]
                print(f"      p{pi} lvl={p.level} align={p.alignment}: {txt!r}")
                for r in runs:
                    print(f"          run={r}")
        if sh.has_table:
            tbl = sh.table
            print(f"      TABLE rows={len(tbl.rows)} cols={len(tbl.columns)}")
            for ri, row in enumerate(tbl.rows):
                cells = []
                for ci, cell in enumerate(row.cells):
                    t = cell.text.replace("\n", "\\n")
                    cells.append(f"c{ci}={t!r}")
                print(f"        r{ri}: " + " | ".join(cells))
        if sh.shape_type == 13 or sh.__class__.__name__ == "Picture":
            try:
                print(f"      IMAGE: {sh.image.filename or sh.image.blob[:0]} ext={sh.image.ext} size={len(sh.image.blob)}")
            except Exception as e:
                print("      IMAGE: (err)", e)
    if slide.has_notes_slide:
        nt = slide.notes_slide.notes_text_frame.text
        print(f"  NOTES: {nt!r}")
    else:
        print("  NOTES: <none>")
