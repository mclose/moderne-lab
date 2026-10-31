#!/bin/bash
# Remove what the Moderne course created on this host, and nothing else.
#   ./uninstall.sh --dry-run          list what would be removed (start here)
#   ./uninstall.sh                    remove it, after one confirmation
#   ./uninstall.sh --all              also remove the labs' repo checkouts (Labs 1, 6, 7: public clones;
#                                     the labs need them again afterwards) and Lab 8's saved results
#   ./uninstall.sh --base-images      also remove public base images the labs pulled (maven:3.9-*),
#                                     but only ones no container on this host is using
# What counts as "created by the course":
#   - Docker images named moderne-lab-* or labelled course=moderne-lab, and their stopped containers
#   - Docker volumes moderne-lab-* (CLI home, recipe cache, Maven caches)
#   - lab caches and outputs: Maven cache, Lab 2 clones, demo runs, Lab 8 clones and results
#     (the scripts, Dockerfiles, docs, lab/recipes and the hand-made Lab 4 repo cli/ws/local always stay)
#   - ~/.config/moderne-lab (the Lab 8 Copilot token)
#   - host tools listed in lab/.installed as installed by the course (none on Linux; the file is how a
#     Mac setup would record e.g. a container runtime it added). Tools you already had are never touched.
set -uo pipefail
LAB="$(cd "$(dirname "$0")" && pwd)"
DRY=0 BASE=0 ALL=0
for a in "$@"; do
  case $a in --dry-run) DRY=1 ;; --base-images) BASE=1 ;; --all) ALL=1 ;; *) sed -n 2,17p "$0"; exit 1 ;; esac
done

images=$( { docker images --format '{{.Repository}}:{{.Tag}}' | grep -E '^moderne-lab-'
            docker images --filter label=course=moderne-lab --format '{{.Repository}}:{{.Tag}}'; } | sort -u)
containers=$(docker ps -a --filter label=course=moderne-lab --format '{{.ID}} {{.Image}} {{.Status}}'
             for i in $images; do docker ps -a --filter ancestor="$i" --format '{{.ID}} {{.Image}} {{.Status}}'; done)
containers=$(echo "$containers" | sed '/^$/d' | sort -u -k1,1)
volumes=$(docker volume ls --format '{{.Name}}' | grep -E '^moderne-lab-' || true)
base=""
if [ $BASE = 1 ]; then
  for i in maven:3.9-eclipse-temurin-17 maven:3.9-eclipse-temurin-21; do
    docker image inspect "$i" >/dev/null 2>&1 || continue
    [ -n "$(docker ps -a --filter ancestor="$i" -q)" ] && { echo "keeping $i: a container uses it"; continue; }
    base="$base $i"
  done
fi
dirs=""
gone=(.m2 cli/ws/repos cli/ws/demo cli/ws/demo-first-run ab/ws ab2/ws)
[ $ALL = 1 ] && gone+=(spring-petclinic rivals/ws own/ws ab/results ab2/results)
for d in "${gone[@]}"; do [ -e "$LAB/$d" ] && dirs="$dirs $LAB/$d"; done
[ -e "$HOME/.config/moderne-lab" ] && dirs="$dirs $HOME/.config/moderne-lab"
tools=""
[ -f "$LAB/.installed" ] && tools=$(awk '$2=="installed-by-course"{print $1}' "$LAB/.installed")

echo "== Containers (running ones are stopped first)"; echo "${containers:-  none}" | sed 's/^/  /'
echo "== Images";  for i in $images $base; do echo "  $i  $(docker image inspect -f '{{.Size}}' "$i" | numfmt --to=si)"; done; [ -z "$images$base" ] && echo "  none"
echo "== Volumes"; for v in $volumes; do echo "  $v"; done; [ -z "$volumes" ] && echo "  none"
echo "== Folders"; for d in $dirs; do echo "  $d  $(du -sh "$d" 2>/dev/null | cut -f1)"; done; [ -z "$dirs" ] && echo "  none"
echo "== Host tools installed by the course"; [ -n "$tools" ] && echo "$tools" | sed 's/^/  /' || echo "  none"
echo "== Left alone: Docker itself, git, Java, Maven, Node, VS Code, gh, and anything not listed above"

[ $DRY = 1 ] && { echo; echo "(dry run: nothing removed)"; exit 0; }
[ -z "$containers$images$base$volumes$dirs$tools" ] && { echo "nothing to remove"; exit 0; }
read -rp $'\nRemove everything listed above? [y/N] ' ok; [ "$ok" = y ] || { echo "nothing removed"; exit 0; }

[ -n "$containers" ] && echo "$containers" | awk '{print $1}' | xargs docker rm -f >/dev/null
for i in $images $base; do docker image rm "$i" >/dev/null && echo "removed image $i"; done
for v in $volumes; do docker volume rm "$v" >/dev/null && echo "removed volume $v"; done
for d in $dirs; do rm -rf "$d" && echo "removed $d"; done
for t in $tools; do
  case $t in   # allow-list: only tools the course knows how to install and remove
    colima) brew uninstall colima && echo "removed colima" ;;
    *) echo "don't know how to remove '$t'; left in place" ;;
  esac
done
[ -n "$tools" ] && rm -f "$LAB/.installed"
echo "Build cache isn't tracked per project; 'docker builder prune' clears it for everything on this host."
