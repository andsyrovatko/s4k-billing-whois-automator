# Whois Infrastructure Automator (for ISPs)

### 🚀 The Problem
In large ISP infrastructures, keeping the `whois` description of IP addresses synchronized with the actual network topology is a manual nightmare. When a switch is renamed or replaced, hundreds of IP records can become outdated.

### 🛠 The Solution
This script automates the synchronization between a **PostgreSQL billing database** and a **local Whois server**.

### Key Features:
* ● **Auto-Discovery:** Fetches all IP addresses associated with a renamed switch from the DB.
* ● **Context-Aware Update:** Intelligently parses current Whois data and replaces only the relevant switch names.
* ● **Email Integration:** Automatically generates and sends update requests to the RIPE-like Whois mail robots.
* ● **Logging:** Full traceability of all actions and errors.

### 📖 Usage
1. Configure your credentials in `whois.conf`.
2. Run the script with the new switch name as an argument:
   ```bash
   ./whois_upd.sh "NEW_SWITCH_HOSTNAME"
   ```
### ⚖️ License
This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.


### Use at your own risk! The author is not responsible for any data loss!
