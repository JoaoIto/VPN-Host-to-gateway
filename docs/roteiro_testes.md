# Roteiro de Testes, Auditoria e Verificação Completa da VPN

Este documento apresenta o guia consolidado com todas as etapas práticas e comandos necessários para auditar e provar o funcionamento da infraestrutura **VPN Host-to-Gateway** perante a banca examinadora.

---

## 🗺️ Índice de Testes
1. [Testes Base no Cliente (Sem VPN - Isolamento)](#1-testes-base-no-cliente-sem-vpn---isolamento)
2. [Testes Ativos no Cliente (Com VPN Conectada)](#2-testes-ativos-no-cliente-com-vpn-conectada)
3. [Auditoria e Testes do Firewall (pfSense Shell & CLI)](#3-auditoria-e-testes-do-firewall-pfsense-shell--cli)
4. [Auditoria do Serviço OpenVPN no Servidor (pfSense)](#4-auditoria-do-serviço-openvpn-no-servidor-pfsense)
5. [Auditoria Visual das Configurações (WebGUI do pfSense)](#5-auditoria-visual-das-configurações-webgui-do-pfsense)

---

## 1. Testes Base no Cliente (Sem VPN - Isolamento)

Execute estes comandos no **Windows físico (Host)** antes de iniciar a conexão do OpenVPN para comprovar que a rede LAN protegida do pfSense (`192.168.1.0/24`) está isolada.

### Teste 1.1: Ping de Teste
No Prompt de Comando (CMD) do Windows:
```cmd
ping 192.168.1.1
```
* **Resultado Esperado:** Mensagem de **"Esgotado tempo limite da solicitação"** ou **"Host de destino inacessível"** (0 respostas de eco).

### Teste 1.2: Rota de Rede Inexistente
No PowerShell do Windows:
```powershell
Get-NetRoute -DestinationPrefix "192.168.1.0/*"
```
* **Resultado Esperado:** Mensagem de erro informando que **nenhum elemento correspondente foi encontrado**, provando que o Windows físico não tem rotas para alcançar a rede interna.

---

## 2. Testes Ativos no Cliente (Com VPN Conectada)

Ligue a VPN usando o **OpenVPN GUI** na barra de tarefas (Login: `user_vpn` / Senha: `vpn`) e aguarde o ícone do cadeado ficar **verde**. Execute os seguintes testes no seu Windows Host:

### Teste 2.1: Verificar Interface Virtual do Túnel
No Prompt de Comando (CMD):
```cmd
ipconfig
```
* **Resultado Esperado:** Uma nova interface de túnel OpenVPN listada com endereço IPv4 da faixa **`10.0.8.x`** (ex: `10.0.8.2`).

### Teste 2.2: Validação de Conexão Criptografada (Ping de Sucesso)
No CMD:
```cmd
ping 192.168.1.1
```
* **Resultado Esperado:** O ping deve responder com **0% de perda** de pacotes e tempo de latência baixíssimo (tempo `< 1ms`), provando que a rede interna agora é alcançável.

### Teste 2.3: Rastreamento do Túnel Seguro (Traceroute)
No CMD:
```cmd
tracert 192.168.1.1
```
* **Resultado Esperado:** O primeiro salto do pacote deve ser o endereço do servidor OpenVPN dentro do túnel: **`10.0.8.1`**, provando que a rede não utilizou o gateway físico comum da sua rede local.

### Teste 2.4: Verificação da Rota Adicionada Dinamicamente
No PowerShell:
```powershell
Get-NetRoute -DestinationPrefix "192.168.1.0/*"
```
* **Resultado Esperado:** A exibição de uma tabela mostrando que o tráfego destinado a `192.168.1.0/24` tem como próximo salto (`NextHop`) o IP virtual do túnel `10.0.8.1`.

---

## 3. Auditoria e Testes do Firewall (pfSense Shell & CLI)

O professor pode pedir para verificar o comportamento do firewall na máquina virtual do pfSense. Acesse a máquina virtual no VirtualBox e entre na **opção 8 (Shell)**.

### Teste 3.1: Listar as Regras de Firewall Ativas (Packet Filter - `pf`)
O pfSense gera as regras do firewall dinamicamente a partir do seu motor. Para visualizar as regras ativas na memória:
```bash
pfctl -sr
```
* **Como Filtrar:** Para ver apenas as regras que envolvem a liberação do OpenVPN (porta 1194 ou interface virtual `ovpns1`), rode:
  ```bash
  pfctl -sr | grep -E "1194|ovpn"
  ```
* **Resultado Esperado:** Linhas de liberação (`pass`) contendo a porta `1194` (tráfego de entrada UDP) e referências a pacotes passando na interface `ovpns1`.

### Teste 3.2: Exibir a Tabela de Estados Ativos (Connections)
Para mostrar todas as sessões e conexões ativas passando pelo firewall em tempo real:
```bash
pfctl -ss | grep "10.0.8"
```
* **Resultado Esperado:** Exibição do mapeamento de estado, mostrando os pacotes indo da sua interface virtual `10.0.8.2` em direção aos recursos da LAN (`192.168.1.x`).

### Teste 3.3: Exibir Estatísticas e Integridade do Firewall
Para mostrar estatísticas de tráfego geral e confirmar se o motor de firewall está ativo:
```bash
pfctl -si
```
* **Resultado Esperado:** O console deve indicar `Status: Enabled` no início da saída, confirmando que a proteção está de fato ligada.

---

## 4. Auditoria do Serviço OpenVPN no Servidor (pfSense)

Acesse o **Shell (opção 8)** no console da VM do pfSense para inspecionar os arquivos de configuração reais e o estado do daemon do OpenVPN.

### Teste 4.1: Ler o Arquivo de Configuração do OpenVPN
Para mostrar como o servidor OpenVPN foi provisionado e verificar os parâmetros de criptografia:
```bash
cat /var/etc/openvpn/server1/config.ovpn
```
* **Elementos a Destacar:**
  * `dev ovpns1` (tipo de interface virtual tunelada);
  * `proto udp4` (protocolo UDP);
  * `port 1194` (porta padrão);
  * `cipher AES-256-GCM` (algoritmo moderno de criptografia).

### Teste 4.2: Listar os Certificados e Chaves do Servidor
Para provar que os certificados de segurança da sessão estão estruturados na pasta do daemon:
```bash
ls -la /var/etc/openvpn/server1/
```
* **Resultado Esperado:** Presença do certificado CA (`server1.ca`), certificado do servidor (`server1.cert`), chave privada (`server1.key`) e chave de autenticação TLS (`server1.tls-auth`).

### Teste 4.3: Verificar se o Daemon do OpenVPN está em Execução
Para atestar que o serviço está no ar e escutando na porta correta:
```bash
sockstat -4 -l -p 1194
```
* **Resultado Esperado:** Uma linha indicando o daemon `openvpn` escutando (`LISTEN`) no IP WAN ou em todas as interfaces (`*:1194`) via protocolo `udp4`.

---

## 5. Auditoria Visual das Configurações (WebGUI do pfSense)

Caso o professor prefira auditar as configurações diretamente pela interface web (`https://192.168.56.101`):

1. **Sessões Ativas da VPN:**
   * **Caminho:** `Status > OpenVPN`
   * **O que mostrar:** A tabela listando o usuário `user_vpn` conectado, seu IP real de origem (`192.168.56.1`), seu IP no túnel (`10.0.8.2`) e os bytes trafegados.
2. **Regras de Liberação de Firewall:**
   * **Caminho:** `Firewall > Rules > WAN` (libera a porta 1194 de entrada).
   * **Caminho:** `Firewall > Rules > OpenVPN` (permite que os pacotes do túnel alcancem a LAN).
3. **Gerência da Autoridade Certificadora (PKI):**
   * **Caminho:** `System > Certificates`
   * **Abas:** `Authorities` (mostra a CA `VPN-CA`) e `Certificates` (mostra o `VPN-Server-Cert` do servidor e o certificado pessoal do usuário `user_vpn_cert`).
