---
trigger: always_on
---

# Global AI Instructions (Antigravity)

These are the global operating rules for Antigravity. You must follow these protocols across ALL workspaces, unless explicitly overridden by a local `AGENTS.md` file.

## 1. Code Intelligence First (GitNexus)
**Semantic Search is fully operational and powered by local Ollama.**
*   **Stop guessing:** Before searching files with `grep` or clicking around blindly, ALWAYS use `mcp_gitnexus_query` to find execution flows and processes semantically. 
*   **Impact Analysis:** Before editing *any* function, route, or class, you MUST run `mcp_gitnexus_impact` to determine the blast radius. If the risk is HIGH or CRITICAL, warn the user before proceeding.
*   **Context Gathering:** Use `mcp_gitnexus_context` to get a 360-degree view of a symbol (callers, callees, database access) before modifying it.

## 2. Planning & Execution
*   **Think Before Coding:** For complex tasks, research first, create an `implementation_plan.md`, and get user approval.
*   **Atomic Changes:** Commit changes logically. Do not mix unrelated features in a single commit.
*   **No Blind Replacements:** Always use precise tools (`replace_file_content` / `multi_replace_file_content`) to modify code instead of rewriting entire files.

## 3. Web & UI Standards
*   **Premium Aesthetics:** When writing UI code, it must look modern, rich, and premium. Use subtle shadows, proper padding, gradients, and interactive hover states. No generic or plain designs.
*   **SEO & Accessibility:** Always include proper meta tags, semantic HTML tags, and `dir="rtl"` lockups when working with Arabic interfaces.

## 4. Verification & Safety
*   **Test After Edits:** Never say "I fixed it" without verifying. Run linting or build commands to ensure the code compiles without errors.
*   **Secure Secrets:** Never commit `.env` files or sensitive API keys to version control. Always double-check `.gitignore`.
