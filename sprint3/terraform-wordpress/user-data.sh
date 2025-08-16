#!/bin/bash

# Atualizar o sistema
dnf update -y

# Instalar Docker
dnf install -y docker
systemctl start docker
systemctl enable docker
usermod -a -G docker ec2-user

# Instalar Docker Compose
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Instalar utilitários NFS para EFS
dnf install -y amazon-efs-utils

# Criar diretório para montar o EFS
mkdir -p /mnt/efs/wordpress

# Montar o EFS
echo '${efs_id}.efs.${aws_region}.amazonaws.com:/ /mnt/efs/wordpress nfs4 nfsvers=4.1,rsize=1048576,wsize=1048576,hard,intr,timeo=600,retrans=2 0 0' >> /etc/fstab
mount -a

# Aguardar alguns segundos para garantir que o EFS esteja montado
sleep 10

# Criar diretório para os dados do WordPress no EFS
mkdir -p /mnt/efs/wordpress/wp-content

# Criar diretório local para o Docker Compose
mkdir -p /home/ec2-user/wordpress
cd /home/ec2-user/wordpress

# Criar o arquivo docker-compose.yml
cat << 'EOF' > docker-compose.yml
version: '3.8'

services:
  wordpress:
    image: wordpress:latest
    container_name: wordpress
    restart: always
    ports:
      - "80:80"
    environment:
      WORDPRESS_DB_HOST: ${rds_endpoint}
      WORDPRESS_DB_USER: ${db_user}
      WORDPRESS_DB_PASSWORD: ${db_password}
      WORDPRESS_DB_NAME: ${db_name}
      WORDPRESS_TABLE_PREFIX: wp_
    volumes:
      - /mnt/efs/wordpress/wp-content:/var/www/html/wp-content
    depends_on:
      - db-check
    networks:
      - wordpress-net

  db-check:
    image: mysql:8.0
    container_name: db-check
    command: >
      sh -c "
        echo 'Aguardando conexão com o banco de dados...' &&
        until mysql -h ${rds_endpoint} -u ${db_user} -p'${db_password}' -e 'SELECT 1'; do
          echo 'Banco não disponível, aguardando...';
          sleep 5;
        done;
        echo 'Banco de dados disponível!';
        exit 0;
      "
    networks:
      - wordpress-net

networks:
  wordpress-net:
    driver: bridge
EOF

# Definir permissões corretas
chown -R ec2-user:ec2-user /home/ec2-user/wordpress
chmod -R 755 /mnt/efs/wordpress

# Aguardar Docker estar completamente inicializado
sleep 15

# Iniciar os containers
cd /home/ec2-user/wordpress
/usr/local/bin/docker-compose up -d

# Aguardar os containers iniciarem
sleep 30

# Verificar se os containers estão rodando
docker ps

# Log para verificação
echo "WordPress deployment iniciado em $(date)" >> /var/log/user-data.log
echo "EFS montado: $(df -h | grep efs)" >> /var/log/user-data.log
echo "Containers Docker: $(docker ps --format 'table {{.Names}}\t{{.Status}}')" >> /var/log/user-data.log

# Criar script de verificação de saúde
cat << 'EOF' > /home/ec2-user/health-check.sh
#!/bin/bash
# Script de verificação de saúde para o WordPress

# Verificar se o container WordPress está rodando
if ! docker ps | grep -q wordpress; then
    echo "Container WordPress não está rodando. Reiniciando..."
    cd /home/ec2-user/wordpress
    /usr/local/bin/docker-compose restart
    exit 1
fi

# Verificar se o WordPress responde na porta 80
if ! curl -f -s http://localhost:80 > /dev/null; then
    echo "WordPress não está respondendo na porta 80"
    exit 1
fi

echo "WordPress está funcionando corretamente"
exit 0
EOF

chmod +x /home/ec2-user/health-check.sh

# Adicionar cron job para verificação de saúde a cada 5 minutos
echo "*/5 * * * * /home/ec2-user/health-check.sh >> /var/log/wordpress-health.log 2>&1" | crontab -u ec2-user -

# Configurar logrotate para os logs
cat << 'EOF' > /etc/logrotate.d/wordpress
/var/log/user-data.log /var/log/wordpress-health.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
}
EOF

echo "User-data script finalizado com sucesso em $(date)" >> /var/log/user-data.log