FROM python:3.12-slim
WORKDIR /app
COPY argos_scholar_gateway.py /app/argos_scholar_gateway.py
ENV PORT=8080
EXPOSE 8080
CMD ["python3", "-u", "/app/argos_scholar_gateway.py"]
