```mermaid
graph TD
    A[WireGuard Server] --> B[Client 1 (Mobile)]
    A[WireGuard Server] --> C[Client 2 (Desktop)]
    A[WireGuard Server] --> D[Client 3 (Phone)]
    A[WireGuard Server] --> E[Client 4 (IoT Device)]

    B -->|Routes DNS| F[DNS Resolver]
    C -->|Routes DNS| F[DNS Resolver]
    D -->|Routes DNS| F[DNS Resolver]
    E -->|Routes DNS| F[DNS Resolver]

    F[DNS Resolver] --> G[WireGuard Server]  %% Server DNS lookup

    %% Traffic through VPN
    B --> H[WireGuard VPN Tunnel] --> A
    C --> H[WireGuard VPN Tunnel] --> A
    D --> H[WireGuard VPN Tunnel] --> A
    E --> H[WireGuard VPN Tunnel] --> A
    
    %% WireGuard Server forwards traffic to the Internet
    A --> I[Router] --> J[Internet]

    %% DNS Query Flow
    F --> K[DNS Server (External)]
    
    style A fill:#f9f,stroke:#333,stroke-width:4px
    style B fill:#bbf,stroke:#333,stroke-width:2px
    style C fill:#bbf,stroke:#333,stroke-width:2px
    style D fill:#bbf,stroke:#333,stroke-width:2px
    style E fill:#bbf,stroke:#333,stroke-width:2px
    style F fill:#bbf,stroke:#333,stroke-width:2px
    style G fill:#ff9,stroke:#333,stroke-width:2px
    style H fill:#cfc,stroke:#333,stroke-width:2px
    style I fill:#e3e3e3,stroke:#333,stroke-width:2px
    style J fill:#e3e3e3,stroke:#333,stroke-width:2px
    style K fill:#f7f7f7,stroke:#333,stroke-width:2px
```
