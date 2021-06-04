#!/usr/bin/env python3

import json
from jsonschema import Draft4Validator as Validator
import os
import sys

def test_json_schema(json_file, schema_file, meta_schema_file=""):
    with open(json_file, "r") as fh:
        json_data = json.loads(fh.read())
    with open(schema_file, "r") as fh:
        schema_data = json.loads(fh.read())
    if meta_schema_file:
        with open(meta_schema_file, "r") as fh:
            meta_schema_data = json.loads(fh.read())
        Validator(meta_schema_data).validate(schema_data)
        print("passed meta schema")
    Validator(schema_data).validate(json_data)
    print("passed schema")

if __name__ == '__main__':

    try:
        if len(sys.argv) <= 2:
            print("This tool validates json against a schema hierarchy.")
            sys.exit("Usage: json-schema-validator.py json schema [meta-schema]")
        elif len(sys.argv) == 3:
            test_json_schema(sys.argv[1], sys.argv[2])
        elif len(sys.argv) == 4:
            test_json_schema(sys.argv[1], sys.argv[2], sys.argv[3])
        else:
            sys.exit("please provide 2 or 3 args (json_file, schema, meta-schema")
        print("Success - the file matches the schema hierarchy!")
    except Exception as e:
        print("Failed!")
        print(e)


