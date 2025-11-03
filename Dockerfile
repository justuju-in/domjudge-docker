FROM domjudge/domserver:8.2.3

RUN apt-get update && \
    apt-get install -y php8.2-redis && \
    rm -rf /var/lib/apt/lists/*

RUN phpenmod redis
RUN service php8.2-fpm restart
