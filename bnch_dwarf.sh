#! /usr/bin/env sh
set -e

mode=$1
build=$2

if [ "$mode" = "dev" ]; then
  if [ "$build" = "build" ]; then
    set -x
    crystal build -p ./bnch_dwarf.cr -o bnch_dwarf-dev
    bin/crystal build -p ./bnch_dwarf.cr -o bnch_dwarf-scan-dev
    set +x
  fi

  echo
  echo "dev (1.21.0)"
  ./bnch_dwarf-dev | column -t

  echo
  echo "dev (one-by-one)"
  ./bnch_dwarf-scan-dev | column -t

  echo
  echo "dev (one-by-one, fn-cache)"
  dw_cache_functions=1 ./bnch_dwarf-scan-dev | column -t

  echo
  echo "dev (one-by-one, fn-cache, ln-index)"
  dw_cache_functions=1 dw_index_lines=1 ./bnch_dwarf-scan-dev | column -t

  echo
  echo "dev (many-at-once)"
  dw_many=1 ./bnch_dwarf-scan-dev | column -t

  echo
  echo "dev (many-at-once, fn-cache)"
  dw_many=1 dw_cache_functions=1 ./bnch_dwarf-scan-dev | column -t
elif [ "$mode" = "rel" ]; then
  if [ "$build" = "build" ]; then
    set -x
    crystal build -p ./bnch_dwarf.cr --release -o bnch_dwarf-release
    bin/crystal build -p ./bnch_dwarf.cr --release -o bnch_dwarf-scan-release
    set +x
  fi

  echo
  echo "rel (1.21.0)"
  ./bnch_dwarf-release | column -t

  echo
  echo "rel (one-by-one)"
  ./bnch_dwarf-scan-release | column -t

  echo
  echo "rel (one-by-one, fn-cache)"
  dw_cache_functions=1 ./bnch_dwarf-scan-release | column -t

  echo
  echo "dev (one-by-one, fn-cache, ln-index)"
  dw_cache_functions=1 dw_index_lines=1 ./bnch_dwarf-scan-release | column -t

  echo
  echo "rel (many-at-once)"
  dw_many=1 ./bnch_dwarf-scan-release | column -t

  echo
  echo "rel (many-at-once, fn-cache)"
  dw_many=1 dw_cache_functions=1 ./bnch_dwarf-scan-release | column -t
else
  echo "usage: bnch_dwarf.sh <dev|rel> [build]"
  exit 1
fi
