FROM python:3.12-alpine
WORKDIR /app
COPY index.html server.py status.js ./
USER 10001
EXPOSE 8080
CMD ["python", "server.py"]
