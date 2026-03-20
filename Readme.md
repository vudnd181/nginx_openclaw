Here's the full walkthrough, in order:                                                                     
                                                                                                           
  ---                                                                                                        
  Step 1: Create the shared Docker network (one-time)                                                        
                                                                                                             
  docker network create bot-proxy-net                                                                      
                                                                                                             
  ---                                    
  Step 2: Configure your domain in nginx/.env                                                                
                                                                                                             
  cd /path/to/auto_bot/nginx                                             
  nano .env                                                                                                  
                                     
  Change these two lines to your real values:                                                                
  DOMAIN=dashboard.yourdomain.com        
  CERTBOT_EMAIL=you@yourdomain.com                                                                           
                                     
  ---                                                                    
  Step 3: Configure DNS at Cloudflare                                                                        
  
  Add two records pointing to your VPS IP:                                                                   
                                     
  ┌──────┬─────────────┬─────────────┐                                                                       
  │ Type │    Name     │    Value    │   
  ├──────┼─────────────┼─────────────┤                                                                       
  │ A    │ dashboard   │ YOUR_VPS_IP │
  ├──────┼─────────────┼─────────────┤                                   
  │ A    │ *.dashboard │ YOUR_VPS_IP │   
  └──────┴─────────────┴─────────────┘                                                                       
  
  Wait a few minutes for propagation.                                                                        
                                     
  ---                                                                    
  Step 4: Create Cloudflare API token    
                                                                                                             
  1. Go to https://dash.cloudflare.com/profile/api-tokens
  2. Create token → Edit zone DNS template                                                                   
  3. Scope it to your domain's zone                                                                          
  4. Copy the token                                                                                          
                                                                                                             
  Then create the credentials file:                                                                          
                                                                         
  cd /path/to/auto_bot/nginx                                                                                 
  nano ssl/cloudflare.ini                
                                                                         
  Paste:                                                                                                     
  dns_cloudflare_api_token = your-token-here
                                                                                                             
  Lock it down:                      
  chmod 600 ssl/cloudflare.ini                                           
                                         
  ---                                                                                                        
  Step 5: Regenerate bot docker-compose with the new network
                                                                                                             
  cd /path/to/auto_bot/openclaw_docker
  ./generate-compose.sh                                                                                      
                                         
  This does 3 things:                                                                                        
  - Adds bot-proxy-net network to each bot service
  - Generates nginx/nginx.conf with your domain                                                              
  - Generates nginx/conf.d/vu.conf for the existing bot
                                                                                                             
  ---                                    
  Step 6: Restart bot containers (to join the new network)                                                   
                                                                                                             
  cd /path/to/auto_bot/openclaw_docker                                   
  docker compose up -d                                                                                       
                                     
  The existing vu container will be recreated with the bot-proxy-net network attached.                       
                                         
  ---                                                                                                        
  Step 7: Bootstrap SSL and start nginx  
                                                                                                             
  cd /path/to/auto_bot/nginx             
  ./scripts/init-ssl.sh                                                                                      
                                     
  This will:                                                             
  1. ✅ Validate prerequisites (network exists, cloudflare.ini present)
  2. 📝 Create a temporary self-signed cert                                                                  
  3. 🚀 Start nginx with the temp cert     
  4. 🔐 Request a real wildcard cert from Let's Encrypt via Cloudflare DNS                                   
  5. 🔄 Reload nginx with the real cert                                                                      
                                                                                                             
  ---                                                                                                        
  Step 8: Verify                                                                                             
                                                                                                             
  # Check nginx is running                                               
  docker ps | grep bot-nginx                                                                                 
                                     
  # Test nginx config is valid                                           
  docker exec bot-nginx nginx -t         
                                                                                                             
  # Test the bot dashboard (from your VPS)
  curl -I https://vu.dashboard.yourdomain.com/health                                                         
                                                                                                             
  # Check certbot is running                                                                                 
  docker ps | grep bot-certbot                                                                               
                                                                                                             
  Open https://vu.dashboard.yourdomain.com in your browser — you should see a valid Let's Encrypt cert.      
                                                                         
  ---                                                                                                        
  Going forward: deploy a new bot    
                                                                                                             
  Everything is automatic now:           
                                                                                                             
  cd /path/to/auto_bot/openclaw_docker
  ./deploy-bot.sh alice 123456:ABC 658635669                             
                                                                                                             
  Output will include:
  ✅ Nginx reloaded with config for alice.dashboard.yourdomain.com                                           
  🚀 Bot 'alice' is now running!                                  
     Dashboard:  https://alice.dashboard.yourdomain.com                                                      
                                                       
  No manual nginx config needed — generate-compose.sh creates nginx/conf.d/alice.conf and reloads nginx      
  automatically.   