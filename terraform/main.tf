terraform {
  required_providers {
    docker = {
      source  = "terraform-providers/docker"
      version = "~> 2.0"
    }
  }
}

provider "docker" {}

resource "docker_network" "labnet" {
  name   = "lab3b_net"
  driver = "bridge"

  ipam_config {
    subnet  = "172.28.0.0/16"
    gateway = "172.28.0.1"
  }
}

resource "docker_image" "web_img" {
  name = "nginxdemos/hello:latest"
}

resource "docker_container" "web1" {
  name  = "web1"
  image = docker_image.web_img.name
  networks_advanced {
    name         = docker_network.labnet.name
    ipv4_address = "172.28.0.11"
  }
}

resource "docker_container" "web2" {
  name  = "web2"
  image = docker_image.web_img.name
  networks_advanced {
    name         = docker_network.labnet.name
    ipv4_address = "172.28.0.12"
  }
}

resource "docker_image" "haproxy_img" {
  name = "haproxy:latest"
}

resource "docker_container" "haproxy" {
  name  = "haproxy"
  image = docker_image.haproxy_img.name
  networks_advanced {
    name         = docker_network.labnet.name
    ipv4_address = "172.28.0.10"
  }
  ports {
    internal = 80
    external = 8080
  }
  volumes {
    host_path      = abspath("${path.module}/haproxy.cfg")
    container_path = "/usr/local/etc/haproxy/haproxy.cfg"
  }
}

resource "docker_image" "curl" {
  name = "curlimages/curl:latest"
}

resource "docker_container" "client" {
  name    = "client"
  image   = docker_image.curl.name
  command = ["sleep", "infinity"]
  networks_advanced {
    name         = docker_network.labnet.name
    ipv4_address = "172.28.0.20"
  }
}

# Added web3 container
resource "docker_container" "web3" {
  name  = "web3"
  image = docker_image.web_img.name
  networks_advanced {
    name         = docker_network.labnet.name
    ipv4_address = "172.28.0.13"
  }
}
