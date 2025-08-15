# KWIX - Kubernetes with Nix

This repository is playing around with bringing NIX benefits to the kubernetes space

## What this project is looking into

- dependecy trees from derivations
- transitive service dependencies (e.g. coredns activating prometheus if i configure it there)
- module abstractions

## What is the next ambitious goal post?

Turn `services.cloud-run = { enable = True, app = <image> }` into a full cluster deployment that creates from monitoring to auto-scaling.

## Why not kubenix?

Kubenix is a great project but to me solves the wrong problem.
To oversimplify, kubenix simply allows you to write yaml in nix, with full typing support.
I might revisit or build on top of it at some time. (see simple helmfile)

# Experimental projects

## Simple Derivations (./simple-dependency/)

Playing around with composing deployments from individual yaml files via dependencies

## Deployment Module (./nginx_test)

Testing the nix module system and composability to write pure nix and generate json.
This also investigates runtime-dependencies through path mentions.
These can also be investigated runtime as annotation

## Simple Helmfile (./nhelmfile/)

TODO

This feels like it is REALLY easy to mirror by using kubenix helm under the hood and describing in one nix file what you want.
Perfectly locked, perfectly reproducible, and no need to use helmfile at all.

## CoreDNS module (./coredns/) ~ helm replacement?

In Progress

Thoughts:
- we can likely drop a lot of values by always offering manual merging with the final attrset per yaml (kustomize type behavior)
- values.yaml is a mess. some values are only declared in comments, their usage might diverge from their consumtion etc
- roles and bindings etc need to have primitives to reduce duplication and enable label sharing

# Weird thougths

- nixos vms as runtime in k8s
- direct image builds including the config in the image etc (not far fetched but needs registry that can handle this well - e.g. the nix store type registry)
