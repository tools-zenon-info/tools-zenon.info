FROM python:3.11-slim

WORKDIR /app
RUN pip install --no-cache-dir requests

COPY nom_data_refiner /app/nom_data_refiner

CMD ["python", "-u", "nom_data_refiner/main.py"]
