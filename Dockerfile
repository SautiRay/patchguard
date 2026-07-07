FROM python:3.12-slim

WORKDIR /app

RUN apt-get update && apt-get install -y \
    openssh-client \
    ansible \
    && rm -rf /var/lib/apt/lists/*

COPY src/api/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 8000

CMD ["uvicorn", "src.api.main:app", "--host", "0.0.0.0", "--port", "8000"]
