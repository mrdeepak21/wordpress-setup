#!/bin/bash

# Ask for MySQL root password
read -s -p "Enter MySQL root password: " MYSQL_ROOT_PASSWORD
echo

# Ask for WordPress database details
read -p "Enter WordPress database name: " WP_DB_NAME
read -p "Enter WordPress database user: " WP_DB_USER
read -s -p "Enter WordPress database password: " WP_DB_PASSWORD
echo

# Ask if SSL should be installed
read -p "Do you want to install SSL with Let's Encrypt? (yes/no): " INSTALL_SSL
if [[ "$INSTALL_SSL" == "yes" ]]; then
    read -p "Enter your domain (e.g., example.com): " DOMAIN
    read -p "Enter admin email for Let's Encrypt: " ADMIN_EMAIL
else
    read -p "Enter your server's public IP address: " PUBLIC_IP
fi

# Update and upgrade the system
sudo apt update && sudo apt upgrade -y

# Install necessary packages
sudo apt install -y nginx mariadb-server php-fpm php-mysql php-curl php-gd php-mbstring php-xml php-xmlrpc php-soap php-intl php-zip curl redis-server php-redis php-imagick unzip php-common php-cli




# Detect the installed PHP version
PHP_VERSION=$(php -v | grep -oP 'PHP \K[0-9]+\.[0-9]+')
PHP_FPM_SOCKET="/var/run/php/php${PHP_VERSION}-fpm.sock"
echo "Detected PHP version: $PHP_VERSION"
echo "PHP-FPM socket: $PHP_FPM_SOCKET"

# Secure MariaDB installation
sudo mysql_secure_installation <<EOF

y
$MYSQL_ROOT_PASSWORD
$MYSQL_ROOT_PASSWORD
y
y
y
y
EOF

# Create a MySQL database and user for WordPress
sudo mysql -u root -p"$MYSQL_ROOT_PASSWORD" <<EOF
CREATE DATABASE $WP_DB_NAME;
CREATE USER '$WP_DB_USER'@'localhost' IDENTIFIED BY '$WP_DB_PASSWORD';
GRANT ALL PRIVILEGES ON $WP_DB_NAME.* TO '$WP_DB_USER'@'localhost';
FLUSH PRIVILEGES;
EOF

# Download and extract WordPress
cd /tmp
curl -O https://wordpress.org/latest.tar.gz
tar xzvf latest.tar.gz

# Move WordPress files to the appropriate directory
if [[ "$INSTALL_SSL" == "yes" ]]; then
    WORDPRESS_DIR="/var/www/$DOMAIN"
else
    WORDPRESS_DIR="/var/www/wordpress"
fi
sudo mv wordpress $WORDPRESS_DIR

# Set proper permissions
sudo chown -R www-data:www-data $WORDPRESS_DIR
sudo chmod -R 755 $WORDPRESS_DIR

# Configure Nginx for WordPress
if [[ "$INSTALL_SSL" == "yes" ]]; then
    # Use HTTPS configuration
    sudo tee /etc/nginx/sites-available/$DOMAIN <<EOF
server {
    listen 80;
    server_name $DOMAIN;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    server_name $DOMAIN;

    root $WORDPRESS_DIR;
    index index.php index.html index.htm;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:$PHP_FPM_SOCKET;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }

    location = /favicon.ico {
        log_not_found off;
        access_log off;
    }

    location = /robots.txt {
        allow all;
        log_not_found off;
        access_log off;
    }

    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg)\$ {
        expires max;
        log_not_found off;
    }

    # Enable Gzip compression
    gzip on;
    gzip_min_length 256;
    gzip_types
      application/atom+xml
      application/geo+json
      application/javascript
      application/x-javascript
      application/json
      application/ld+json
      application/manifest+json
      application/rdf+xml
      application/rss+xml
      application/xhtml+xml
      application/xml
      font/eot
      font/otf
      font/ttf
      image/svg+xml
      text/css
      text/javascript
      text/plain
      text/xml;
}
EOF
    # Enable the site
    sudo ln -s /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/
else
    # Use HTTP configuration with public IP
    sudo tee /etc/nginx/sites-available/wordpress <<EOF
server {
    listen 80;
    server_name $PUBLIC_IP;

    root $WORDPRESS_DIR;
    index index.php index.html index.htm;

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:$PHP_FPM_SOCKET;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }

    location = /favicon.ico {
        log_not_found off;
        access_log off;
    }

    location = /robots.txt {
        allow all;
        log_not_found off;
        access_log off;
    }

    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg)\$ {
        expires max;
        log_not_found off;
    }

    # Enable Gzip compression
    gzip on;
    gzip_min_length 256;
    gzip_types
      application/atom+xml
      application/geo+json
      application/javascript
      application/x-javascript
      application/json
      application/ld+json
      application/manifest+json
      application/rdf+xml
      application/rss+xml
      application/xhtml+xml
      application/xml
      font/eot
      font/otf
      font/ttf
      image/svg+xml
      text/css
      text/javascript
      text/plain
      text/xml;
}
EOF
    # Enable the site
    sudo ln -s /etc/nginx/sites-available/wordpress /etc/nginx/sites-enabled/
fi

# Remove default Nginx site
sudo unlink /etc/nginx/sites-enabled/default

# Modify PHP configuration
sudo sed -i 's/^;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/' /etc/php/$PHP_VERSION/fpm/php.ini
sudo sed -i 's/^upload_max_filesize = .*/upload_max_filesize = 32M/' /etc/php/$PHP_VERSION/fpm/php.ini
sudo sed -i 's/^post_max_size = .*/post_max_size = 512M/' /etc/php/$PHP_VERSION/fpm/php.ini
sudo sed -i 's/^memory_limit = .*/memory_limit = 512M/' /etc/php/$PHP_VERSION/fpm/php.ini
sudo sed -i 's/^max_execution_time = .*/max_execution_time = 300/' /etc/php/$PHP_VERSION/fpm/php.ini
sudo sed -i 's/^max_input_time = .*/max_input_time = 300/' /etc/php/$PHP_VERSION/fpm/php.ini
sudo sed -i 's/^max_input_vars = .*/max_input_vars = 10000/' /etc/php/$PHP_VERSION/fpm/php.ini

# Configure Redis
sudo sed -i 's/^# maxmemory .*/maxmemory 256mb/' /etc/redis/redis.conf
sudo sed -i 's/^# maxmemory-policy .*/maxmemory-policy allkeys-lru/' /etc/redis/redis.conf

# Enable auto-restart for services
sudo systemctl enable nginx php$PHP_VERSION-fpm mysql redis-server
sudo systemctl restart nginx php$PHP_VERSION-fpm mysql redis-server

# Install Let's Encrypt SSL if enabled
if [[ "$INSTALL_SSL" == "yes" ]]; then
    sudo apt install -y certbot python3-certbot-nginx
    sudo certbot --nginx --non-interactive --agree-tos --redirect --email $ADMIN_EMAIL -d $DOMAIN
    echo "SSL installed successfully!"
    # Set up auto-renewal
    (crontab -l 2>/dev/null; echo "0 12 * * * /usr/bin/certbot renew --quiet") | crontab -
    echo "SSL auto-renewal configured."
fi

# Enable and configure UFW
sudo ufw allow OpenSSH
sudo ufw allow 'Nginx Full'
sudo ufw --force enable
echo "UFW enabled with OpenSSH and Nginx Full rules."

# Output the WordPress installation details
echo "WordPress has been installed successfully!"
echo "Database Name: $WP_DB_NAME"
echo "Database User: $WP_DB_USER"
echo "Database Password: $WP_DB_PASSWORD"
if [[ "$INSTALL_SSL" == "yes" ]]; then
    echo "Please visit https://$DOMAIN to complete the WordPress setup."
else
    echo "Please visit http://$PUBLIC_IP to complete the WordPress setup."
fi