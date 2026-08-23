import zipfile
import xml.etree.ElementTree as ET
import sys

def read_docx(path):
    """读取 docx 文件的全部文本内容"""
    ns = {'w': 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'}
    result = []
    with zipfile.ZipFile(path, 'r') as z:
        with z.open('word/document.xml') as f:
            tree = ET.parse(f)
            root = tree.getroot()
            # 遍历所有段落
            for para in root.iter('{http://schemas.openxmlformats.org/wordprocessingml/2006/main}p'):
                texts = []
                for t in para.iter('{http://schemas.openxmlformats.org/wordprocessingml/2006/main}t'):
                    if t.text:
                        texts.append(t.text)
                line = ''.join(texts)
                if line.strip():
                    result.append(line)
            # 遍历所有表格
            for table in root.iter('{http://schemas.openxmlformats.org/wordprocessingml/2006/main}tbl'):
                result.append('--- TABLE START ---')
                for row in table.iter('{http://schemas.openxmlformats.org/wordprocessingml/2006/main}tr'):
                    cells = []
                    for cell in row.iter('{http://schemas.openxmlformats.org/wordprocessingml/2006/main}tc'):
                        cell_texts = []
                        for t in cell.iter('{http://schemas.openxmlformats.org/wordprocessingml/2006/main}t'):
                            if t.text:
                                cell_texts.append(t.text)
                        cells.append(''.join(cell_texts))
                    result.append(' | '.join(cells))
                result.append('--- TABLE END ---')
    return '\n'.join(result)

if __name__ == '__main__':
    path = sys.argv[1]
    out = sys.argv[2] if len(sys.argv) > 2 else None
    content = read_docx(path)
    if out:
        with open(out, 'w', encoding='utf-8') as f:
            f.write(content)
        print(f'Saved to {out}, length={len(content)}')
    else:
        print(content)
