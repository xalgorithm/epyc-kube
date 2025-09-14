# WordPress with WP-CLI
FROM wordpress:latest

# Install dependencies for WP-CLI
RUN apt-get update && \
    # Try different MySQL client packages for Debian Trixie
    (apt-get install -y curl less default-mysql-client || \
     apt-get install -y curl less mariadb-client || \
     apt-get install -y curl less mysql-client || \
     apt-get install -y curl less) && \
    rm -rf /var/lib/apt/lists/*

# Install WP-CLI
RUN curl -O https://raw.githubusercontent.com/wp-cli/wp-cli/v2.8.1/utils/wp-cli.phar \
    && chmod +x wp-cli.phar \
    && mv wp-cli.phar /usr/local/bin/wp

# Verify WP-CLI installation
RUN wp --info --allow-root

# Create wp-cli config directory
RUN mkdir -p /var/www/.wp-cli && chown www-data:www-data /var/www/.wp-cli

# Set working directory
WORKDIR /var/www/html

# Copy custom wp-cli config if needed
COPY wp-cli.yml /var/www/html/wp-cli.yml

# Ensure proper permissions
RUN chown -R www-data:www-data /var/www/html