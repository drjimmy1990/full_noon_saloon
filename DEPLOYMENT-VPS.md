# Linux VPS Deployment Guide (Noon Salon System)

This guide covers deploying the unified Monorepo (`saloon-mostafa` and `gardenia-website`) to a Linux VPS (Ubuntu/Debian) using **PM2** as the process manager and **Nginx** as the reverse proxy.

## 1. Prerequisites

First, SSH into your Linux VPS and update your system:

```bash
sudo apt update && sudo apt upgrade -y
```

Install the required dependencies: **Node.js**, **Git**, **Nginx**, and **PM2**.

```bash
# Install Node.js (v20 recommended)
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs git nginx

# Verify installation
node -v
npm -v

# Install PM2 globally
sudo npm install -g pm2
```

---

## 2. Clone the Repository

Navigate to your web directory and clone the unified monorepo. Since all projects are now in a single repository on the `main` branch, you only need to clone it once.

```bash
mkdir -p /www/wwwroot
cd /www/wwwroot

# Clone the unified monorepo
git clone https://github.com/drjimmy1990/full_noon_saloon.git saloooon

# The structure will now be:
# /www/wwwroot/saloooon/saloon-mostafa (Dashboard)
# /www/wwwroot/saloooon/gardenia-website (Storefront)
```

---

## 3. Setup Environment Variables

Both projects require `.env` files to connect to Supabase, the Evolution API, and other services.

### Dashboard (`saloon-mostafa`)
```bash
cd /www/wwwroot/saloooon/saloon-mostafa
nano .env
```
Add your production variables:
```env
NEXT_PUBLIC_SUPABASE_URL=your_supabase_url
NEXT_PUBLIC_SUPABASE_ANON_KEY=your_anon_key
SUPABASE_SERVICE_ROLE_KEY=your_service_role_key

# Evolution API (WhatsApp)
EVOLUTION_API_URL=your_evolution_api_url
EVOLUTION_API_KEY=your_evolution_api_key

# Add any other required variables (Paymob, etc.)
```

### Website (`gardenia-website`)
```bash
cd /www/wwwroot/saloooon/gardenia-website
nano .env
```
Add your production variables for the website:
```env
NEXT_PUBLIC_SUPABASE_URL=your_supabase_url
NEXT_PUBLIC_SUPABASE_ANON_KEY=your_anon_key
SUPABASE_SERVICE_ROLE_KEY=your_service_role_key
```

---

## 4. Install Dependencies & Build

You must install dependencies and compile the Next.js apps for production.

### Build the Dashboard
```bash
cd /www/wwwroot/saloooon/saloon-mostafa
npm install
npm run build
```

### Build the Website
```bash
cd /www/wwwroot/saloooon/gardenia-website
npm install
npm run build
```

---

## 5. Start the Apps with PM2

PM2 will keep your Next.js apps running in the background and restart them if they crash.

```bash
# Start the Dashboard on a specific port (e.g., 3000)
cd /www/wwwroot/saloooon/saloon-mostafa
pm2 start npm --name "salon-dashboard" -- start -- -p 3000

# Start the Website on a different port (e.g., 3001)
cd /www/wwwroot/saloooon/gardenia-website
pm2 start npm --name "salon-website" -- start -- -p 3001

# Save the PM2 list so it restarts on server reboot
pm2 save
pm2 startup
```
*(Run the command PM2 outputs after running `pm2 startup`)*

---

## 6. Configure Nginx (Reverse Proxy)

Nginx will map your domains to the local ports (3000 and 3001).

```bash
sudo nano /etc/nginx/sites-available/saloooon
```

Paste the following configuration (replace the `server_name` with your actual domains):

```nginx
# Configuration for Dashboard
server {
    listen 80;
    server_name dashboard.yourdomain.com; # <--- CHANGE THIS

    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
    }
}

# Configuration for Website
server {
    listen 80;
    server_name www.yourdomain.com yourdomain.com; # <--- CHANGE THIS

    location / {
        proxy_pass http://localhost:3001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
    }
}
```

Enable the configuration and restart Nginx:
```bash
sudo ln -s /etc/nginx/sites-available/saloooon /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl restart nginx
```

---

## 7. Secure with SSL (Let's Encrypt)

To secure your websites with HTTPS, install Certbot:

```bash
sudo apt install -y certbot python3-certbot-nginx

# Request SSL certificates for your domains
sudo certbot --nginx -d dashboard.yourdomain.com
sudo certbot --nginx -d yourdomain.com -d www.yourdomain.com
```

Follow the prompts. Certbot will automatically configure Nginx to use SSL and set up auto-renewal.

---

## 🎉 Deployment Complete!
Your applications are now live. 

### Useful PM2 Commands for Maintenance:
- **View logs:** `pm2 logs`
- **Restart dashboard:** `pm2 restart salon-dashboard`
- **Restart website:** `pm2 restart salon-website`
- **Monitor performance:** `pm2 monit`
