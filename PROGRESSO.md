# Progresso: Traefik na VPS

Última atualização: 2026-09-24

## Contexto

- Tudo roda **na VPS** (`ubuntu@my-first-vps-with-docker.duckdns.org`). No PC local só editamos os arquivos e fazemos o deploy com `make`.
- O Traefik já está no ar na VPS e serve o painel em `https://traefik.my-first-vps-with-docker.duckdns.org`.
- O DNS vem do DuckDNS. Qualquer subdomínio (`*.my-first-vps-with-docker.duckdns.org`) aponta para o mesmo IP.
- Repositório git: o commit `81bf7a2 v1 config traefik` é a versão original. Para voltar a ela: `git checkout .`

## O que aprendemos

- **VPS**: um computador alugado, ligado 24h e com IP público.
- **DNS**: traduz nome em IP (é a "agenda de contatos" da internet).
- **Traefik**: o "porteiro". Recebe tudo nas portas 80/443 e encaminha para o container certo.
- **HTTPS / Let's Encrypt**: o cadeado criptografa os dados e prova a identidade do site. O Traefik pede e renova o certificado sozinho. O Let's Encrypt precisa alcançar o domínio pela internet, por isso só funciona na VPS.
- **Labels**: "bilhetes" colados em cada container dizendo qual endereço vai para ele e com qual segurança. O Traefik lê essas labels e cria as rotas sozinho.

## Melhorias feitas (já no ar na VPS desde 2026-09-24, ainda sem commit)

`docker-compose.yml`
- Redireciona todo acesso HTTP para HTTPS (direto no entrypoint `web`).
- `exposedbydefault=false`: só publica containers com a label `traefik.enable=true` (acrescentada no próprio Traefik).
- `providers.docker.network=traefik`: fala com os apps sempre pela rede `traefik`.
- Logs (`log.level=INFO`) e log de acessos ligados.
- Linha do Let's Encrypt *staging* deixada comentada, como opção para testes futuros.

`Makefile`
- `rsync` não envia `.git` nem `letsencrypt/`.
- `setup` cria `letsencrypt/acme.json` (o caminho correto) e não falha se a rede `traefik` já existir.
- `deploy` usa só `docker compose up -d`, que recria apenas o que mudou.
- Novos atalhos: `make ps` e `make logs`.

`traefik_dynamic.yml`: sem mudanças. O middleware `https-only` ficou sem uso (pode ser apagado).

## ⚠️ Atenção antes do próximo deploy

Com `exposedbydefault=false`, qualquer outro container na VPS que já use o Traefik **sem** `traefik.enable=true` sai do ar. Conferido no Teste 1: hoje só existe o `traefik`, então não há risco. Todo app novo precisa da label `traefik.enable=true`.

## Plano de testes (tudo na VPS, um de cada vez)

A pasta do projeto se chama `traefik`, tanto no PC quanto na VPS (`~/traefik`).

- [x] **Teste 1: estado atual, sem mudar nada** (passou em 2026-09-24)
  ```sh
  ssh ubuntu@my-first-vps-with-docker.duckdns.org "docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}'"
  ssh ubuntu@my-first-vps-with-docker.duckdns.org "cd traefik && ls -la . letsencrypt"
  curl -s -o /dev/null -w '%{http_code}\n' https://traefik.my-first-vps-with-docker.duckdns.org/dashboard/
  ```
  Resultado:
  - ✅ Só existe o container `traefik`. O `exposedbydefault=false` não derruba nada.
  - ✅ O `acme.json` de verdade está em `letsencrypt/acme.json` (16 KB, permissão 600). O dono é o `root`, porque o Docker criou o arquivo. Por isso **não rode `make setup` de novo** (daria erro de permissão). O `make deploy` funciona normalmente.
  - ✅ O painel responde `200` com certificado válido do Let's Encrypt (vence em 19/12/2026).
  - ℹ️ `curl -I` devolve `405`, porque o painel não aceita pedidos HEAD. Não é erro. Por isso usamos o `curl -s -o /dev/null -w ...`.
  - ⚠️ O `ssh` só funciona no terminal do seu PC. Pelo Claude Code (inclusive com `!`) dá "Host key verification failed".
- [x] **Teste 2: aplicar as melhorias**: `make deploy` e depois `make logs` (passou em 2026-09-24)
  - ✅ O deploy recriou o container `traefik` (versão 3.7.13), e os logs não mostram nenhum erro (`ERR`).
  - ✅ O Traefik achou os certificados guardados ("Testing certificate renew...").
  - ℹ️ Apareceram dois avisos (`WRN`): um sobre caracteres codificados no endereço e outro sobre `aliasHeadersStrategy`. São avisos, não erros. Só importam quando houver apps atrás do Traefik. Ver pendências.
- [x] **Teste 3: redirecionamento e HTTPS** (passou em 2026-09-24)
  - ✅ `http://` → `308 Permanent Redirect` para `https://`. O painel por `https://` → `200`.
  ```sh
  curl -I http://traefik.my-first-vps-with-docker.duckdns.org                 # esperado: 308
  curl -s -o /dev/null -w '%{http_code}\n' https://traefik.my-first-vps-with-docker.duckdns.org/dashboard/   # esperado: 200
  ```
- [x] **Teste 4: senha no painel** (passou em 2026-09-24): gerar o hash com `htpasswd -nbB admin SUASENHA`, colar no `dashboard-auth` do `traefik_dynamic.yml`, descomentar a label `middlewares=dashboard-auth@file` e rodar `make deploy`. Esperado: `401` sem senha e `200` com `curl -u admin:SUASENHA`.
  - ✅ Hash gerado na VPS com `docker run --rm -it httpd:2.4-alpine htpasswd -nB admin` (o programa pede a senha, sem ela ficar no histórico nem sofrer com `$`, `!` e `#`).
  - ✅ Arquivos editados: `dashboard-auth` ativado com o hash novo no `traefik_dynamic.yml` e label `middlewares=dashboard-auth@file` ativada no `docker-compose.yml`.
  - ✅ Deploy feito. Sem senha → `401`, com senha → `200`. No navegador aparece a janela de login.
  - Para testar com senha, use `curl -u admin URL` (sem escrever a senha): o curl pergunta a senha. Copie o comando em uma linha só, senão o endereço fica de fora (`no URL specified`).
- [x] **Teste 5: app cobaia `traefik/whoami`** em `https://whoami.my-first-vps-with-docker.duckdns.org`, antes da aplicação de verdade. (passou em 2026-09-24)
  - ✅ Criado `whoami/docker-compose.yml`: container próprio, rede `traefik` e labels (`traefik.enable=true`, endereço, HTTPS, certificado, porta 80).
  - ✅ `make deploy` + `docker compose up -d` na pasta `traefik/whoami`. O certificado novo saiu sozinho, e o `curl` devolveu `Hostname`, `IP` e os cabeçalhos `X-Forwarded-*`. Isso prova que o pedido passou pelo Traefik, por HTTPS (`X-Forwarded-Proto: https`).
  - Login do painel: usuário `admin` + a senha criada no Teste 4.
  - Depois do teste: decidir se o `whoami` fica no ar como exemplo ou se é removido (`docker compose down` na pasta `traefik/whoami`).
- [ ] Depois que tudo passar: commit `v2`. ⬅️ *paramos aqui*

## Pendências menores

- Apagar o `acme.json` solto na raiz da pasta na VPS (`~/traefik/acme.json`, 0 bytes, sem uso). Ele existe, conferido no Teste 1.
- O `README.md` (instruções de senha) não entrou no commit v1. Decidir se ele volta.
- Avisos `WRN` do Traefik 3.7 (`aliasHeadersStrategy` e caracteres codificados): ver na documentação como configurar antes de colocar a aplicação de verdade (principalmente se for PHP ou parecido).
- O `rsync` também envia o `PROGRESSO.md` para a VPS. Não atrapalha. Se quiser, acrescentar `--exclude PROGRESSO.md` no `Makefile`.
