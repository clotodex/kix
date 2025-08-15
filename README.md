# Kix - Kubernetes Manifest Management with Nix

This project demonstrates a Nix-based approach to managing Kubernetes manifests with explicit dependency tracking. It builds CoreDNS Kubernetes resources using Nix derivations to create a dependency graph that ensures proper ordering and relationships between components.

## Prerequisites

- Nix package manager (with flakes enabled)
- devenv (for development environment)

## Development Environment Setup

This project uses [devenv](https://devenv.sh/) to provide a consistent development environment with all necessary tools.

### Enter the Development Environment

```bash
# Start the development shell
devenv shell
```

This will automatically install and make available:
- `kubernetes-helm` - Kubernetes package manager
- `nix-tree` - Interactive dependency tree explorer
- Other development tools

## Project Structure

```
.
├── simple-dependency.nix           # Main Nix build configuration
├── devenv.nix           # Development environment configuration
├── yamls/               # Kubernetes YAML manifests
│   ├── clusterrole.yaml
│   ├── clusterrolebinding.yaml
│   ├── configmap.yaml
│   ├── deployment.yaml
│   └── service.yaml
└── README.md
```

## Building the Project

The `simple-dependency.nix` file defines several build targets that create a dependency graph for CoreDNS components:

### Build Individual Components

```bash
# Build individual Kubernetes resources
nix-build -A clusterrole
nix-build -A clusterrolebinding
nix-build -A configmap
nix-build -A service
nix-build -A deployment
```

### Build Complete Manifest Set

```bash
# Build all manifests ready for kubectl
nix-build -A kubectl

# Build the simple-dependency target (service - root of dependency tree)
nix-build

# Build all components as a symlinked collection
nix-build -A all
```

### Build and Apply to Kubernetes

```bash
# Build manifests and apply to cluster
kubectl apply -f $(nix-build -A kubectl)
```

## Dependency Graph

The project implements this dependency relationship:

```
clusterrole (no deps)
    ↓
clusterrolebinding (depends on clusterrole)
    ↓
configmap (independent)
    ↓
deployment (depends on configmap + clusterrolebinding)
    ↓
service (depends on deployment) ← ROOT NODE
```

## Inspecting Dependencies

### Using nix-tree (Interactive)

The development environment includes `nix-tree`, an interactive tool for exploring dependency graphs:

```bash
# Explore dependencies of the simple-dependency build
nix-tree

# Explore dependencies of a specific component
nix-tree $(nix-build -A kubectl)

# Explore dependencies of individual components
nix-tree $(nix-build -A deployment)
```

`nix-tree` provides an interactive TUI where you can:
- Navigate the dependency tree with arrow keys
- Expand/collapse nodes with Enter
- View detailed information about each dependency
- See which packages depend on what

### Using nix show-derivation

```bash
# Show the derivation details for a component
nix show-derivation $(nix-instantiate -A service)

# Show all derivations in the build
nix show-derivation $(nix-instantiate -A kubectl)
```

### Using nix-store Commands

```bash
# Show runtime dependencies
nix-store -q --references $(nix-build -A kubectl)

# Show reverse dependencies (what depends on this)
nix-store -q --referrers $(nix-build -A configmap)

# Show the full dependency closure
nix-store -q --requisites $(nix-build -A kubectl)

# Calculate closure size
nix-store -q --size $(nix-build -A kubectl)
```

### Graphical Dependency Visualization

```bash
# Generate a graphical representation of dependencies
nix-store -q --graph $(nix-build -A kubectl) | dot -Tpng > dependencies.png

# Or use a simpler text tree format
nix-store -q --tree $(nix-build -A kubectl)
```

## Understanding Build vs Runtime Dependencies

### Build Dependencies
These are dependencies needed during the build process:

```bash
# Show what's needed to build a component
nix-store -q --references $(nix-instantiate -A deployment)
```

### Runtime Dependencies
These are dependencies included in the final result:

```bash
# Show what the built component depends on at runtime
nix-store -q --references $(nix-build -A deployment)
```

## Working with Built Manifests

### Inspect Built Manifests

```bash
# List all built YAML files
ls $(nix-build -A kubectl)/

# View a specific manifest
cat $(nix-build -A kubectl)/deployment.yaml

# View the generated README
cat $(nix-build -A kubectl)/README.md
```

### Deploy to Kubernetes

```bash
# Apply all manifests
kubectl apply -f $(nix-build -A kubectl)/

# Apply individual components in dependency order
kubectl apply -f $(nix-build -A clusterrole)/clusterrole.yaml
kubectl apply -f $(nix-build -A clusterrolebinding)/clusterrolebinding.yaml
kubectl apply -f $(nix-build -A configmap)/configmap.yaml
kubectl apply -f $(nix-build -A deployment)/deployment.yaml
kubectl apply -f $(nix-build -A service)/service.yaml
```

## Development Workflow

1. **Enter Development Environment**:
   ```bash
   devenv shell
   ```

2. **Modify YAML Files**: Edit files in the `yamls/` directory

3. **Test Builds**:
   ```bash
   nix-build -A kubectl
   ```

4. **Inspect Dependencies**:
   ```bash
   nix-tree $(nix-build -A kubectl)
   ```

5. **Deploy and Test**:
   ```bash
   kubectl apply -f $(nix-build -A kubectl)/
   ```

## Advanced Usage

### Building with Different Nixpkgs

```bash
# Use a specific nixpkgs version
nix-build --arg pkgs 'import <nixpkgs-unstable> {}'
```

### Debugging Build Issues

```bash
# Build with verbose output
nix-build -A kubectl --show-trace

# Keep build directories for inspection
nix-build -A kubectl --keep-failed
```

### Custom Dependency Modifications

The dependency graph is defined in `simple-dependency.nix`. To modify dependencies:

1. Edit the `deps` parameter in the `mkYamlDerivation` calls
2. Rebuild to see the new dependency structure
3. Use `nix-tree` to verify the changes

## Troubleshooting

### Common Issues

1. **Build Failures**: Check that all YAML files exist and are valid
2. **Dependency Cycles**: Use `nix-tree` to identify circular dependencies
3. **Missing Dependencies**: Ensure all referenced components are included in the dependency list

### Debugging Commands

```bash
# Check if derivations are valid
nix-instantiate -A kubectl

# Verify YAML syntax
kubectl apply --dry-run=client -f $(nix-build -A kubectl)/
```

## Benefits of This Approach

1. **Explicit Dependencies**: Clear dependency relationships between Kubernetes resources
2. **Reproducible Builds**: Nix ensures consistent builds across environments
3. **Dependency Tracking**: Easy to see what depends on what
4. **Atomic Operations**: Build all or nothing - prevents partial deployments
5. **Development Environment**: Consistent tooling across team members

## Further Reading

- [Nix Manual](https://nixos.org/manual/nix/stable/)
- [devenv Documentation](https://devenv.sh/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)

