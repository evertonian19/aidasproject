#/home/user1/aidas/services/web/main.py
import logging
from fastapi import FastAPI, Depends, Request
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates
from sqlalchemy.orm import Session
from app.db import engine, Base, get_db
from models import Product

from app.routers import incidents



logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] AIDAS_WEB - %(message)s"
)
logger = logging.getLogger("aidas")

Base.metadata.create_all(bind=engine)
app = FastAPI(title="AIDAS Web Architecture")

app.include_router(incidents.router, prefix="/api/v1")



templates = Jinja2Templates(directory="app/templates")

@app.on_event("startup")
def seed_data():
    db = next(get_db())
    if db.query(Product).count() == 0:
        sample_products = [
            Product(product_name="[SRE] 하이브리드 관제 가이드북", price=25000, stock_quantity=50),
            Product(product_name="[보안] Tailscale VPN 전용 라우터", price=128000, stock_quantity=15),
            Product(product_name="[컨테이너] 도커 핵심 가이드노트", price=32000, stock_quantity=100),
        ]
        db.add_all(sample_products)
        db.commit()

# ① 통합 대문 라우터
@app.get("/", response_class=HTMLResponse)
def get_index_page(request: Request):
    return templates.TemplateResponse("index.html", {"request": request})

@app.get("/api/v1/products")
def get_products(db: Session = Depends(get_db)):
    return db.query(Product).all()

# ② 쇼핑몰 화면 라우터
@app.get("/user", response_class=HTMLResponse)
def get_user_page(request: Request, db: Session = Depends(get_db)):
    products = db.query(Product).all()
    return templates.TemplateResponse("user.html", {"request": request, "products": products})

# ③ 제어판 화면 라우터
@app.get("/admin", response_class=HTMLResponse)
def get_admin_page(request: Request):
    return templates.TemplateResponse("admin.html", {"request": request})

# main.py 파일에 추가
@app.get("/monitoring", response_class=HTMLResponse)
def get_monitoring_page(request: Request):
    return templates.TemplateResponse("monitoring.html", {"request": request})