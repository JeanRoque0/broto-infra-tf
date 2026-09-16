# Estimativa mensal — Broto em São Paulo

Consulta em **16/09/2026**, catálogo oficial AWS Price List (API `pricing get-products` em us-east-1, produtos filtrados para **sa-east-1**). Moeda USD; **730 horas/mês**, On-Demand, Linux, 1 t3.small, 1 PostgreSQL db.t4g.micro Single-AZ. Sem descontos, impostos, câmbio ou créditos promocionais. Esta é uma projeção, não uma fatura ou orçamento fechado.

| Componente | Hipótese e tarifa consultada | USD/mês |
|---|---|---:|
| EC2 t3.small | 730 × 0,0336/h | 24,53 |
| EBS gp3 da EC2 | 30 GB × 0,152/GB-mês; IOPS/throughput incluídos | 4,56 |
| RDS PostgreSQL db.t4g.micro | 730 × 0,034/h | 24,82 |
| RDS gp3 | 20 GB × 0,219/GB-mês | 4,38 |
| Application Load Balancer | 730 × 0,034/h | 24,82 |
| ALB capacidade | média de 0,1 LCU × 730 × 0,011/LCU-h | 0,80 |
| IPv4 públicos | mínimo 2 ALB + 1 EC2, 3 × 730 × 0,005/h | 10,95 |
| S3 Standard fotos | 5 GB × 0,0405/GB-mês | 0,20 |
| Outros serviços pequenos | estimativa de Secrets Manager, logs/alarmes, DNS, ECR, estado/requests | 3–5 |
| **Subtotal sem saída CDN** | configuração econômica sem NAT | **98,06–100,06** |
| CloudFront saída | cenário 100 GB no Brasil × 0,110/GB | 11,00 |
| CloudFront HTTPS | cenário 100 mil requests × 0,022/10 mil | 0,22 |
| **Total do cenário** | sem franquias/descontos CloudFront | **109,28–111,28** |

Planeje aproximadamente **US$ 110–120/mês** para esse cenário pequeno, antes dos itens variáveis abaixo. A folga é indicativa, não limita a cobrança.

“Outros” é uma reserva, não uma tarifa única: três secrets custam US$1,20/mês (US$0,40 cada), ingestão de 1 GB de logs em São Paulo custa US$0,90; somam-se retenção, alarmes, Route53, armazenamento ECR/estado e operações S3/Secrets. Se o volume passar dessas hipóteses, recalcule. O TTL e os acessos afetam requests ao S3; uma request na CDN não implica necessariamente GET no S3.

## Opção com EC2 privada e IP de saída fixo

`private_compute=true` adiciona **1 NAT Gateway**: 730 × US$0,093 = **US$67,89/mês**, mais **US$0,093/GB processado**. O Elastic IP do NAT substitui, neste cenário de um host, o IPv4 público da EC2; a linha base continua com três IPv4 (dois ALB, um NAT).

Com 10 GB processados no NAT, acrescente US$68,82: **US$178,10–180,10/mês** no cenário acima; reserve aproximadamente **US$180–190**, fora tráfego entre AZs/excedentes. S3 usa gateway endpoint e não passa pelo NAT. Downloads de imagens ECR, Secrets Manager, logs, Anthropic e SMTP podem passar. O NAT é de uma AZ; hosts em outra AZ podem gerar transferência inter-AZ.

Essa opção resolve saída estável para allowlist SMTP. Sem NAT, substituições/autoscaling mudam IPs dos hosts; não assuma funcionamento de uma allowlist fixa do Brevo nesse modo.

## Variações e cobranças não incluídas

- CloudFront está em **pay-as-you-go**, não plano flat-rate. Verifique franquias/descontos aplicáveis à conta: eles podem reduzir a linha CDN; o cálculo conservador acima não os desconta. A tarifa usada é South America, primeiro nível de volume, e muda conforme a localização de quem acessa.
- A LCU é o maior consumo entre conexões, conexões ativas, bytes e avaliações de regras, não uma reserva de 0,1. Se a média for 1 LCU, a linha passa de US$0,80 para **US$8,03** (+US$7,23).
- EC2 extras durante migration, rolling deploy, recuperação e autoscaling: cada host custa aproximadamente **US$0,04485/h** somando EC2, EBS30GB proporcional e IPv4 no modo público. No privado, retire US$0,005/h de IPv4 por host e considere NAT/tráfego. Capacidade inicial do ECS também pode subir temporariamente acima de um host.
- Saída de dados da **API/ALB**, tráfego entre AZs, versões anteriores de fotos, downloads não cacheados, requests S3, snapshots/backups excedentes, logs PostgreSQL e crescimento ECR/banco. Storage RDS pode crescer até 50 GB: **US$10,95/mês** só de disco nesse limite, em vez de US$4,38.
- Créditos CPU excedentes do RDS burstable, se a carga superar a capacidade baseline; EC2 usa Standard e pode ser limitada por falta de créditos. Não confundir vCPU alocada com desempenho sustentado.
- Registro anual do domínio, cobrança da Anthropic, plano Brevo, GitHub Actions, impostos e conversão para reais. IA pode superar o custo de infraestrutura; depende de tokens/modelo/usuários.
- Multi-AZ, segunda task permanente, WAF, RDS Proxy e NAT redundante não fazem parte da estimativa. O padrão com uma instância e um banco **não é alta disponibilidade**.

## Reproduzir e fontes

Exemplo (somente consulta):

```sh
aws pricing get-products --region us-east-1 --service-code AmazonEC2 \
  --filters Type=TERM_MATCH,Field=regionCode,Value=sa-east-1 \
            Type=TERM_MATCH,Field=instanceType,Value=t3.small \
            Type=TERM_MATCH,Field=operatingSystem,Value=Linux \
            Type=TERM_MATCH,Field=tenancy,Value=Shared \
            Type=TERM_MATCH,Field=preInstalledSw,Value=NA \
            Type=TERM_MATCH,Field=capacitystatus,Value=Used
```

- [Catálogo oficial ELB São Paulo](https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AWSELB/current/sa-east-1/index.json): ALB US$0,034/h, LCU US$0,011/h.
- [Catálogo oficial CloudFront](https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AmazonCloudFront/current/index.json): South America US$0,110/GB e HTTPS US$0,022/10 mil requests no primeiro nível.
- [AWS Price List API](https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/price-changes.html), serviços consultados: AmazonEC2, AmazonRDS, AmazonS3, AmazonCloudWatch e AWSSecretsManager.
- [IPv4 e NAT](https://aws.amazon.com/vpc/pricing/), [RDS PostgreSQL](https://aws.amazon.com/rds/postgresql/pricing/), [CloudFront e planos/franquias](https://aws.amazon.com/cloudfront/pricing/).

Reconsulte tarifas e estime tráfego real antes do apply. Nenhum recurso cobrado foi criado para obter estes valores.
