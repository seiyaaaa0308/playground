# Netfilter 学習用 Docker ネットワーク

Docker Compose で、クライアント側とサーバ側を分離したNAT/firewalld実験環境を起動します。クライアントからサーバ側への経路はNATルータだけを通り、Nginxリバースプロキシの背後に2台のNginx Webサーバを配置します。各コンテナに iproute2、net-tools、iptables、nftables、firewalld、tcpdump、curl、ping、DNSツールを含めています。

## ネットワーク構成

```text
client (172.16.0.10)
    |
    | client_net: 172.16.0.0/24 (internal)
    |
nat / firewalld
  client: 172.16.0.1
  server: 172.24.0.1
    |
    | server_net: 172.24.0.0/24 (internal)
    +-- reverse-proxy: 172.24.0.10
    |      +-- web1: 172.24.0.11
    |      +-- web2: 172.24.0.12
```

両ネットワークをDockerの `internal` ネットワークにして外部への直接経路を閉じています。クライアントのデフォルトゲートウェイは `172.16.0.1` です。ルータはfirewalldで `client -> server` の転送を許可してmasqueradeし、`8080 -> 172.24.0.10:80`、`8443 -> 172.24.0.10:443` をDNATします。サーバからの応答はSNATされたルータのアドレスへ返るため、クライアントとサーバ間の直接経路は不要です。

## 起動

必要条件: Docker Engine と Docker Compose v2。ホスト側で `172.16.0.0/24` および `172.24.0.0/24` が未使用であること、公開ポート `8080` と `8443` が空いていることを確認してください。

```sh
cd docker
docker compose up -d --build
docker compose ps
```

ルータには `NET_ADMIN` と `NET_RAW` capability、およびIPv4 forwardingを付与しています。ホストカーネルとDockerの設定によってはfirewalld/nftables操作が制限されることがあります。

## 検証

クライアントからネットワークとデフォルト経路を確認します。

```sh
docker compose exec client ip -br address
docker compose exec client ip route
docker compose exec client ping -c 2 172.16.0.1
```

クライアントから直接サーバ側IPへアクセスするのではなく、NATルータの転送ポートを使います。

```sh
docker compose exec client curl --resolve web.lab.test:8080:172.16.0.1 http://web.lab.test:8080/
docker compose exec client curl -k --resolve web.lab.test:8443:172.16.0.1 https://web.lab.test:8443/
```

繰り返し実行すると、応答本文が `web1` と `web2` の間で切り替わります。自己署名証明書のため、HTTPSの検証では `-k` を付けています。ホストからは `http://localhost:8080/` および `https://localhost:8443/` で確認できます。

NAT/firewalldの状態とパケットを確認します。

```sh
docker compose exec router firewall-cmd --get-active-zones
docker compose exec router firewall-cmd --policy=client-to-server --list-all
docker compose exec router nft list ruleset
docker compose exec router iptables -t nat -L -n -v
docker compose exec router tcpdump -ni any 'host 172.16.0.10 or host 172.24.0.10'
```

クライアントとWebサーバの経路がルータを通ることは、クライアントの `traceroute` 相当の確認や、上記tcpdumpで観察できます。サーバ側IPへの直接アクセスを試す場合は、クライアントにその宛先への経路がなく、またサーバ側ネットワークにも接続していないことを確認してください。

## firewalld実験

ルータ上でDNATルールを一時削除してHTTP疎通を確認し、元に戻します。

```sh
docker compose exec router firewall-cmd --zone=client --remove-forward-port=port=8080:proto=tcp:toaddr=172.24.0.10:toport=80
docker compose exec client curl --connect-timeout 3 --resolve web.lab.test:8080:172.16.0.1 http://web.lab.test:8080/
docker compose exec router firewall-cmd --zone=client --add-forward-port=port=8080:proto=tcp:toaddr=172.24.0.10:toport=80
```

永続設定ではなく、コンテナを再作成すると起動時設定へ戻ります。nftablesルールはfirewalldが管理するため、実験中に `nft flush ruleset` を実行するとfirewalldの通信も壊れます。まず `nft list ruleset` でルールを観察し、変更は `firewall-cmd` から行ってください。

## 公開ドメインでCertbotを使う場合

既定構成では自己署名証明書を使います。Let's Encryptを使うには、公開DNSがこのホストを指し、外部からTCP 80/443へ到達できる必要があります。`docker` ディレクトリで `.env.example` を `.env` にコピーし、実ドメインとメールアドレスに書き換えます。80/443がホスト上で使用可能である必要があります。

```sh
cp .env.example .env
${EDITOR:-vi} .env
```

初期値の `example.com` と `admin@example.com` はプレースホルダーで、Certbotはそのままでは実行できません。`.env` を実際に管理しているドメイン名とメールアドレスに変更してください。`.env` はGit管理対象外です。

CertbotコンテナはACME APIへ接続するためだけに外向きネットワークを使います。クライアント用・サーバ用ネットワークは引き続き内部専用です。

80/443をホスト上で空けてから、起動および証明書発行を行います。

```sh
docker compose up -d --build
docker compose --profile certbot run --rm certbot
docker compose exec proxy nginx -s reload
```

CertbotはHTTP-01 webroot方式です。証明書更新時もCertbotを再実行し、その後 `nginx -s reload` してください。実際の公開にあたっては、証明書更新を定期実行する運用とホストのファイアウォール設定も別途必要です。

## 停止・初期化

```sh
docker compose down
```

証明書やACME challengeを含むボリュームも削除して初期状態に戻す場合のみ、次を実行します。

```sh
docker compose down -v
```