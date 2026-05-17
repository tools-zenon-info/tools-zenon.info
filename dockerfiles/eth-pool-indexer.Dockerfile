FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY eth_pool_indexer /app/eth_pool_indexer

CMD ["python", "-u", "eth_pool_indexer/main.py"]
