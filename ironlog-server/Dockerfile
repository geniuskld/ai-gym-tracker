FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app/ app/
COPY tools/ tools/

# schemas/ is mounted as /schemas via docker-compose volume
RUN addgroup --system appgroup && adduser --system --ingroup appgroup appuser \
    && chown -R appuser:appgroup /app
USER appuser

CMD ["uvicorn", "app.main:app", "--proxy-headers", "--forwarded-allow-ips=172.16.0.0/12", "--host", "0.0.0.0", "--port", "8000"]
