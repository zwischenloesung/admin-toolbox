#!/usr/bin/env python3

import json
import yaml
from jsonschema import Draft7Validator as Validator
import os
import sys

def load_data(filename):
    try:
        print("Trying JSON")
        with open(filename, "r") as fh:
            data = json.loads(fh.read())
#            print(data)
            return data
    except json.decoder.JSONDecodeError:
        try:
            print("Trying YAML")
            with open(filename, "r") as fh:
                data = yaml.load(fh.read())
#                print(data)
                return data
        except yaml.scanner.ScannerError as e:
            print(e)
            sys.exit("The input is not JSON (/YAML)")
        except Exception as e:
            print(e)
    except Exception as e:
        print(e)
        print("Could not read the imput file.")

def test_json_schema(json_file, schema_file, meta_schema_file=""):
    json_data = load_data(json_file)
    schema_data = load_data(schema_file)
    if meta_schema_file:
        meta_schema_data = load_data(meta_schema_file)
        Validator(meta_schema_data).validate(schema_data)
        print("passed meta schema")
    Validator(schema_data).validate(json_data)
    print("passed schema")

if __name__ == '__main__':

    try:
        if len(sys.argv) <= 2:
            print("This tool validates json/yaml against a schema hierarchy.")
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

