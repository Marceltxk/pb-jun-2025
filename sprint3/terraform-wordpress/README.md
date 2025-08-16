# WordPress Alta Disponibilidade - Terraform

Este projeto provisiona uma arquitetura completa do WordPress em alta disponibilidade na AWS usando Terraform.

## Arquivos do Projeto

```
terraform-wordpress/
├── main.tf                    # Configuração principal do Terraform
├── user-data.sh              # Script de inicialização das instâncias EC2
├── terraform.tfvars.example  # Exemplo de variáveis
├── terraform.tfvars          # Suas variáveis (criar este arquivo)
└── README.md                 # Este arquivo
```

## Pré-requisitos

### 1. Instalar Terraform
```bash
# Ubuntu/Debian
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com jammy main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform

# macOS
brew install terraform

# Windows
choco install terraform
```

### 2. Configurar AWS CLI
```bash
# Instalar AWS CLI
curl "https://awsc