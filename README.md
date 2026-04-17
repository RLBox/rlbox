# ClackyAI Rails7 starter

The template for ClackyAI

## Installation

Install dependencies:

* postgresql

    ```bash
    $ brew install postgresql
    ```

    Ensure you have already initialized a user with username: `postgres` and password: `postgres`( e.g. using `$ createuser -d postgres` command creating one )

* rails 7

    Using `rbenv`, update `ruby` up to 3.x, and install `rails 7.x`

    ```bash
    $ ruby -v ( output should be 3.x )

    $ gem install rails

    $ rails -v ( output should be rails 7.x )
    ```

* npm

    Make sure you have Node.js and npm installed

    ```bash
    $ npm --version ( output should be 8.x or higher )
    ```

Install dependencies, setup db:
```bash
$ ./bin/setup
```

## Running the Project

### Quick Start

**First-time setup** (install required tools):
```bash
$ ./bin/install-dev-tools    # Install tmux & overmind (auto-detect OS)
```

**Start the project:**
```bash
$ bin/dev          # Auto-uses overmind if available, falls back to foreman
$ bin/dev -D       # Run in background (daemon mode)
```

**View logs** (when running in background):
```bash
$ overmind connect    # Press Ctrl+B then D to detach
```

**Stop the project:**
```bash
$ overmind quit       # Graceful shutdown
# Or press Ctrl+C if running in foreground
```

**Restart a specific process:**
```bash
$ overmind restart web   # Restart Rails server
$ overmind restart css   # Restart CSS watcher
$ overmind restart js    # Restart JS bundler
```

### Manual Installation (if auto-install fails)

<details>
<summary>Click to expand manual installation steps</summary>

**macOS:**
```bash
$ brew install overmind tmux
```

**Ubuntu/Debian:**
```bash
$ sudo apt install tmux
$ wget https://github.com/DarthSim/overmind/releases/download/v2.5.1/overmind-v2.5.1-linux-amd64.gz
$ gunzip overmind-v2.5.1-linux-amd64.gz
$ sudo mv overmind-v2.5.1-linux-amd64 /usr/local/bin/overmind
$ sudo chmod +x /usr/local/bin/overmind
```

</details>

### Alternative: Terminal Foreground (No Installation Required)

If you don't want to install overmind/tmux, you can run with foreman (comes with Rails):
```bash
$ bin/dev    # Will automatically use foreman if overmind not found
```
⚠️ Note: Foreman mode only works in terminal foreground, cannot run in background.

## Admin dashboard info

This template already have admin backend for website manager, do not write business logic here.

Access url: /admin

Default superuser: admin

Default password: admin

## Tech stack

* Ruby on Rails 7.x
* Tailwind CSS 3 (with custom design system)
* Hotwire Turbo (Drive, Frames, Streams)
* Stimulus
* ActionCable
* figaro
* postgres
* active_storage
* kaminari
* puma
* rspec