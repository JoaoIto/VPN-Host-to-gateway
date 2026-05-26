# Roteiro de Testes e Verificação da VPN Host-to-Gateway

Este documento apresenta o roteiro prático passo a passo e os comandos necessários para testar e validar o funcionamento da VPN Host-to-Gateway implementada no laboratório.

---

## 1. Estado Base (Sem VPN Conectada)

Antes de iniciar a VPN, execute estes testes a partir do seu Windows físico (Host) para comprovar que a rede interna (`192.168.1.0/24`) da máquina virtual está completamente inacessível.

### Teste 1.1: Teste de Ping
No Prompt de Comando (CMD) do Windows físico, tente se comunicar com o gateway da rede interna:
```cmd
ping 192.168.1.1
```
* **Resultado Esperado:** Os pacotes devem falhar (mensagem de "Esgotado tempo limite da solicitação" ou "Host de destino inacessível"). Isso prova que a rede interna do pfSense está isolada.

### Teste 1.2: Rota de Rede
Verifique se o seu computador possui alguma rota configurada para a sub-rede `192.168.1.0/24` no PowerShell:
```powershell
Get-NetRoute -DestinationPrefix "192.168.1.0/*"
```
* **Resultado Esperado:** Nenhuma rota deve ser encontrada para este prefixo no computador físico.

---

## 2. Ativação da Conexão VPN

1. Com o pfSense ligado e o firewall ativo, abra o **OpenVPN GUI** na barra de tarefas.
2. Clique com o botão direito no ícone do cadeado, selecione o perfil importado e clique em **Conectar**.
3. Insira as credenciais de teste:
   * **Usuário:** `user_vpn`
   * **Senha:** `vpn`
4. Aguarde até o ícone ficar **verde**.

---

## 3. Estado Ativo (Com VPN Conectada)

Execute os comandos a seguir para confirmar que o tráfego da rede interna está sendo encapsulado e entregue com sucesso através do túnel criptografado.

### Teste 3.1: Verificar o Adaptador e IP do Túnel
No Prompt de Comando (CMD), verifique se uma nova placa de rede virtual (TAP/Wintun) recebeu o IP atribuído pela rede do túnel (`10.0.8.0/24`):
```cmd
ipconfig
```
* **Resultado Esperado:** Localize o adaptador OpenVPN na lista. O campo **Endereço IPv4** deve exibir um endereço da faixa `10.0.8.x` (como `10.0.8.2`).

### Teste 3.2: Validação de Conectividade (A Prova de Fogo)
No CMD, tente pingar novamente o gateway da rede LAN interna:
```cmd
ping 192.168.1.1
```
* **Resultado Esperado:** O ping deve responder imediatamente (com 0% de perda de pacotes e tempo de latência baixíssimo, normalmente `< 1ms`).

### Teste 3.3: Rastreamento de Rota (Traceroute)
Para provar que os pacotes estão de fato passando por dentro do túnel virtual e não por um caminho comum, realize o rastreio da rota até o gateway da LAN:
```cmd
tracert 192.168.1.1
```
* **Resultado Esperado:** O primeiro salto da rota deve ser o IP do próprio servidor OpenVPN dentro do túnel (`10.0.8.1`), comprovando o tunelamento do tráfego.

### Teste 3.4: Tabela de Rotas Dinâmica
Verifique se a rota para a sub-rede `192.168.1.0/24` foi inserida dinamicamente no seu Windows físico após a conexão da VPN:
```powershell
Get-NetRoute -DestinationPrefix "192.168.1.0/*"
```
* **Resultado Esperado:** O PowerShell deve retornar uma rota ativa onde o gateway de saída (*NextHop*) aponta para o túnel (`10.0.8.1`).

---

## 4. Auditoria de Conexões Ativas (No pfSense WebGUI)

Para validar a gerência e auditoria de segurança da VPN:
1. Acesse o painel web do pfSense no navegador do Windows Host: `https://192.168.56.101`
2. Navegue até o menu **Status** > **OpenVPN**.
3. **Resultado Esperado:** O dashboard exibirá o usuário `user_vpn` ativo na tabela, detalhando:
   * **Real Address:** O IP de origem do seu computador físico (`192.168.56.1`).
   * **Virtual Address:** O IP recebido no túnel (`10.0.8.2`).
   * **Bytes Sent / Bytes Received:** A taxa de bytes criptografados transitando pelo túnel em tempo real.
