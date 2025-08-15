# WordPress em Alta Disponibilidade na AWS
## Documentação Completa do Projeto

- **Programa**: Fundamentos de AWS - DevSecOps

![Minha Imagem](imgs/logo.jpg)

---

## 1. Visão Geral do Projeto

Este projeto implementa uma arquitetura escalável e tolerante a falhas para o WordPress na AWS, utilizando múltiplas instâncias EC2 distribuídas em diferentes Availability Zones, com balanceamento de carga, armazenamento compartilhado e banco de dados gerenciado.

### 1.1 Objetivos
- Garantir alta disponibilidade e escalabilidade do WordPress
- Implementar tolerância a falhas
- Utilizar serviços gerenciados da AWS
- Simular ambiente de produção real
- Desenvolver competências em infraestrutura como código

### 1.2 Arquitetura Implementada
A solução utiliza uma arquitetura distribuída com os seguintes componentes:
- **Application Load Balancer (ALB)** para distribuição de tráfego
- **Auto Scaling Group (ASG)** com instâncias EC2 em subnets privadas
- **Amazon EFS** para armazenamento compartilhado de arquivos
- **Amazon RDS** para banco de dados MySQL gerenciado
- **VPC customizada** com múltiplas subnets e NAT Gateway

---

## 2. Componentes da Infraestrutura

### 2.1 Rede (VPC)
```
VPC: wordpress-vpc
CIDR: 10.0.0.0/16
Availability Zones: 2 (us-east-1a, us-east-1b)
```

**Subnets:**
- **Públicas (2)**: Para ALB e NAT Gateway
  - `wordpress-public-subnet-1`: 10.0.1.0/24 (us-east-1a)
  - `wordpress-public-subnet-2`: 10.0.2.0/24 (us-east-1b)
- **Privadas (4)**: Para EC2 e RDS
  - `wordpress-private-subnet-1`: 10.0.11.0/24 (us-east-1a) - EC2
  - `wordpress-private-subnet-2`: 10.0.12.0/24 (us-east-1b) - EC2
  - `wordpress-private-subnet-3`: 10.0.21.0/24 (us-east-1a) - RDS
  - `wordpress-private-subnet-4`: 10.0.22.0/24 (us-east-1b) - RDS

**Componentes de Conectividade:**
- **Internet Gateway (IGW)**: Acesso à internet para subnets públicas
- **NAT Gateway**: Acesso à internet para subnets privadas
- **Route Tables**: Roteamento configurado para cada subnet

### 2.2 Security Groups

#### ALB Security Group (SG-ALB)
```
INBOUND:
- HTTP (80) de 0.0.0.0/0

OUTBOUND:
- ALL TRAFFIC para 0.0.0.0/0
```

#### EC2 Security Group (SG-EC2)
```
INBOUND:
- HTTP (80) de SG-ALB
- NFS (2049) de SG-EFS
- MYSQL/Aurora (3306) de SG-RDS

OUTBOUND:
- ALL TCP para 0.0.0.0/0
- HTTPS (443) para 0.0.0.0/0
```

#### RDS Security Group (SG-RDS)
```
INBOUND:
- MYSQL (3306) de SG-EC2

OUTBOUND:
- ALL TRAFFIC para 0.0.0.0/0
```

#### EFS Security Group (SG-EFS)
```
INBOUND:
- NFS (2049) de SG-EC2

OUTBOUND:
- ALL TRAFFIC para 0.0.0.0/0
```

---

## 3. Configuração dos Serviços

### 3.1 Amazon RDS
**Configuração do Banco de Dados:**
```
Engine: MySQL 8.0
Instance Class: db.t3g.micro
Endpoint: wordpress-rds.XXXXXXXXXXXX.us-east-1.rds.amazonaws.com
Database Name: wordpress
Username: admin
Password: password
Multi-AZ: Desabilitado (limitação da conta de estudos)
Subnets: Private Subnets (3 e 4)
```

**Características:**
- Backup automatizado configurado
- Monitoramento via CloudWatch
- Security Group restritivo (apenas EC2)

### 3.2 Amazon EFS
**Configuração:**
```
File System ID: fs-XXXXXXXXXXXXXXXXX
Performance Mode: General Purpose
Throughput Mode: Provisioned
Mount Targets: Nas subnets privadas das EC2
```

**Utilização:**
- Armazenamento do diretório `wp-content` do WordPress
- Compartilhamento de arquivos entre instâncias EC2
- Montagem automática via user-data script

### 3.3 Application Load Balancer (ALB)
**Configuração:**
```
Scheme: Internet-facing
IP Address Type: IPv4
Subnets: Public Subnets (1 e 2)
Security Group: SG-ALB
Target Group: wordpress-tg
```

**Health Check:**
```
Protocol: HTTP
Path: /
Port: 80
Healthy Threshold: 2
Unhealthy Threshold: 3
Timeout: 10 segundos
Interval: 30 segundos
Success Codes: 200,302
```

### 3.4 Auto Scaling Group (ASG)
**Configuração:**
```
Launch Template: wordpress-launch-template
Min Size: 2
Desired Capacity: 2
Max Size: 6
Subnets: Private Subnets (1 e 2)
Target Group: wordpress-tg
```

**Scaling Policies:**
- Scale Out: CPU > 70% por 2 períodos consecutivos
- Scale In: CPU < 30% por 5 períodos consecutivos
- Cool Down: 300 segundos

---

## 4. User Data Script Completo

```bash
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
echo 'fs-0a279b706fa6dfa41.efs.us-east-1.amazonaws.com:/ /mnt/efs/wordpress nfs4 nfsvers=4.1,rsize=1048576,wsize=1048576,hard,intr,timeo=600,retrans=2 0 0' >> /etc/fstab
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
      WORDPRESS_DB_HOST: wordpress-rds.XXXXXXXXXXXX.us-east-1.rds.amazonaws.com:3306
      WORDPRESS_DB_USER: admin
      WORDPRESS_DB_PASSWORD: password
      WORDPRESS_DB_NAME: wordpress
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
        until mysql -h wordpress-rds.XXXXXXXXXXXX.us-east-1.rds.amazonaws.com -u admin -p'password' -e 'SELECT 1'; do
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
```

---

## 5. Launch Template

### 5.1 Configuração da Instância
```
AMI: Amazon Linux 2023 (ami-XXXXXXXXXXXXXXXXX)
Instance Type: t3.micro
Key Pair: wordpress-key
Security Groups: SG-EC2
```

### 5.2 Tags Obrigatórias
```
Name: wordpress-instance
CostCenter: DevSecOps-Training
Project: WordPress-HighAvailability
```

### 5.3 User Data
O script completo está incorporado no Launch Template, garantindo que todas as instâncias sejam configuradas automaticamente.

---

## 6. Processo de Deploy

### 6.1 Sequência de Criação
1. **VPC e Componentes de Rede**
   - VPC personalizada
   - Subnets públicas e privadas
   - Internet Gateway e NAT Gateway
   - Route Tables

2. **Security Groups**
   - Criação dos 4 security groups
   - Configuração das regras de entrada e saída

3. **Amazon RDS**
   - DB Subnet Group
   - Instância RDS MySQL
   - Configuração de segurança

4. **Amazon EFS**
   - Sistema de arquivos EFS
   - Mount Targets nas subnets privadas
   - Access Points (opcional)

5. **Launch Template**
   - Template com user-data script
   - Configurações de instância
   - Tags obrigatórias

6. **Application Load Balancer**
   - ALB nas subnets públicas
   - Target Group
   - Health Check configuration

7. **Auto Scaling Group**
   - ASG com Launch Template
   - Políticas de escalamento
   - Associação com Target Group

### 6.2 Verificação do Deploy
Após o deploy, verificar:
- [ ] Instâncias EC2 saudáveis no Target Group
- [ ] WordPress acessível via ALB
- [ ] EFS montado corretamente
- [ ] Conectividade com RDS
- [ ] Logs do user-data sem erros

---

## 7. Operação e Manutenção

### 7.1 Comandos de Diagnóstico
```bash
# Verificar containers Docker
docker ps -a

# Ver logs do WordPress
docker logs wordpress -f

# Verificar montagem do EFS
df -h | grep efs

# Testar conectividade com RDS
telnet wordpress-rds.XXXXXXXXXXXX.us-east-1.rds.amazonaws.com 3306

# Verificar health check
tail -f /var/log/wordpress-health.log
```

### 7.2 Logs Importantes
- **User Data**: `/var/log/user-data.log`
- **Health Check**: `/var/log/wordpress-health.log`
- **WordPress**: `docker logs wordpress`
- **CloudWatch**: Métricas de CPU, memória e rede

### 7.3 Solução de Problemas Comuns

#### 502 Bad Gateway
- Verificar saúde das instâncias EC2
- Confirmar que WordPress está rodando na porta 80
- Verificar conectividade com RDS
- Analisar logs do ALB

#### Instâncias Unhealthy
- Verificar Security Groups
- Confirmar montagem do EFS
- Verificar conectividade com RDS
- Analisar user-data logs

#### Falhas no Auto Scaling
- Verificar Launch Template
- Confirmar quotas de instâncias EC2
- Verificar availability de recursos na AZ

---

## 8. Monitoramento

### 8.1 CloudWatch Metrics
**Métricas do ALB:**
- `RequestCount`
- `TargetResponseTime`
- `HTTPCode_Target_2XX_Count`
- `HTTPCode_Target_5XX_Count`

**Métricas do ASG:**
- `GroupMinSize`, `GroupMaxSize`, `GroupDesiredCapacity`
- `GroupInServiceInstances`

**Métricas do RDS:**
- `DatabaseConnections`
- `CPUUtilization`
- `FreeableMemory`

### 8.2 CloudWatch Alarms (Recomendados)
- CPU alta nas instâncias EC2 (>80%)
- Target 5XX errors no ALB (>10)
- RDS CPU utilization (>80%)
- EFS connection errors

---

## 9. Segurança

### 9.1 Implementações de Segurança
- **Network Isolation**: Instâncias EC2 em subnets privadas
- **Security Groups**: Regras restritivas por serviço
- **RDS**: Acesso apenas das instâncias EC2
- **EFS**: Acesso controlado via Security Groups
- **ALB**: Exposto apenas na porta 80

### 9.2 Recomendações Adicionais
- Implementar HTTPS com certificado SSL/TLS
- Usar AWS WAF para proteção de aplicação web
- Configurar VPC Flow Logs
- Implementar backup automatizado do EFS
- Usar AWS Secrets Manager para credenciais do banco

---

## 10. Custos e Otimização

### 10.1 Recursos que Geram Custos
- **EC2 Instances**: t3.micro (2-6 instâncias)
- **RDS**: db.t3g.micro MySQL
- **EFS**: Armazenamento + throughput
- **ALB**: Horas de execução + LCUs
- **NAT Gateway**: Dados processados
- **Data Transfer**: Entre AZs e para internet

### 10.2 Práticas de Otimização
- Monitorar utilização via Cost Explorer
- Usar Reserved Instances para cargas previsíveis
- Configurar auto scaling adequado
- Implementar lifecycle policies no EFS
- Monitorar data transfer costs

---

## 11. Limitações da Conta de Estudos

### 11.1 Restrições Identificadas
- **RDS**: Apenas db.t3g.micro, sem Multi-AZ
- **EC2**: Tags obrigatórias (Name, CostCenter, Project)
- **Recursos Limitados**: Quotas reduzidas
- **Tempo**: Recursos devem ser excluídos após estudos

### 11.2 Workarounds Implementados
- RDS sem Multi-AZ (compensado pelo ASG multi-AZ)
- Monitoramento via scripts próprios
- Configurações simplificadas mas funcionais

---

## 12. Melhorias Futuras

### 12.1 Arquitetura de Produção
Para um ambiente de produção real, considerar:
- **Route 53**: DNS gerenciado e health checks
- **CloudFront**: CDN para conteúdo estático
- **ElastiCache**: Cache Redis/Memcached
- **RDS Multi-AZ**: Alta disponibilidade do banco
- **AWS WAF**: Proteção contra ataques web
- **CloudFormation/Terraform**: Infraestrutura como código

### 12.2 Funcionalidades Adicionais
- **SSL/TLS**: Certificados via ACM
- **Backup**: AWS Backup para RDS e EFS
- **Monitoring**: Enhanced monitoring e custom metrics
- **Logging**: Centralized logging com CloudWatch Logs
- **Security**: GuardDuty e Security Hub

---

## 13. Referências

- [AWS WordPress Reference Architecture](https://docs.aws.amazon.com/whitepapers/latest/best-practices-wordpress/welcome.html)
- [Amazon EFS User Guide](https://docs.aws.amazon.com/efs/)
- [Application Load Balancer User Guide](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/)
- [Amazon RDS User Guide](https://docs.aws.amazon.com/rds/)
- [Auto Scaling User Guide](https://docs.aws.amazon.com/autoscaling/ec2/)

---

## 14. Conclusão

Este projeto demonstra a implementação bem-sucedida de uma arquitetura WordPress altamente disponível na AWS, utilizando as melhores práticas de cloud computing. A solução atende aos requisitos de escalabilidade, tolerância a falhas e performance, servindo como base sólida para futuras implementações em ambiente de produção.

A arquitetura implementada comprova a eficácia dos serviços gerenciados da AWS para simplificar a operação de aplicações web complexas, mantendo alta disponibilidade e performance otimizada.