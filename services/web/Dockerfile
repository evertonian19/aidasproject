FROM python:3.10-slim

ENV PYTHONUNBUFFERED=1
ENV PYTHONPATH=/app

WORKDIR /app

RUN mkdir -p /var/log/aidas

COPY services/web/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY services/web/ .

EXPOSE 8000

CMD ["python", "-m", "uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]