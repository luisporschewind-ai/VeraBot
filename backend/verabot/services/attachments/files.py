"""Bounded, read-only text extraction for user supplied office and text documents."""
from __future__ import annotations

import csv
import io
import multiprocessing
import posixpath
import re
import zipfile
from dataclasses import dataclass
from pathlib import PurePath
from xml.etree import ElementTree

MAX_BYTES = 10 * 1024 * 1024
MAX_ZIP_BYTES = 100 * 1024 * 1024
MAX_ZIP_ENTRIES = 2_000
MAX_PDF_PAGES = 200
MAX_SHEETS = 10
MAX_ROWS = 5_000
SEGMENT_CHARS = 30_000
ALLOWED = {"pdf", "txt", "md", "csv", "docx", "xlsx"}
MIME = {"pdf": "application/pdf", "txt": "text/plain", "md": "text/markdown", "csv": "text/csv",
        "docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        "xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"}


class FileProcessingError(ValueError):
    def __init__(self, message: str, code: str = "invalid_file"):
        super().__init__(message)
        self.message, self.code = message, code


@dataclass(frozen=True)
class ProcessedFile:
    filename: str
    extension: str
    mime: str
    pages: tuple[str, ...]
    text_status: str

    @property
    def text(self) -> str:
        return "\n\n".join(self.pages)


def safe_filename(name: str) -> str:
    name = PurePath((name or "file").replace("\\", "/")).name
    name = re.sub(r"[\x00-\x1f\x7f\"/\\]", "_", name).strip(" .")[:120]
    return name or "file"


def _zip(data: bytes) -> zipfile.ZipFile:
    try:
        z = zipfile.ZipFile(io.BytesIO(data))
        entries = z.infolist()
        if len(entries) > MAX_ZIP_ENTRIES or sum(x.file_size for x in entries) > MAX_ZIP_BYTES:
            raise FileProcessingError("Office 文档解压后超过安全限制", "file_resource_limit")
        if any(x.flag_bits & 1 for x in entries):
            raise FileProcessingError("不支持加密的 Office 文档", "encrypted_file")
        return z
    except zipfile.BadZipFile as e:
        raise FileProcessingError("文件损坏或格式不正确") from e


def _process_file(data: bytes, filename: str) -> ProcessedFile:
    clean = safe_filename(filename)
    ext = clean.rsplit(".", 1)[-1].lower() if "." in clean else ""
    if ext not in ALLOWED:
        raise FileProcessingError("支持 PDF、TXT、MD、CSV、DOCX 和 XLSX 文件", "unsupported_file_type")
    if not data or len(data) > MAX_BYTES:
        raise FileProcessingError("文件为空或超过 10 MB", "file_too_large")
    pages: list[str] = []
    try:
        if ext in {"txt", "md", "csv"}:
            if b"\0" in data:
                raise FileProcessingError("文本文件包含二进制内容")
            try: text = data.decode("utf-8-sig")
            except UnicodeDecodeError: text = data.decode("gb18030")
            if ext == "csv":
                text = "\n".join("\t".join(row) for row in csv.reader(io.StringIO(text)))
            pages = [text[i:i + SEGMENT_CHARS] for i in range(0, len(text), SEGMENT_CHARS)] or [""]
        elif ext == "pdf":
            try:
                from pypdf import PdfReader
                reader = PdfReader(io.BytesIO(data), strict=True)
                if reader.is_encrypted: raise FileProcessingError("不支持加密的 PDF", "encrypted_file")
                if len(reader.pages) > MAX_PDF_PAGES: raise FileProcessingError("PDF 页数超过 200 页", "file_resource_limit")
                pages = [(p.extract_text() or "") for p in reader.pages]
            except ImportError as e: raise FileProcessingError("PDF 解析组件未安装", "parser_unavailable") from e
        elif ext == "docx":
            with _zip(data) as z:
                if "word/vbaProject.bin" in z.namelist(): raise FileProcessingError("不支持含宏的文档")
                root = ElementTree.fromstring(z.read("word/document.xml"))
                ns = {"w": "http://schemas.openxmlformats.org/wordprocessingml/2006/main"}
                pages = ["\n".join("".join(t.itertext()) for t in p.findall(".//w:p", ns))]
        else:
            with _zip(data) as z:
                names = z.namelist()
                if any(n.endswith("vbaProject.bin") for n in names): raise FileProcessingError("不支持含宏的工作簿")
                wb = ElementTree.fromstring(z.read("xl/workbook.xml"))
                ns = {"m": "http://schemas.openxmlformats.org/spreadsheetml/2006/main", "r": "http://schemas.openxmlformats.org/officeDocument/2006/relationships"}
                sheets = wb.findall(".//m:sheets/m:sheet", ns)
                if len(sheets) > MAX_SHEETS: raise FileProcessingError("XLSX 工作表超过 10 个", "file_resource_limit")
                shared = []
                if "xl/sharedStrings.xml" in names:
                    sr = ElementTree.fromstring(z.read("xl/sharedStrings.xml"))
                    shared = ["".join(si.itertext()) for si in sr]
                relroot = ElementTree.fromstring(z.read("xl/_rels/workbook.xml.rels"))
                relns = {"r": "http://schemas.openxmlformats.org/package/2006/relationships"}
                rels = {x.attrib["Id"]: x.attrib["Target"] for x in relroot.findall("r:Relationship", relns)}
                for sheet in sheets:
                    target = rels.get(sheet.attrib.get("{" + ns["r"] + "}id"), "")
                    path = target.lstrip("/") if target.startswith("/") else posixpath.normpath(posixpath.join("xl", target))
                    if not path.startswith("xl/" ) or ".." in path.split("/"):
                        raise FileProcessingError("XLSX 文件结构无效")
                    root = ElementTree.fromstring(z.read(path))
                    rows = []
                    for row in root.findall(".//m:sheetData/m:row", ns):
                        if len(rows) >= MAX_ROWS: raise FileProcessingError("单个工作表超过 5,000 行", "file_resource_limit")
                        vals = []
                        for cell in row.findall("m:c", ns):
                            v = cell.find("m:v", ns)
                            value = "" if v is None else v.text or ""
                            if cell.attrib.get("t") == "s" and value.isdigit() and int(value) < len(shared): value = shared[int(value)]
                            inline = cell.find("m:is", ns)
                            if inline is not None: value = "".join(inline.itertext())
                            vals.append(value)
                        rows.append("\t".join(vals))
                    pages.append("工作表：" + sheet.attrib.get("name", "") + "\n" + "\n".join(rows))
    except FileProcessingError: raise
    except Exception as e: raise FileProcessingError("文件损坏或无法读取") from e
    flat = "\n\n".join(pages)
    segments = tuple(flat[i:i + SEGMENT_CHARS] for i in range(0, len(flat), SEGMENT_CHARS)) or ("",)
    return ProcessedFile(clean, ext, MIME[ext], segments, "ready" if flat.strip() else "empty")


def _worker(data: bytes, filename: str, pipe) -> None:
    try:
        p = _process_file(data, filename)
        pipe.send(("ok", p.filename, p.extension, p.mime, p.pages, p.text_status))
    except FileProcessingError as e:
        pipe.send(("error", e.message, e.code))
    except BaseException:
        pipe.send(("error", "文件损坏或无法读取", "invalid_file"))
    finally:
        pipe.close()


def process_file(data: bytes, filename: str) -> ProcessedFile:
    """Use a disposable worker so malformed documents cannot exceed parser wall time."""
    parent, child = multiprocessing.Pipe(duplex=False)
    proc = multiprocessing.get_context("spawn").Process(target=_worker, args=(data, filename, child), daemon=True)
    proc.start(); child.close()
    try:
        if not parent.poll(15):
            proc.terminate(); proc.join(timeout=1)
            raise FileProcessingError("文件解析超时，请尝试较小或较简单的文件", "parser_timeout")
        result = parent.recv()
        proc.join(timeout=1)
        if result[0] == "error":
            raise FileProcessingError(result[1], result[2])
        return ProcessedFile(*result[1:])
    finally:
        parent.close()
        if proc.is_alive(): proc.terminate(); proc.join(timeout=1)
