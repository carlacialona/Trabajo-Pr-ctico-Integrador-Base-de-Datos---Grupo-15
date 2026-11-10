FROM python:3.12-slim
WORKDIR /seed
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY cargar_datos.py .
COPY catalogos ./catalogos
CMD ["python", "cargar_datos.py", "--si-vacia"]
