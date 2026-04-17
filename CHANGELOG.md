# RLBox Changelog

## [Unreleased] - 2026-04-17

### Added
- **Smart `bin/dev` script** that auto-detects overmind and gracefully falls back to foreman
- **One-click installation script** `bin/install-dev-tools` for cross-platform setup (macOS & Ubuntu)
- **Background execution support** via `bin/dev -D` (daemon mode with overmind)
- **Comprehensive startup documentation** in README.md with three execution modes

### Changed
- `bin/dev` now prefers overmind over foreman when available
- Updated `.clackyrules` with new startup workflow and tool detection logic
- Enhanced README with simplified quick start guide
- Added esbuild `--watch=forever` flag to prevent early exit in background mode

### Fixed
- Background execution failure due to Tailwind CSS stdin dependency
- Foreman process termination when CSS watcher exits

### Technical Details

**Problem**: Running `bin/dev` in background (e.g., `nohup bin/dev &`) failed because:
1. Tailwind CSS watch requires active stdin stream
2. When stdin closes in background mode, Tailwind exits with code 0
3. Foreman detects child process exit and terminates all processes

**Solution**: Use overmind + tmux to provide proper pseudo-terminal environment:
- overmind creates tmux session with full tty support
- All watch processes (Rails, esbuild, Tailwind) receive active stdin
- Background execution works perfectly with `-D` flag

**User Impact**:
- **Before**: Only terminal foreground execution worked
- **After**: Both foreground and background modes supported
- **Migration**: Run `./bin/install-dev-tools` once, then use `bin/dev` as normal

### Files Modified
- `bin/dev` - Smart tool detection and execution
- `bin/install-dev-tools` - New installation script
- `README.md` - Updated startup documentation
- `.clackyrules` - Updated AI behavior rules
- `package.json` - Added esbuild `--watch=forever` flag
- `~/.clacky/memories/rlbox-overmind-startup.md` - Complete solution documentation

### Backward Compatibility
- ✅ Existing users can continue using `bin/dev` without changes
- ✅ Falls back to foreman if overmind not installed
- ✅ No breaking changes to project structure or dependencies

---

## Legend
- **Added**: New features
- **Changed**: Changes in existing functionality
- **Deprecated**: Soon-to-be removed features
- **Removed**: Removed features
- **Fixed**: Bug fixes
- **Security**: Vulnerability fixes
