# Stage 8 — Docker Swarm HA

## Objective

The goal of this stage is to deploy the PetClinic application as a highly available Docker Swarm service.

The application is deployed with:

* Docker Swarm
* 1 Swarm Manager
* 2 Swarm Worker nodes
* 2 PetClinic replicas
* Overlay network
* Replica placement across two application nodes
* Restart policy
* Resource limits and reservations

At this stage, the application uses the default H2 database. PostgreSQL will be introduced in a later stage.

---

## Architecture

The current architecture is:

```text
                    WSL2
             Docker Swarm Manager
                 192.168.65.229
                       |
          +------------+------------+
          |                         |
          v                         v
  devops-manager             devops-worker
  192.168.56.101             192.168.56.103
          |                         |
       App #1                    App #2
          |                         |
          +------ petclinic-net ---+
                Overlay Network
```

The WSL machine is used only as the Swarm Manager.

The two VM nodes are used to execute the PetClinic containers.

---

## 1. Initialize Docker Swarm

Docker Swarm was initialized on the WSL machine:

```bash
docker swarm init --advertise-addr 192.168.65.229
```

The WSL machine became the Swarm Manager and Leader.

The Swarm state was verified with:

```bash
docker info --format '{{.Swarm.LocalNodeState}}'
```

Result:

```text
active
```

---

## 2. Join Worker Nodes

Two application nodes were joined to the Swarm:

```text
devops-manager
192.168.56.101
```

and:

```text
devops-worker
192.168.56.103
```

The final cluster was verified with:

```bash
docker node ls
```

Expected topology:

```text
DESKTOP-GM6VT7V   Ready   Active   Leader
devops-manager    Ready   Active
devops-worker     Ready   Active
```

---

## 3. Label Application Nodes

The two VM nodes were labeled:

```bash
docker node update --label-add app=true devops-manager
docker node update --label-add app=true devops-worker
```

The label allows the Swarm service to explicitly target application nodes.

The WSL Manager does not have the `app=true` label, so PetClinic is not scheduled there.

---

## 4. Overlay Network

A Swarm overlay network was created:

```bash
docker network create \
  --driver overlay \
  --attachable \
  petclinic-net
```

The network was verified with:

```bash
docker network ls
```

The overlay network allows containers running on different Swarm nodes to communicate through the same logical Docker network.

---

## 5. Docker Image Distribution

The PetClinic image was built previously as:

```text
petclinic:1.0
```

Because the application nodes use separate Docker Engines, the image available locally on WSL is not automatically available on the worker nodes.

For this lab environment, the image was exported from WSL:

```bash
docker save -o petclinic-1.0.tar petclinic:1.0
```

The image archive was copied to both application nodes and loaded using:

```bash
docker load -i /tmp/petclinic-1.0.tar
```

This ensured that both application nodes had:

```text
petclinic:1.0
```

available locally.

In a production environment, a container registry would normally be used instead of manually transferring image archives.

---

## 6. Swarm Stack Configuration

The application was deployed using:

```text
docker-stack.yml
```

The service uses H2 at this stage, so no PostgreSQL configuration is required.

The relevant configuration is:

```yaml
services:

  petclinic:
    image: petclinic:1.0

    environment:
      SPRING_PROFILES_ACTIVE: ""

    networks:
      - petclinic-net

    deploy:
      replicas: 2

      placement:
        constraints:
          - node.labels.app == true
        max_replicas_per_node: 1

      restart_policy:
        condition: on-failure
        delay: 5s
        max_attempts: 3
        window: 60s

      resources:
        limits:
          cpus: "1.0"
          memory: 1G

        reservations:
          cpus: "0.25"
          memory: 512M

networks:
  petclinic-net:
    external: true
```

---

## 7. Two Application Replicas

The service was deployed with:

```bash
docker stack deploy -c docker-stack.yml petclinic
```

The service was checked using:

```bash
docker service ls
```

The expected result is:

```text
petclinic_petclinic   replicated   2/2
```

This confirms that two replicas of the PetClinic service are running.

---

## 8. Replica Placement

The placement was verified using:

```bash
docker service ps petclinic_petclinic
```

The two replicas were distributed across the application nodes:

```text
petclinic_petclinic.1   devops-manager
petclinic_petclinic.2   devops-worker
```

The following configuration ensures this behavior:

```yaml
placement:
  constraints:
    - node.labels.app == true
  max_replicas_per_node: 1
```

`node.labels.app == true` restricts the service to application nodes.

`max_replicas_per_node: 1` prevents both replicas from being scheduled on the same node.

---

## 9. Application Exposure

The PetClinic service does not publish port 8080 directly:

```yaml
ports:
```

is intentionally not configured.

The application still listens on port 8080 inside its container, but the port is not exposed directly on the VM hosts.

This is intentional because the requirement states that the application should not be directly exposed to the Internet.

NGINX will be introduced in a later stage and will act as the external entry point.

The future architecture will be:

```text
Internet
    |
    v
  NGINX :80
    |
    v
petclinic-net
   / \
  /   \
App #1 App #2
```

---

## 10. Restart Policy

The service uses:

```yaml
restart_policy:
  condition: on-failure
  delay: 5s
  max_attempts: 3
  window: 60s
```

This tells Swarm to restart a failed application task according to the configured policy.

Swarm can also reschedule a task when a node becomes unavailable, depending on the cluster state and service configuration.

---

## 11. Resource Management

Resource limits and reservations were configured:

```yaml
resources:
  limits:
    cpus: "1.0"
    memory: 1G

  reservations:
    cpus: "0.25"
    memory: 512M
```

### Limits

The limits define the maximum resources the container is allowed to consume.

### Reservations

Reservations tell Swarm the minimum amount of resources that should be available on a node before scheduling the task.

This helps Swarm make better scheduling decisions.

---

## 12. Database

At this stage, PetClinic uses the default H2 database.

PostgreSQL is intentionally not part of this stage.

The database architecture will be introduced in a later stage:

```text
PetClinic
    |
    v
PostgreSQL Primary
    |
    v
PostgreSQL Replica
```

This separation allows the Swarm HA functionality to be tested independently before introducing database networking and replication.

---

## 13. Verification Commands

Useful commands used to verify the Swarm deployment:

### Check Swarm state

```bash
docker info --format '{{.Swarm.LocalNodeState}}'
```

### List nodes

```bash
docker node ls
```

### List services

```bash
docker service ls
```

### Inspect service tasks

```bash
docker service ps petclinic_petclinic
```

### View service logs

```bash
docker service logs petclinic_petclinic
```

### List networks

```bash
docker network ls
```

---

## Result

Stage 8 was successfully completed.

The final state is:

```text
                 WSL2
          Swarm Manager / Leader
             192.168.65.229
                    |
          +---------+---------+
          |                   |
          v                   v
  devops-manager        devops-worker
  192.168.56.101        192.168.56.103
          |                   |
       App #1              App #2
          \                   /
           \                 /
            +---------------+
             petclinic-net
              Overlay Network
```

### Acceptance Checklist

* [x] Docker Swarm initialized
* [x] WSL configured as Manager
* [x] Two application Worker nodes joined
* [x] Overlay network created
* [x] PetClinic deployed as a Swarm service
* [x] Minimum 2 replicas
* [x] Replicas distributed across two application nodes
* [x] Application not directly exposed through port 8080
* [x] Restart policy configured
* [x] Resource limits configured
* [x] Resource reservations configured
* [x] H2 used for this stage
* [x] PostgreSQL deferred to a later stage

**Stage 8 — COMPLETE**
