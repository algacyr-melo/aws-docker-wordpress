# Projeto AWS-Docker-WordPress

Este projeto tem como objetivo realizar o deploy de uma aplicação WordPress em container Docker, de forma segura e com alta disponibilidade na AWS, utilizando boas práticas de infraestrutura.

## Etapa 1: Criação da VPC

### Objetivo

Criar uma VPC com duas subnets públicas e duas privadas, distribuídas entre duas zonas de disponibilidade.

### Passo a passo

1. Acesse o serviço **VPC** no console da AWS.

2. Clique em **Create VPC**.

3. Preencha os campos com os seguintes valores:

   | Campo               | Valor        |
   | ------------------- | ------------ |
   | Name tag            | aws-docker   |
   | Resources to create | VPC and more |
   | Availability Zones  | 2            |
   | Public Subnets      | 2            |
   | Private Subnets     | 2            |
   | NAT gateways        | 1 por AZ     |
   | VPC endpoints       | Nenhum       |

4. Clique em **Create VPC** para confirmar.

---

## Etapa 2: Criando um Launch Template para instância EC2

### Objetivo

Definir um modelo padronizado de instância EC2 que será utilizado por um Auto Scaling Group com Load Balancer.

### Passo a passo

1. Acesse o serviço **EC2** no console da AWS.

2. No menu lateral, clique em **Launch Templates** e depois em **Create launch template**.

3. Preencha os campos principais:

   | Campo                | Valor                                                        |
   | -------------------- | ------------------------------------------------------------ |
   | Launch template name | wordpress-template                                           |
   | AMI                  | AL2023                                                       |
   | Instance type        | t2.micro (ou equivalente)                                    |
   | Key pair             | Selecione um existente                                       |
   | Network settings     | Nenhum (configurado via Auto Scaling)                        |
   | Security Group       | Crie ou selecione um que permita acesso HTTP                 |
   | User data            | Script de preparação do ambiente WordPress com Docker na EC2 |

4. Clique em **Create launch template**.

### Observações

* Esse template será usado para criar múltiplas instâncias EC2 dentro de um Auto Scaling Group.
* A configuração de subnets e balanceamento será feita posteriormente ao criar o Auto Scaling Group.

---

## Etapa 3: Criação da Instância RDS

### Objetivo

Criar um banco de dados relacional gerenciado (Amazon RDS) para uso pela aplicação.

### Passo a passo

1. Acesse o serviço **Amazon RDS** no console da AWS.

2. Clique em **Create database**.

3. Selecione a opção **Standard Create**.

4. Configure os seguintes parâmetros principais:

   | Campo                  | Valor                         |
   | ---------------------- | ----------------------------- |
   | Engine                 | MySQL                         |
   | Version                | (versão estável mais recente) |
   | DB instance identifier | wordpress-db                  |
   | Master username        | admin                         |
   | Master password        | auto-generate                 |
   | DB instance size       | db.t3.micro (para testes)     |
   | Storage                | 20 GB (General Purpose SSD)   |

5. Em **Connectivity**, configure:

   | Campo                       | Valor                                        |
   | --------------------------- | -------------------------------------------- |
   | Virtual Private Cloud (VPC) | Selecione a VPC criada anteriormente         |
   | Subnet group                | Subnets privadas                             |
   | Public access               | No                                           |
   | VPC security group          | Crie ou selecione um com acesso da aplicação |

6. Em **Additional configuration**, defina o nome do banco de dados inicial como `wordpress`.

7. Clique em **Create database** para iniciar a criação.

### Observações

* A instância **não deve ser pública**, para garantir isolamento da internet.
* O Security Group da instância RDS pode ser configurado ou alterado após a criação. Quando a instância EC2 da aplicação estiver criada, edite a instância RDS e adicione o Security Group da EC2 para permitir o acesso ao banco de dados.
* Libere acesso à instância apenas para o serviço que irá utilizá-la, via **Security Group**.

## Etapa 4: Auto Scaling Group com Load Balancer

### Objetivo

Garantir alta disponibilidade e escalabilidade automática da aplicação, utilizando um Load Balancer para distribuir o tráfego e um Auto Scaling Group para gerenciar as instâncias EC2.

### Passo a passo

1. Acesse o serviço **EC2** no console da AWS.

2. No menu lateral, clique em **Auto Scaling Groups** e selecione **Create Auto Scaling group**.

3. Configure os seguintes parâmetros iniciais:

   | Campo                   | Valor                            |
   | ----------------------- | -------------------------------- |
   | Auto Scaling group name | wordpress-asg                    |
   | Launch template         | Selecione o criado anteriormente |

4. Clique em **Next** para definir a **rede e subnets**:

   * Selecione a VPC criada anteriormente.
   * Marque as duas subnets privadas (uma em cada AZ).

5. Em **Load Balancing**, selecione:

   * Clique em **Attach to a new load balancer** e configure:

     * Application Load Balancer (ALB)
     * Nome: `wordpress-alb`
     * Scheme: Internet-facing
     * Listeners: HTTP (porta 80)
     * Target group: criar novo, do tipo instance, HTTP na porta 80

6. Em **Health checks**, use o padrão HTTP na raiz (`/`).

7. Em **Group size and scaling policies**:

   * Desired capacity: 2
   * Minimum capacity: 1
   * Maximum capacity: 2

8. Conclua as etapas seguintes e clique em **Create Auto Scaling Group**.

### Observações

* O Load Balancer distribuirá o tráfego entre as instâncias EC2 de forma equilibrada.
* O Auto Scaling ajustará o número de instâncias conforme a demanda (configurações padrão).
* O target group criado será automaticamente vinculado ao Load Balancer e às instâncias EC2.

## Etapa 5: Configuração do Amazon EFS

### Objetivo

Prover um sistema de arquivos compartilhado entre as instâncias EC2 para persistência de dados, útil especialmente em ambientes com Auto Scaling.

### Passo a passo

1. Acesse o serviço **Amazon EFS** no console da AWS.

2. Clique em **Create file system**.

3. Configure os campos iniciais:

   | Campo | Valor                                |
   | ----- | ------------------------------------ |
   | Name  | wordpress-efs                        |
   | VPC   | Selecione a VPC criada anteriormente |

4. Clique em **Customize** para ajustes finos:

   * **Mount targets**: selecione todas as subnets privadas usadas no Auto Scaling.

5. Finalize a criação clicando em **Create**.

### Integração com EC2

Para que a aplicação funcione corretamente com EFS, o script de **User Data** no Launch Template deve incluir comandos como:

```bash
sudo dnf install -y amazon-efs-utils
sudo mkdir -p /mnt/efs
sudo mount -t efs fs-<ID-do-EFS>:/ /mnt/efs
```

### Configuração do Security Group para EFS

* Crie um Security Group específico para o EFS com a seguinte regra de entrada:

  * Tipo: NFS
  * Porta: 2049
  * Origem: Security Group das instâncias EC2

* Isso garante que apenas as instâncias autorizadas tenham acesso ao sistema de arquivos.

## Security Groups Necessários

Para garantir uma comunicação segura e funcional entre os serviços da arquitetura, os seguintes Security Groups devem ser criados ou configurados:

### 1. EC2 (Instância da Aplicação)

* Permitir entrada:

  * Tipo: HTTP | Porta: 80 | Origem: 0.0.0.0/0
  * Tipo: SSH | Porta: 22 | Origem: IP pessoal (opcional, para acesso via terminal)
* Permitir saída:

  * Regra padrão: All traffic | Destino: 0.0.0.0/0

### 2. RDS (Banco de Dados)

* Permitir entrada:

  * Tipo: MySQL/Aurora | Porta: 3306 | Origem: Security Group da EC2

### 3. EFS (Sistema de Arquivos Compartilhado)

* Permitir entrada:

  * Tipo: NFS | Porta: 2049 | Origem: Security Group da EC2

> Obs: A origem baseada em outro Security Group garante que apenas instâncias da aplicação possam se conectar ao banco de dados e ao sistema de arquivos, aumentando a segurança da arquitetura.
