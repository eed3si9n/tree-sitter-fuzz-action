#!/bin/sh
ROOT_DIR="fuzzer"

LANG=$1
TIME=$2

shift 2

export PATH="/root/.cargo/bin:$PATH"
export CFLAGS="$(pkg-config --cflags --libs tree-sitter) -O0 -g -Wall"

JQ_FILTER='.. | if .type? == "STRING" or (.type? == "ALIAS" and .named? == false) then .value else null end'

build_dict() {
  cat src/grammar.json | jq "$JQ_FILTER" |\
    grep -v "\\\\" | grep -v null > $ROOT_DIR/dict
}

build_fuzzer() {
  cat <<END | clang -fsanitize=fuzzer,address $CFLAGS -lstdc++ -g -x c - src/parser.c $@ -o $ROOT_DIR/fuzzer
#include <stdio.h>
#include <stdlib.h>
#include <tree_sitter/api.h>

TSLanguage *tree_sitter_$LANG();

int LLVMFuzzerTestOneInput(const uint8_t * data, const size_t len) {
  // Create a parser.
  TSParser *parser = ts_parser_new();

  // Set the parser's language.
  ts_parser_set_language(parser, tree_sitter_$LANG());

  // Build a syntax tree based on source code stored in a string.
  TSTree *tree = ts_parser_parse_string(
    parser,
    NULL,
    (const char *)data,
    len
  );
  // Free all of the heap-allocated memory.
  ts_tree_delete(tree);
  ts_parser_delete(parser);
  return 0;
}
END
}

generate_fuzzer() {
  tree-sitter generate
}

makedirs() {
  mkdir -p "$ROOT_DIR"
  mkdir -p "$ROOT_DIR/out"
}

makedirs
generate_fuzzer

build_dict
build_fuzzer $@
cd "$ROOT_DIR"
./fuzzer -dict=dict -max_total_time=$TIME -fork=1 --ignore_ooms --ignore_timeout out/
