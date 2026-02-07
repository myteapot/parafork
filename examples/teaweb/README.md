# teaweb

Static page + a small Python backend.

## Run

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python -m uvicorn main:app --reload --host 127.0.0.1 --port 8000
```

Windows PowerShell:

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
python -m uvicorn main:app --reload --host 127.0.0.1 --port 8000
```

Then open:

- http://127.0.0.1:8000/

## API

- `GET /api/regions`
- `GET /api/products?region=Fujian&q=%E8%82%89%E6%A1%82`
- `POST /api/newsletter/subscribe` `{ "email": "you@example.com" }`
- `POST /api/checkout/quote` `{ "items": [{"id":"fj-rougui","qty":1}] }`
- `POST /api/checkout` `{ "items": [...] }`
