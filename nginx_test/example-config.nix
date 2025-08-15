{
  services = {
    nginx = {
      enable = true;
      image = "nginx:1.25";
      replicas = 2;
      config = ''
user  nginx;
worker_processes auto;

events {
  worker_connections 1024;
}

http {
  server {
    listen 80;
    location / {
      return 200 'hello from nginx + nix derivations';
    }
  }
}
'';
    };
  };
}

