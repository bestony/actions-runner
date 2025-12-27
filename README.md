# actions-runner
Dockerfile for the creation of a GitHub Actions runner image to be deployed dynamically. [Find the full explanation and tutorial here](https://baccini-al.medium.com/creating-a-dockerfile-for-dynamically-creating-github-actions-self-hosted-runners-5994cc08b9fb).

When running the docker image, or when executing docker compose, environment variables for repo-owner/repo-name and github-token must be included. 

Credit to [testdriven.io](https://testdriven.io/blog/github-actions-docker/) for the original start.sh script, which I slightly modified to make it work with a regular repository rather than with an enterprise. 

Whene generating your GitHub PAT you will need to include `repo`, `workflow`, and `admin:org` permissions.



## first run

```yaml
services:
  runner:
    image: bestony/actions-runner:latest
    restart: unless-stopped
    networks:
      - runner
    environment:
      - REPO=<owner>/<repo>
      - TOKEN=<your-github-personal-access-token>
      - ACTIONS_RESULTS_URL=http://cache:3000/
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    deploy:
      mode: replicated
      replicas: 4
      resources:
        reservations:
          cpus: 0.5
          memory: 1024M
  cache:
    image: ghcr.io/falcondev-oss/github-actions-cache-server:latest
    restart: unless-stopped
    container_name: cache
    networks:
      - runner
    ports:
      - "3000:3000"
    environment:
      API_BASE_URL: http://cache:3000
    volumes:
      - cache:/app/.data

volumes:
  cache:

networks:
  runner:
    external: true
```


## other run
```yaml
services:
  another-runner:
    image: bestony/actions-runner:latest
    networks:
      - runner
    environment:
      - REPO=<another-repo>
      - TOKEN=<your-token>
      - ACTIONS_RESULTS_URL=http://cache:3000/
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock

networks:
  runner:
    external: true # 声明这是一个外部已存在的网络
```
