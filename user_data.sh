#!/bin/bash

# RDS instance access
WORDPRESS_DB_ADMIN="your_rds_admin_username"
WORDPRESS_DB_ADMIN_PASSWORD="your_rds_admin_password"

# WordPress database credentials
WORDPRESS_DB_HOST="your_rds_endpoint"
WORDPRESS_DB_USER="wordpress_user"
WORDPRESS_DB_PASSWORD="wordpress_password"
WORDPRESS_DB_NAME="wordpress_db"

WORKDIR=/home/ec2-user
EFS_ID="your_efs_id"

# Update and install necessary packages
dnf update -y
dnf install -y \
    docker \
    mariadb105 \
    amazon-efs-utils

# Docker compose installation
COMPOSE_DIR=/usr/local/lib/docker/cli-plugins
mkdir -p $COMPOSE_DIR
curl -SL https://github.com/docker/compose/releases/download/v2.36.2/docker-compose-linux-x86_64 -o $COMPOSE_DIR/docker-compose
chmod +x $COMPOSE_DIR/docker-compose

# Start and enable Docker service
systemctl start docker
systemctl enable --now docker

# Add ec2-user to the docker group
usermod -a -G docker ec2-user

# Create WordPress user
mysql -h "$WORDPRESS_DB_HOST" -u "$WORDPRESS_DB_ADMIN" -p"$WORDPRESS_DB_ADMIN_PASSWORD" <<EOF
CREATE USER IF NOT EXISTS '$WORDPRESS_DB_USER'@'%' IDENTIFIED BY '$WORDPRESS_DB_PASSWORD';
GRANT ALL PRIVILEGES ON '$WORDPRESS_DB_NAME'.* TO '$WORDPRESS_DB_USER'@'%';
FLUSH PRIVILEGES;
EOF

# Mount EFS
sudo mkdir -p /mnt/efs
sudo mount -t efs -o tls $EFS_ID:/ /mnt/efs
sudo chown -R 33:33 /mnt/efs  # UID do www-data

# Create Docker Compose file
cat << EOF > $WORKDIR/compose.yaml
services:
  wordpress:
    image: wordpress
    restart: always
    ports:
      - 80:80
    environment:
      WORDPRESS_DB_HOST: ${WORDPRESS_DB_HOST}
      WORDPRESS_DB_USER: ${WORDPRESS_DB_USER}
      WORDPRESS_DB_PASSWORD: ${WORDPRESS_DB_PASSWORD}
      WORDPRESS_DB_NAME: ${WORDPRESS_DB_NAME}
    volumes:
      - /mnt/efs:/var/www/html/
EOF

# Wait for Docker to start
echo "Aguardando Docker iniciar..."
while ! docker info &>/dev/null; do sleep 2; done

# Start Docker Compose
su - ec2-user -c "$COMPOSE_DIR/docker-compose -f /home/ec2-user/compose.yaml up -d"

# vim: ts=4 sts=4 sw=4 et nowrap:
