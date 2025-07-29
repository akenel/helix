# 🎮 Helix Minecraft Server

## 🚀 Deploy Minecraft Faster Than Booting Windows!

**The Viral Challenge:** 60 seconds from command to playable Minecraft server!

### ⚡ Quick Start

```bash
# One command, infinite possibilities
./install-service.sh --plug minecraft --install
```

**That's it!** Your Minecraft server is now running and ready for players!

### 🎯 What You Get

- ✅ **Minecraft 1.20.4** with Paper server (optimized performance)
- ✅ **Up to 20 players** concurrent
- ✅ **Gaming-optimized JVM settings** for lag-free experience  
- ✅ **Persistent world storage** - your builds are safe forever
- ✅ **LoadBalancer service** - automatic external IP
- ✅ **Professional-grade infrastructure** running on Kubernetes

### 📱 Connecting to Your Server

After deployment, get your server IP:

```bash
kubectl get svc -n minecraft minecraft-minecraft-server -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

**Share with friends:** `your-server-ip:25565`

### 🎮 Server Configuration

Your server comes pre-configured with:
- **MOTD:** "🚀 Helix Minecraft - Deployed in 60 seconds! 🎮"
- **Game Mode:** Survival 
- **Difficulty:** Normal
- **PVP:** Enabled
- **Memory:** 2GB (expandable to 4GB)
- **Max Players:** 20

### ⚙️ Customization

Want to modify settings? Edit `values.yaml`:

```yaml
minecraftServer:
  maxPlayers: 50        # More players
  difficulty: hard      # Hardcore mode
  gameMode: creative    # Creative building
  motd: "My Epic Server!"
```

Then upgrade:
```bash
./install-service.sh --plug minecraft --upgrade
```

### 🔥 Why This Is Revolutionary

**Traditional Method:**
- Rent VPS: $20-50/month
- Install OS, Java, Minecraft
- Configure networking, firewalls
- Set up backups manually
- Total setup time: 2-4 hours
- Monthly cost: $20-50
- **Total effort: PAINFUL** 😫

**Helix Method:**
- One command: 60 seconds
- Professional infrastructure
- Built-in backups (coming soon)
- Auto-scaling capabilities
- Monthly cost: $0-10 (your hardware)
- **Total effort: EFFORTLESS** 🚀

### 👨‍👩‍👧‍👦 Perfect for Families

- **Kids learn:** Real DevOps skills while gaming
- **Parents save:** No monthly VPS fees
- **Everyone wins:** Better performance than expensive VPS

### 🎬 Viral Potential

This setup is **TikTok-ready**:
- Film the 60-second deployment
- Show kids' reactions to instant server
- Compare to traditional gaming VPS setup
- **Result:** DevOps goes viral! 🎬

### 🛠️ Management Commands

```bash
# Check server status
kubectl get pods -n minecraft

# View server logs  
kubectl logs -n minecraft deployment/minecraft-minecraft-server -f

# Restart server
kubectl rollout restart deployment/minecraft-minecraft-server -n minecraft

# Scale resources
kubectl patch deployment minecraft-minecraft-server -n minecraft -p '{"spec":{"template":{"spec":{"containers":[{"name":"minecraft-server","resources":{"limits":{"memory":"6Gi"}}}]}}}}'

# Uninstall (careful!)
./install-service.sh --plug minecraft --uninstall
```

### 🎯 What's Next?

Once your kids see this working, they'll want:
- Valheim server ⚔️
- Terraria server 🌍  
- Voice chat server 🎤
- Web dashboard 📊

**Good news:** Helix can deploy ALL of these just as easily!

---

## 🏆 The Bottom Line

You just deployed a **production-grade Minecraft server** with **enterprise infrastructure** in **60 seconds**.

Your kids are now accidentally learning **Kubernetes, DevOps, and cloud architecture**.

And you're saving **$240-600/year** compared to gaming VPS services.

**Welcome to the future of gaming infrastructure!** 🎮🚀
