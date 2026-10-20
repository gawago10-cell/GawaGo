from pathlib import Path
import re
import sys

from pypdf import PdfReader



def clean_page_text(text: str) -> str:
    text = text.replace("\r", "")
    text = re.sub(r"[ \t]+\n", "\n", text)
    text = re.sub(r"\n{4,}", "\n\n\n", text)
    return text.strip()


def main() -> int:
    if len(sys.argv) != 3:
        print("Usage: python scripts/extract_pdf_to_capstone.py <source.pdf> <output.md>")
        return 2

    source = Path(sys.argv[1])
    output = Path(sys.argv[2])
    reader = PdfReader(str(source))

    sections = [
        "# Capstone Manuscript\n",
        (
            f"> Source: `{source}`  \n"
            "> Imported into `capstone.md` on 2026-06-01.  \n"
            "> Use this Markdown file as the living manuscript copy. "
            "When GawaGo system logic changes, update the related manuscript sections here too.\n\n"
        ),
        "---\n\n",
    ]

    for index, page in enumerate(reader.pages, start=1):
        text = clean_page_text(page.extract_text(extraction_mode="layout") or "")
        sections.append(f"<!-- Page {index} -->\n\n{text}\n\n")

    output.write_text("\n".join(sections), encoding="utf-8")
    print(f"Wrote {output} from {len(reader.pages)} PDF pages.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
