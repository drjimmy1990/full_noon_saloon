# GitNexus: Complete Docker Setup & Usage Guide

GitNexus is a Code Intelligence Engine that indexes your codebase into a knowledge graph. Because the native Windows version currently has a bug with its database engine, **Docker is the recommended and most stable way to run it.**

This guide covers everything from setup to connecting AI agents (MCP), generating wikis using local AI (Ollama), and an exhaustive list of all commands.

---

## 🛠️ Step 1: Start GitNexus via Docker Compose

GitNexus requires two containers to run: a backend server (for analysis/API) and a frontend web UI.

1.  In the root folder of any project you want to analyze, create a file named `docker-compose.yml` with the following content:

    ```yaml
    services:
      server:
        image: ghcr.io/abhigyanpatwari/gitnexus:latest
        container_name: gitnexus-server
        restart: unless-stopped
        ports:
          - "4747:4747"
        volumes:
          - gitnexus-data:/data/gitnexus
          - ${WORKSPACE_DIR:-.}:/workspace
        environment:
          - NODE_ENV=production

      web:
        image: ghcr.io/abhigyanpatwari/gitnexus-web:latest
        container_name: gitnexus-web
        restart: unless-stopped
        ports:
          - "4173:4173"
        environment:
          - VITE_API_URL=http://localhost:4747
        depends_on:
          - server

    volumes:
      gitnexus-data:
    ```

2.  Open your terminal in that folder and start the stack:
    ```bash
    docker compose up -d
    ```
    *This maps your current folder to `/workspace` inside the container.*

---

## 📊 Step 2: Analyze Your Project

Because the global `gitnexus` alias is not mapped in the official Docker image, you must call the node script directly using `docker exec`.

To analyze the current folder that is mounted as `/workspace`:

**If it is a Git repository:**
```bash
docker exec gitnexus-server node /app/gitnexus/dist/cli/index.js analyze /workspace
```

**If it is NOT a Git repository (or you want to ignore Git history):**
```bash
docker exec gitnexus-server node /app/gitnexus/dist/cli/index.js analyze /workspace --skip-git
```

### ⚠️ Fixing the "dubious ownership" git error
If you see a `fatal: detected dubious ownership in repository` error during analysis or wiki generation, it is because the Docker container runs as `root` while your files are owned by your Windows user. Fix it by running this once:
```bash
docker exec gitnexus-server git config --global --add safe.directory /workspace
```

---

## 👁️ Step 3: Explore the Web UI

Once the analysis is complete (you will see node and edge counts), you can view the interactive graph.

1.  Open your web browser.
2.  Go to **[http://localhost:4173](http://localhost:4173)**.
3.  The dashboard will automatically connect to the backend and display your mapped codebase.

---

## 🧠 Step 4: Connecting & Using GitNexus in Your IDE (MCP Setup)

GitNexus acts as a Model Context Protocol (MCP) server. By connecting it to your AI IDE (like Cursor or Windsurf), the AI gets direct access to the knowledge graph. This means the AI won't break call chains or miss hidden dependencies when writing code for you.

Because you are running in Docker, you must manually add the MCP configuration to your editor.

### 1. Where to put the configuration
Because you are running GitNexus in Docker with the Web UI enabled, the database is "locked" by the web server. To prevent conflicts, you must connect your IDE to the server over HTTP (SSE) instead of running a CLI command.

Depending on your IDE, you need to add the GitNexus server to its MCP settings:

*   **Cursor:**
    1. Go to **Cursor Settings** > **Features** > **MCP**.
    2. Click **+ Add New MCP Server**.
    3. Set Type to `sse` (NOT command).
    4. Set Name to `gitnexus`.
    5. Set URL to `http://localhost:4747/api/mcp`

*   **Windsurf:**
    1. Open your `~/.codeium/windsurf/mcp_config.json` file.
    2. Add the GitNexus JSON block using the `sse` type:
    ```json
    {
      "mcpServers": {
        "gitnexus": {
          "type": "sse",
          "url": "http://localhost:4747/api/mcp"
        }
      }
    }
    ```

*   **Claude Desktop:**
    Currently, Claude Desktop only supports `command` execution for MCP. If you must use Claude Desktop, you must stop the background web server (`docker stop gitnexus-server`) and configure Claude to use the `docker exec` command method:
    ```json
    {
      "mcpServers": {
        "gitnexus": {
          "command": "docker",
          "args": ["exec", "-i", "gitnexus-server", "node", "/app/gitnexus/dist/cli/index.js", "mcp"]
        }
      }
    }
    ```

### 3. How to Use It (Prompting the AI)
Once connected, your IDE will automatically see GitNexus as an available tool. You don't need to run CLI commands anymore; you just talk to the AI normally!

**Examples of what to ask your IDE's AI:**
*   *"I want to modify the `loginUser` function. Use GitNexus to check the blast radius and tell me what other files will break if I change its return type."*
*   *"Use GitNexus to give me a 360-degree context of the `DatabaseService` class. Who calls it?"*
*   *"Query the GitNexus graph to find the execution flow for user registration."*
*   *"I'm getting a bug in the cart component. Can you check GitNexus to see what recent files interact with this module?"*

The AI will automatically execute background queries against your Docker container and give you incredibly accurate answers based on the whole architecture, not just the files you have open.

---

## 🤖 Step 5: Generate an AI Wiki (Using Local Ollama)

GitNexus can auto-generate a documentation wiki based on your codebase graph. You can use free, local AI via Ollama to do this without paying for OpenAI keys.

### 1. Setup Ollama
Make sure you have Ollama installed on Windows and running. Download a model (like `llama3` or `mistral`).
```bash
ollama run llama3
```

### 2. Run the Wiki Command pointing to Ollama
Because GitNexus is running inside Docker, it cannot use `localhost` to talk to your Windows machine. Instead, Docker uses `host.docker.internal` to route traffic to your host PC.

Run this command to generate the Wiki using Ollama:
```bash
docker exec -u node gitnexus-server sh -c "cd /workspace && node /app/gitnexus/dist/cli/index.js wiki . --base-url http://host.docker.internal:11434/v1 --model llama3 --api-key ollama"
```
*(If you are using a different model like `mistral`, change `--model llama3` to `--model mistral`)*.

---

## 📚 Complete Command Reference

Because you are running GitNexus in Docker, **every command must be prefixed with:**
`docker exec -u node gitnexus-server node /app/gitnexus/dist/cli/index.js`

Here is the exhaustive list of all commands available in GitNexus and what they do. Just append these to the prefix above!

### General & Setup Commands
*   **`setup`**: One-time setup to configure MCP for Cursor, Claude Code, OpenCode, Codex. *(Not recommended in Docker, use manual JSON setup above).*
*   **`mcp`**: Start the MCP server via stdio. (Used internally by editors).
*   **`serve`**: Start the local HTTP server for the Web UI connection. *(Already handled by docker-compose).*
*   **`eval-server`**: Start a lightweight HTTP server for fast tool calls during evaluation.

### Analysis & Indexing
*   **`analyze [path]`**: Perform a full deep-scan analysis of a repository.
    *   *Flags:* `--skip-git` (ignore git requirement), `-f` (force re-index), `--embeddings` (enable semantic search).
*   **`index [path]`**: Register an existing `.gitnexus/` folder into the global registry without having to re-analyze it.
*   **`group`**: Manage repository groups for cross-index impact analysis (analyzing blast radius across multiple repos).

### Knowledge Graph Exploration
*   **`list`**: List all indexed repositories known to your local registry.
*   **`status`**: Show the current index status for the repository you are in.
*   **`context [name]`**: Get a 360-degree view of a specific code symbol (who calls it, what it calls, what processes it affects).
*   **`impact <target>`**: Perform a "Blast radius" analysis. See exactly what will break if you modify or delete a specific symbol.
*   **`query <search_query>`**: Search the knowledge graph for execution flows related to a specific concept.
*   **`cypher <query>`**: Execute a raw, custom Cypher database query against the knowledge graph. Example: `cypher "MATCH (n) RETURN n LIMIT 10"`
*   **`augment <pattern>`**: Augment a search pattern with knowledge graph context (mostly used by AI hooks).
*   **`detect-changes`**: Map git diff hunks to indexed symbols to see how your uncommitted changes affect execution flows.

### Documentation
*   **`wiki [path]`**: Generate a complete repository wiki from the knowledge graph using an LLM (like OpenAI or Ollama).

### Cleanup
*   **`clean`**: Delete the GitNexus index for the current repository.
*   **`remove <target>`**: Delete the index for a registered repo by its alias, name, or absolute path.

---
*For the most up-to-date documentation, always check the [official GitNexus GitHub repository](https://github.com/abhigyanpatwari/GitNexus).*


docker exec gitnexus-server node /app/gitnexus/dist/cli/index.js wiki /workspace --base-url http://host.docker.internal:11434/v1 --model gemma4:31b-cloud --api-key ollama --force