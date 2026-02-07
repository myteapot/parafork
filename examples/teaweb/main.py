from __future__ import annotations

import json
import re
import sqlite3
import time
import uuid
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import FileResponse
from pydantic import BaseModel, Field


# Keep the product catalog in sync with index.html.
@dataclass(frozen=True)
class Region:
    key: str
    label: str


@dataclass(frozen=True)
class Product:
    id: str
    name: str
    region: str
    style: str
    price: int
    weight: str
    tasting: List[str]
    note: str


REGIONS: List[Region] = [
    Region(key="Fujian", label="福建"),
    Region(key="Yunnan", label="云南"),
    Region(key="Zhejiang", label="浙江"),
    Region(key="Taiwan", label="台湾"),
    Region(key="SriLanka", label="斯里兰卡"),
    Region(key="Assam", label="印度·阿萨姆"),
]


PRODUCTS: List[Product] = [
    Product(
        id="fj-rougui",
        name="武夷肉桂",
        region="Fujian",
        style="乌龙·岩茶",
        price=68,
        weight="50g",
        tasting=["桂皮香", "焙火", "岩韵"],
        note="香气辛甜，汤感饱满，回甘利落。",
    ),
    Product(
        id="fj-baimudan",
        name="白牡丹",
        region="Fujian",
        style="白茶",
        price=58,
        weight="50g",
        tasting=["花香", "清甜", "柔润"],
        note="花香清雅，入口甘润，适合日常。",
    ),
    Product(
        id="yn-lincang-shu",
        name="临沧古树熟普",
        region="Yunnan",
        style="普洱·熟茶",
        price=88,
        weight="100g",
        tasting=["醇滑", "糯甜", "陈香"],
        note="汤感厚而不闷，甜度稳定，耐泡。",
    ),
    Product(
        id="yn-dianhong",
        name="凤庆滇红",
        region="Yunnan",
        style="红茶",
        price=62,
        weight="60g",
        tasting=["蜜香", "红薯甜", "暖意"],
        note="蜜香明显，适合秋冬，亦可加奶。",
    ),
    Product(
        id="zj-longjing",
        name="明前龙井",
        region="Zhejiang",
        style="绿茶",
        price=98,
        weight="50g",
        tasting=["豆香", "鲜爽", "清甜"],
        note="鲜爽度高，豆香显，尾段回甘清晰。",
    ),
    Product(
        id="tw-gaoshan",
        name="高山乌龙",
        region="Taiwan",
        style="乌龙",
        price=92,
        weight="50g",
        tasting=["兰花香", "奶香", "甘润"],
        note="花香高扬，汤水细，冷泡也出彩。",
    ),
    Product(
        id="slk-ceylon",
        name="锡兰柑橘红茶",
        region="SriLanka",
        style="红茶",
        price=72,
        weight="60g",
        tasting=["柑橘", "清亮", "冷泡"],
        note="果香干净，适合做冰红茶或冷泡。",
    ),
    Product(
        id="in-assam",
        name="阿萨姆 CTC",
        region="Assam",
        style="红茶",
        price=55,
        weight="80g",
        tasting=["麦芽香", "浓强", "奶茶"],
        note="适合奶茶基底：浓、厚、香。",
    ),
]


PRODUCT_BY_ID: Dict[str, Product] = {p.id: p for p in PRODUCTS}


ROOT = Path(__file__).resolve().parent
DB_PATH = ROOT / "teaweb.db"


def _db() -> sqlite3.Connection:
    # A short-lived connection keeps the code simple and safe for reload/dev.
    conn = sqlite3.connect(DB_PATH)
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA foreign_keys=ON")
    return conn


def init_db() -> None:
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    with _db() as conn:
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS newsletter (
              email TEXT PRIMARY KEY,
              created_at INTEGER NOT NULL
            )
            """
        )
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS orders (
              order_id TEXT PRIMARY KEY,
              created_at INTEGER NOT NULL,
              total INTEGER NOT NULL,
              payload_json TEXT NOT NULL
            )
            """
        )


class NewsletterIn(BaseModel):
    email: str = Field(..., min_length=3, max_length=254)


class CheckoutItem(BaseModel):
    id: str
    qty: int = Field(..., ge=1, le=99)


class CheckoutIn(BaseModel):
    items: List[CheckoutItem] = Field(..., min_length=1)
    email: Optional[str] = Field(default=None, max_length=254)


def _normalize_query(s: str) -> str:
    return s.strip().lower()


def _matches_query(p: Product, q: str) -> bool:
    if not q:
        return True
    hay = f"{p.name} {p.style} {p.weight} {' '.join(p.tasting)} {p.note}".lower()
    return q in hay


EMAIL_RE = re.compile(r"^[^\s@]+@[^\s@]+\.[^\s@]+$")


def _validate_email(email: str) -> str:
    e = email.strip()
    if not EMAIL_RE.match(e):
        raise HTTPException(status_code=422, detail="Invalid email")
    return e


def _compute_quote(items: List[CheckoutItem]) -> Dict[str, Any]:
    subtotal = 0
    normalized_items: List[Dict[str, Any]] = []
    for it in items:
        p = PRODUCT_BY_ID.get(it.id)
        if not p:
            raise HTTPException(status_code=400, detail=f"Unknown product id: {it.id}")
        line = p.price * it.qty
        subtotal += line
        normalized_items.append(
            {
                "id": p.id,
                "name": p.name,
                "qty": it.qty,
                "unit_price": p.price,
                "line_total": line,
            }
        )

    shipping = 0 if subtotal >= 199 else 12
    total = subtotal + shipping
    return {
        "currency": "CNY",
        "subtotal": subtotal,
        "shipping": shipping,
        "total": total,
        "free_shipping_threshold": 199,
        "items": normalized_items,
    }


app = FastAPI(title="teaweb backend", version="0.1.0")


@app.on_event("startup")
def _startup() -> None:
    init_db()


@app.get("/healthz")
def healthz() -> Dict[str, str]:
    return {"status": "ok"}


@app.get("/api/regions")
def list_regions() -> List[Dict[str, str]]:
    return [asdict(r) for r in REGIONS]


@app.get("/api/products")
def list_products(region: Optional[str] = None, q: Optional[str] = None) -> List[Dict[str, Any]]:
    qn = _normalize_query(q or "")
    out: List[Dict[str, Any]] = []
    for p in PRODUCTS:
        if region and p.region != region:
            continue
        if not _matches_query(p, qn):
            continue
        out.append(asdict(p))
    return out


@app.get("/api/products/{product_id}")
def get_product(product_id: str) -> Dict[str, Any]:
    p = PRODUCT_BY_ID.get(product_id)
    if not p:
        raise HTTPException(status_code=404, detail="Not found")
    return asdict(p)


@app.post("/api/newsletter/subscribe")
def newsletter_subscribe(payload: NewsletterIn, request: Request) -> Dict[str, Any]:
    email = _validate_email(payload.email)
    created_at = int(time.time())
    with _db() as conn:
        # Upsert behavior: subscribing twice is ok.
        conn.execute(
            "INSERT INTO newsletter(email, created_at) VALUES(?, ?) "
            "ON CONFLICT(email) DO UPDATE SET created_at=excluded.created_at",
            (email, created_at),
        )
    return {"ok": True, "email": email, "created_at": created_at}


@app.post("/api/checkout/quote")
def checkout_quote(payload: CheckoutIn) -> Dict[str, Any]:
    return _compute_quote(payload.items)


@app.post("/api/checkout")
def checkout(payload: CheckoutIn) -> Dict[str, Any]:
    if payload.email is not None:
        _validate_email(payload.email)

    quote = _compute_quote(payload.items)
    order_id = uuid.uuid4().hex
    created_at = int(time.time())
    to_store = {
        "order_id": order_id,
        "created_at": created_at,
        "email": payload.email,
        "quote": quote,
    }
    with _db() as conn:
        conn.execute(
            "INSERT INTO orders(order_id, created_at, total, payload_json) VALUES(?, ?, ?, ?)",
            (order_id, created_at, int(quote["total"]), json.dumps(to_store, ensure_ascii=True)),
        )
    return {"ok": True, "order_id": order_id, **quote}


@app.get("/api/orders/{order_id}")
def get_order(order_id: str) -> Dict[str, Any]:
    with _db() as conn:
        row = conn.execute(
            "SELECT payload_json FROM orders WHERE order_id = ?",
            (order_id,),
        ).fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="Not found")
    return json.loads(row[0])


@app.get("/", include_in_schema=False)
def index() -> FileResponse:
    path = ROOT / "index.html"
    if not path.exists():
        raise HTTPException(status_code=404, detail="index.html not found")
    return FileResponse(path)


@app.get("/index.html", include_in_schema=False)
def index_alias() -> FileResponse:
    return index()
