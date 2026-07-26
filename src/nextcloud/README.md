# Nextcloud Homelab Setup

Served at `https://lenovoflakes.tail62b305.ts.net:8444/` (nginx TLS on Tailscale).

Metrics dashboard (Streamlit) is published on host port 8501:

```bash
ssh -L 8501:localhost:8501 lenovo -N
```

Then open [http://localhost:8501](http://localhost:8501).
