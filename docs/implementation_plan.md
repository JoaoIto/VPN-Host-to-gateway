# Implementação da Arquitetura VPN Host-to-Gateway com pfSense e OpenVPN

Este plano detalha o desenvolvimento e a implementação de uma Rede Privada Virtual (VPN) na topologia **Host-to-Gateway** (Client-to-Site) para a disciplina de Segurança e Auditoria de Redes. 

Decidimos utilizar o **VirtualBox** como hypervisor e o seu **Windows Host (máquina física)** como o cliente remoto VPN.

---

## Gerenciamento do Repositório e Arquivos (Sua Dúvida)

> [!NOTE]
> **Como funcionará o fluxo de arquivos entre as VMs e o seu Windows Host:**
> * O seu repositório Git e a documentação final continuam **no seu Windows físico** (nesta pasta onde estamos trabalhando). Você não precisa clonar o repositório dentro do pfSense ou das VMs.
> * Como o seu Windows Host estará conectado à rede da VM pfSense (via rede Host-Only), você poderá abrir o navegador do seu Windows físico (Chrome/Edge/Firefox) e acessar a interface administrativa (WebGUI) do pfSense digitando o IP dele (ex: `https://192.168.56.100`).
> * Toda a configuração do pfSense será feita pelo seu navegador do Windows.
> * Ao finalizar a configuração, você baixará o perfil de conexão do cliente (arquivo `.ovpn`) diretamente através do navegador do Windows, salvando-o nesta pasta de repositório.
> * Isso elimina a necessidade de configurar pastas compartilhadas ou transferir arquivos manualmente das VMs para o host!

---

## Proposed Changes

### Topologia de Rede no VirtualBox

A arquitetura final consistirá em:
1. **Windows Host (Seu PC físico - Cliente Remoto):**
   * Interface física/virtual: **VirtualBox Host-Only Ethernet Adapter** (geralmente com o IP `192.168.56.1`).
   * Software: **OpenVPN GUI** instalado no Windows.
2. **VM 1: pfSense (Firewall & Servidor VPN):**
   * **Placa 1 (WAN):** Adaptador apenas de hospedeiro (Host-Only Adapter). Receberá o IP `192.168.56.100` (será nosso IP público simulado).
   * **Placa 2 (LAN):** Rede Interna (Internal Network) nomeada `intnet`. Receberá o IP `192.168.1.1`.
3. **VM 2: Cliente Interno (Máquina Alvo na LAN):**
   * **Placa 1:** Rede Interna (Internal Network) nomeada `intnet`. Receberá IP via DHCP do pfSense na faixa `192.168.1.100/24`.

```mermaid
graph TD
    subgraph Windows Host (Máquina Física)
        Browser[Navegador Web: Gerencia pfSense]
        OpenVPNClient[OpenVPN GUI: Conecta na VPN]
        HostOnlyNIC[IP Host-Only: 192.168.56.1]
    end

    subgraph pfSense Gateway (VM 1)
        WAN[Interface WAN Host-Only<br>IP: 192.168.56.100]
        LAN[Interface LAN Rede Interna<br>IP: 192.168.1.1]
        OpenVPNServer[Servidor OpenVPN<br>Rede do Túnel: 10.0.8.0/24]
    end

    subgraph Rede Interna Corporativa (Isolada)
        LAN_VM[Máquina Interna VM 2<br>IP: 192.168.1.x DHCP]
    end

    Browser -.->|Acessa WebGUI via HTTPS| WAN
    OpenVPNClient -->|Túnel OpenVPN UDP 1194| WAN
    WAN --> OpenVPNServer
    OpenVPNServer -->|Encaminha tráfego| LAN
    LAN --> LAN_VM
```

---

### Roteiro de Configuração Passo a Passo

#### Passo 1: Preparação no VirtualBox (Configurações das Placas)
1. No VirtualBox, vá em **Ferramentas > Rede > Redes de Hospedeiro (Host-only Networks)**. Certifique-se de que existe uma placa (geralmente `VirtualBox Host-Only Ethernet Adapter`) com o IP `192.168.56.1` e que o servidor DHCP dela esteja **desabilitado** (para não conflitar com o pfSense).
2. Crie a **VM 1 (pfSense)**:
   * Tipo: BSD, Versão: FreeBSD (64-bit).
   * Memória: 1024 MB RAM, Disco: 8 GB.
   * **Rede > Adaptador 1:** Habilitar. Conectado a: **Adaptador apenas de hospedeiro (Host-Only)**. Nome: `VirtualBox Host-Only Ethernet Adapter`.
   * **Rede > Adaptador 2:** Habilitar. Conectado a: **Rede Interna (Internal Network)**. Nome: `intnet`.
3. Crie a **VM 2 (Cliente Interno - Alvo)**:
   * Escolha uma distribuição Linux leve (como Lubuntu, Alpine ou Ubuntu Linux).
   * **Rede > Adaptador 1:** Habilitar. Conectado a: **Rede Interna (Internal Network)**. Nome: `intnet`.

#### Passo 2: Instalação e Configuração de IP do pfSense
1. Inicie a VM do pfSense com a ISO anexada. Prossiga com a instalação padrão (ZFS, tudo padrão). Ao final, reinicie a VM e remova a ISO.
2. No menu de console do pfSense (tela preta com opções de 1 a 16):
   * Quando perguntar sobre VLANs, responda `n`.
   * Para WAN interface, digite `em0` (ou a correspondente ao adaptador Host-Only).
   * Para LAN interface, digite `em1` (ou a correspondente à Rede Interna).
3. **Atribuir IP na WAN (Opção 2):**
   * Selecione a interface WAN (opção 1).
   * Configure o IP estático como `192.168.56.100`.
   * Máscara: `24` (que equivale a `255.255.255.0`).
   * Gateway: Deixe em branco (pressione Enter).
   * IPv6: Desative (pressione Enter).
4. **Atribuir IP na LAN (Opção 2):**
   * Selecione a interface LAN (opção 2).
   * Configure o IP como `192.168.1.1`.
   * Máscara: `24`.
   * Habilitar Servidor DHCP na LAN: Digite `y`.
   * Range inicial: `192.168.1.100`.
   * Range final: `192.168.1.200`.
   * Reverter HTTP para HTTPS na WebGUI: Digite `y`.
5. **Liberar a WebGUI temporariamente na interface WAN:**
   * Por padrão, o pfSense bloqueia acessos administrativos vindos da WAN. Para liberar temporariamente o acesso a partir do seu Windows Host, selecione a **Opção 8 (Shell)** no console do pfSense e digite:
     ```bash
     pfctl -d
     ```
     *(Isso desativa o firewall temporariamente para que você consiga acessar `https://192.168.56.100` a partir do navegador do seu Windows físico e configurar as regras permanentes).*

#### Passo 3: Configuração do Servidor VPN via Navegador (No Windows)
1. No seu Windows Host, abra o navegador e acesse `https://192.168.56.100`. Aceite o aviso de certificado autossinado. Login: `admin` / Senha: `pfsense`.
2. Siga o assistente inicial (mude a senha do admin se preferir).
3. Vá em **VPN > OpenVPN > Wizards**:
   * **Type:** `Local User Access`. Avance.
   * **Certificate Authority (CA):**
     * Descriptive Name: `VPN_CA`.
     * Preencha os campos de localização e avance para criar a autoridade certificadora.
   * **Server Certificate:**
     * Descriptive Name: `pfSense-VPN-Server`. Avance para criar.
   * **Server Setup:**
     * Interface: `WAN`.
     * Protocolo: `UDP on IPv4 only`. Porta: `1194`.
     * Criptografia: Padrão (AES-256-GCM).
     * **Tunnel Network:** `10.0.8.0/24`.
     * **Local Network:** `192.168.1.0/24` (Isso diz ao OpenVPN para rotear o tráfego da LAN corporativa pelo túnel).
     * Avance.
   * **Firewall Rules:**
     * Marque **ambas** as opções (*Firewall Rule* e *OpenVPN rule*). Isso criará as regras que liberam o tráfego UDP na porta 1194 e permitem pacotes dentro da VPN.
     * Conclua o Wizard.
4. Vá em **System > Advanced > Admin Access**:
   * Role até o final e marque a opção para desabilitar o bloqueio de redes privadas na interface WAN (desmarque `Block private networks and loopback addresses` em **Interfaces > WAN**), pois a nossa WAN é a rede Host-Only (`192.168.56.x`), que é classificada como rede privada (RFC1918). Salve e aplique.
5. Digite `pfctl -e` no console (Shell - Opção 8) do pfSense para reativar o firewall com as novas regras configuradas permanentemente.

#### Passo 4: Criação do Usuário e Exportação
1. Vá em **System > User Manager**:
   * Adicione o usuário `aluno_vpn`. Defina uma senha.
   * Marque a opção `Click to create a user certificate`.
   * Nome descritivo: `certificado_aluno`. Autoridade Certificadora: `VPN_CA`. Salve.
2. Vá em **System > Package Manager > Available Packages**:
   * Instale o pacote `openvpn-client-export`.
3. Vá em **VPN > OpenVPN > Client Export**:
   * Role até o final. Você verá o usuário `aluno_vpn`.
   * Na coluna do instalador para Windows, selecione a opção **Inline Configuration** (baixa o arquivo `.ovpn` direto) ou o instalador completo. Recomendamos baixar o `.ovpn` (Inline Configuration) para usar com o cliente OpenVPN já instalado no seu Windows Host.

#### Passo 5: Conexão no Windows Host (Cliente)
1. Instale o **OpenVPN GUI** no seu Windows (baixe do site oficial do OpenVPN se já não tiver).
2. Cole o arquivo `.ovpn` baixado no diretório de configurações do OpenVPN (geralmente `C:\Users\<SeuUsuario>\OpenVPN\config`).
3. Inicie o OpenVPN GUI como Administrador no Windows (clique com o botão direito no ícone da bandeja, selecione "Conectar", insira as credenciais do usuário `aluno_vpn` e a senha).

---

## Verification Plan

Você demonstrará os seguintes passos para validar que a VPN está funcionando:

1. **Sem VPN (Isolamento):**
   * Abra o PowerShell no seu Windows Host e tente pingar a VM interna:
     ```powershell
     ping 192.168.1.100
     ```
     *Resultado Esperado:* **Esgotado tempo limite da solicitação** (pois o Windows host não tem rota para a rede `192.168.1.0/24` e o pfSense bloqueia acessos diretos).

2. **Ativação da VPN:**
   * Conecte a VPN usando o OpenVPN GUI na bandeja do Windows. O ícone deve ficar verde.
   * Verifique o IP atribuído no PowerShell:
     ```powershell
     ipconfig
     ```
     *Resultado Esperado:* Uma nova interface virtual (geralmente chamada de Ethernet virtual TAP/TUN) exibirá o IP `10.0.8.2`.

3. **Com VPN (Conectividade Segura):**
   * Refaça o ping para a VM interna:
     ```powershell
     ping 192.168.1.100
     ```
     *Resultado Esperado:* **Resposta de 192.168.1.100** (sucesso!).
   * Rastreie a rota para comprovar o tunelamento:
     ```powershell
     tracert 192.168.1.100
     ```
     *Resultado Esperado:* O primeiro salto será o gateway da VPN `10.0.8.1`.

4. **Auditoria e Logs:**
   * Abra a WebGUI do pfSense no navegador do seu Windows: `https://192.168.56.100`.
   * Vá em **Status > OpenVPN** para mostrar à banca o usuário `aluno_vpn` ativo, exibindo o IP real do Windows Host (`192.168.56.1`) e o IP virtual do túnel (`10.0.8.2`), além das estatísticas de criptografia e tráfego.
