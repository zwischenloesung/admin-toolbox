#!/usr/bin/env python3

# usage: interactive mode - or short cut:
#
# echo "WittBoy_GW2000A
# 0000
#    humidityin %RH float
#    baromrelin hPa float" | ./$0
#

import os
import sys
import uuid
import yaml
import json
import re

from units_registry_loader import get_units_registry

# Prepare tiny global singleton helper copy
ucum_registry = None

# Define a new Class to be represented and ..
class Quoted(str): pass
#a global function to mark resp. strings
def q(s): return Quoted(str(s))


class SourceType():
    # Configurable indent prefix
    LEADING_SPACES = "    "  # 4 spaces

    # Some defaults
    DEFAULT_SUPER_TYPE = "CombinedSensor"
    DEFAULT_SUB_TYPE = "Sensor"

    def __init__(self):
        self.uuid = None
        self.name = None
        self.classname = None
        self.devicetype = None
        self.datatype = None
        self.dataunit = None
        self.dataunitencoding = 'meta:quantity_kind'
        self.meta = {
            'uncertainty': None,
            'quantity_kind': None,
            'displayname': {
                'en': ""
            },
            'tooltip': {
                'en': ""
            },
        }

    def auto_fill(self):
        if not self.uuid:
            self.uuid = str(uuid.uuid4())

    def serialize_parameters(self):
        self.auto_fill()
        o = {
            "name": self.name,
            "uuid": self.uuid,
            "classname": self.classname,
            "devicetype": self.devicetype,
            "type": self.datatype,
            "unit": self.dataunit,
            "unitencoding": self.dataunitencoding,
            "meta": self.meta,
        }
        return quote_textlike(o)



class Source():
    # Configurable indent prefix
    LEADING_SPACES = "      "  # 6 spaces

    def __init__(self, sourcetype: SourceType, parentsource=None):
        self.uuid = None
        self.name = None
        self.index = '0000'

        self.sourcetype = sourcetype
        self.parentsource = parentsource
        self.sub_sources = []

        self.meta = {
            'displayname': {
                'en': ""
            },
            'tooltip': {
                'en': ""
            },
        }

    def set_names(
        self,
        sourcetype_name,
        index=None,
        disable_index=False,
        classname=None,
        devicetype=None,
    ):
        sourcetype_name = slugify(sourcetype_name)
        self.sourcetype.name = sourcetype_name
        if disable_index == True:
            self.index = None
            self.name = sourcetype_name
        elif not index and not self.index:
            self.name = sourcetype_name
        elif not index:
            self.name = sourcetype_name + "_" + self.index
        else:
            self.index = index
            self.name = sourcetype_name + "_" + index

        self.sourcetype.classname = classname or SourceType.DEFAULT_SUPER_TYPE

        self.sourcetype.devicetype = devicetype or sourcetype_name


    def set_displaynames(
        self,
        disable_displaynames=False,
        sourcetype_displayname=None,
        source_displayname=None,
        sourcetype_tooltip=None,
        source_tooltip=None,
        lang="en",
    ):
        if disable_displaynames:
            self.meta["displayname"] = { lang: "" }
            self.sourcetype.meta["displayname"] = { lang: "" }
            self.meta["tooltip"] = { lang: "" }
            self.sourcetype.meta["tooltip"] = { lang: "" }
        else:
            if sourcetype_displayname:
                self.sourcetype.meta["displayname"] = {
                    lang: sourcetype_displayname
                }
            if source_displayname:
                self.meta["displayname"] = {
                    lang: source_displayname
                }
            if sourcetype_tooltip:
                self.sourcetype.meta["tooltip"] = {
                    lang: sourcetype_tooltip
                }
            if source_tooltip:
                self.meta["tooltip"] = {
                    lang: source_tooltip
                }


    def parturate(self):
        s = Source(SourceType(), self)
        self.sub_sources.append(s)
        return s

    def adopt(self, childsource):
        self.sub_sources.append(childsource)
        childsource.parentsource = self

    def auto_fill(self):
        if not self.uuid:
            self.uuid = str(uuid.uuid4())
        if not self.sourcetype:
            raise Exception(f"ERROR: Source without SourceType: {self.uuid}")
        else:
            self.sourcetype.auto_fill()
        # NOT handling self.parentsource.uuid, see serialize_deep(..)

    def serialize_parameters(self):
        self.auto_fill()
        o = {
            "name": self.name,
            "uuid": self.uuid,
            "typeuuid": self.sourcetype.uuid if self.sourcetype else None,
            "parentuuid": self.parentsource.uuid if self.parentsource else None,
            "parentname": self.parentsource.name if self.parentsource else None,
            "meta": self.meta,
        }
        return quote_textlike(o)

    def serialize_deep(self, container=None, depth=None):
        if depth == None:
            pass
        elif depth > 0:
            depth -= 1
        else:
            return container

        if not container:
            container = {
                "sources": {},
                "sourcetypes": {},
            }

        if (
            "sources" not in container or
            "sourcetypes" not in container
        ):
            raise Exception("Container corrupt.")

        if self.uuid in container["sources"]:
            print("WARNING: Duplicate Source entry found, last one takes precedence: {self.uuid}")
        container["sources"][self.uuid] = self.serialize_parameters()
        if not self.sourcetype.uuid in container["sourcetypes"]:
            container["sourcetypes"][self.sourcetype.uuid] = self.sourcetype.serialize_parameters()

        for s in self.sub_sources:
            s.serialize_deep(container, depth)
        return container



def slugify(name: str) -> str:
    return re.sub(r"[^A-Za-z0-9_-]", "_", name.strip().replace(" ", "_"))

def search_ucum(query, type_query=None, limit=8):
    while True:
        q = ucum_registry.lookup_quantity_kinds(query=query, limit=limit)
        if len(q) < 1:
            q = ucum_registry.lookup_quantity_kinds(query=type_query, limit=limit)

        u = 0 ; i = 0
        if len(q) > 0:
            print("  One of the following quantity-kinds:units could match:")
            for key, score in q:
                qk = ucum_registry.quantity_kinds[key]
                print(
                    f"    {i}: {key} {qk.label} [{qk.symbol}] (unit={qk.default_unit}) " +
                    f"score={score}"
                )
                i += 1
            r = input(f"Enter the index that fits best (or new search terms: ").strip()
            try:
                j = int(r)
                if j > len(q):
                    print(
                        f"There are only {len(q)} number of items to choose from... " +
                        "Please try again."
                    )
                else:
                    qk = ucum_registry.quantity_kinds[q[j][0]]
                    return qk.__dict__
            except Exception as e:
                print(e)
                query = r
        else:
            query = input("No results found, please add new search terms: ").strip()


# TODO parse_stdin() supports far less features than parse_interactive()..
def parse_stdin():
    """Parse lines of form:
       CombinedSensorName
       Index
          subname unit [type]
    """
    the_source = Source()
    lines = [l.rstrip() for l in sys.stdin if l.strip()]
    if not lines:
        return None
    the_source.sourcetype.name = slugify(lines[0])
    the_source.index = lines[1].strip() if len(lines) > 1 else the_source.index
    for line in lines[2:]:
        parts = line.strip().split(None, 3)
        if not parts:
            continue
        sub_source = the_source.parturate()
        sub_source.name = slugify(parts[0])
        sub_source.sourcetype.dateunit = parts[1].strip() if len(parts) > 1 else ""
        sub_source.sourcetype.datatype = parts[2].strip() if len(parts) > 2 else "float"
    return the_source

def parse_interactive():

    print()
    print("################################################################################")
    name = input(
        f"Enter {SourceType.DEFAULT_SUPER_TYPE} type name (empty to finish): "
    ).strip()
    if not name:
        return None

    # still here?
    the_source = Source(SourceType())

    disable_index = False
    index = input(
        f"Enter the source index ('-' to skip, [{the_source.index}]): "
    ).strip()
    if index == "-":
        index = ""
        disable_index = True
    devtype = input(
        "Enter device-type (empty means autogenerate): "
    ).strip()
    the_source.set_names(
        name,
        index,
        disable_index,
        SourceType.DEFAULT_SUPER_TYPE,
        devtype,
    )

    typedispln = input(
        "Enter type display name (empty to skip all display names): "
    ).strip()
    if typedispln:
        disable_dn = False
        if the_source.index:
            tmp = f"{typedispln} {the_source.index}"
        tmpi = input(
            f"Enter source display name ([{tmp}]): "
        ).strip()
        srcdispln = tmpi if tmpi else tmp
        typettip = input(
            "Enter tooltip for sourcetype (empty to skip []): "
        )
        srcttip = input(
            f"Enter tooltip for source ([{typettip}]): "
        ) or typettip
    else:
        disable_dn = True
        typedispln = None
        srcdispln = None
        typettip = None
        srcttip = None
    the_source.set_displaynames(
        disable_dn,
        typedispln,
        srcdispln,
        typettip,
        srcttip,
        lang="en",
    )

    tmpuuid = str(uuid.uuid4())
    the_source.sourcetype.uuid = input(
        f"Enter sourcetype UUID (['{tmpuuid}']): "
    ).strip() or tmpuuid
    tmpuuid = str(uuid.uuid4())
    the_source.uuid = input(
        f"Enter source UUID (['{tmpuuid}']): "
    ).strip() or tmpuuid

    subcount = 0
    while True:
        print("")
        print(f"========================= {name}::{subcount} =============================")
        sub_name = input(
            f"Enter sub-sensor name (empty to end this {SourceType.DEFAULT_SUPER_TYPE}): "
        ).strip()
        if not sub_name:
            break

        # still here?
#        the_child = the_source.parturate()
        the_child = Source(SourceType())

        # names
        sub_index = input(
            f"Enter the sub-sensor index (['']) "
        ).strip()
        sub_dis_index = False if sub_index else True
        sub_class = input(
            f"Enter a class name (['{SourceType.DEFAULT_SUB_TYPE}']): "
        ).strip() or SourceType.DEFAULT_SUB_TYPE
        sub_dev_type = input(
            "Enter device-type (empty means autogenerate): "
        ).strip()

        the_child.set_names(
            sub_name, sub_index, sub_dis_index, sub_class, sub_dev_type
        )

        #TODO repeat for all languages
        if not disable_dn:
            sub_tdisplname = input(
                f"Enter sourcetype display name ([{sub_name}] if empty): "
            ).strip() or sub_name
            if sub_index:
                i = f"{sub_tdisplname} {sub_index}"
            elif the_source.index:
                i = f"{sub_tdisplname} {the_source.index}"
            else:
                type_displname
            sub_sdisplname = input(
                f"Enter source display name ([{i}]): "
            ).strip() or i
            sub_tttip = input(
                "Enter sourcetype tooltip ([]): "
            )
            sub_sttip = input(
                f"Enter source tooltip ([{sub_tttip}]): "
            )
            the_child.set_displaynames(
                False,
                sub_tdisplname,
                sub_sdisplname,
                sub_tttip,
                sub_sttip,
                "en"
            )
        else:
            sub_tdisplname = None
            sub_sdisplname = None
            the_child.set_displaynames(disable_displaynames=True)


        print("---")
        tmpuuid = str(uuid.uuid4())
        sub_type_uuid = input(
            f"Enter sourcetype UUID (['{tmpuuid}']): "
        ).strip()
        tmpuuid = str(uuid.uuid4())
        sub_source_uuid = input(
            f"Enter source UUID (['{tmpuuid}']): "
        ).strip()

        print("---")
        if ucum_registry:
            qk = search_ucum(sub_name, sub_dev_type)
            the_child.sourcetype.dataunit = qk["default_unit"]
            the_child.sourcetype.meta["quantity_kind"] = qk
            the_child.sourcetype.meta["uncertainty"] = {}
        else:
            the_child.sourcetype.dataunit = input(
                f"Enter unit for '{sub_name}' ['m']: "
            ).strip()

        print("---")
        the_child.sourcetype.datatype = input(
            f"Enter type for '{sub_name}' (default float): "
        ).strip() or "float"

        print("---")
        for k, v in parse_meta().items():
            the_child.meta[k] = v
        print()
        print("=== SourceType ===")
        print(yaml.dump(
            the_child.sourcetype.serialize_parameters(),
            sort_keys=False,
            default_flow_style=False,
            allow_unicode=True,
            width=80,
        ))
        print("=== Source ===")
        print(yaml.dump(
            the_child.serialize_parameters(),
            sort_keys=False,
            default_flow_style=False,
            allow_unicode=True,
            width=80,
        ))
        print("===")
        skipit = input("Please confirm the entry (parent is set automatically [Y/n]): ").strip()
        if not skipit.lower() == "n":
            the_source.adopt(the_child)
            subcount += 1
    return the_source


def parse_meta(level=0):
    meta = {}
    hasMeta = True
    while hasMeta:
        if not meta:
            m = input(
                f"Enter meta JSON Level{level} (empty to skip, a key or JSON): "
            ).strip()
        else:
            m = input(
                f"Enter meta JSON Level{level} (empty to skip or the next key): "
            ).strip()
        if not m:
            return meta
        elif m.startswith("{") or m.startswith("["):
            if not meta:
                try:
                    m = json.loads(m)
                except:
                    input("WARNING/ERROR: Unable to parse JSON, please try again..")
                return m
            else:
                input("WARNING/ERROR: JSON found but meta not empty, please try again..")
        else:
            v = input(
                f"Now enter the value for '{m}' or leave empty to add sub-dict: "
            ).strip()
            if v:
                meta[m] = v
            else:
                meta[m] = parse_meta(level + 1)
    return meta

# limitting depth is not really needed, but might be interesting later for non-interactive
def quote_textlike(obj, depth=None):
    # stop and return None if obj is empty
    if not obj:
        return None

    # stop descending if depth is a non-None or negative
    if depth is not None and depth < 0:
        return obj

    # dict: descend into values
    if isinstance(obj, dict):
        if depth == 0:
            return {k: q(v) if isinstance(v, str) else v for k, v in obj.items()}
        next_depth = None if depth is None else depth - 1
        return {k: quote_textlike(v, next_depth) for k, v in obj.items()}

    # list/tuple: same logic
    if isinstance(obj, (list, tuple)):
        if depth == 0:
            return [q(v) if isinstance(v, str) else v for v in obj]
        next_depth = None if depth is None else depth - 1
        seq = [quote_textlike(v, next_depth) for v in obj]
        return type(obj)(seq)

    # leaf: quote strings, leave everything else
    if isinstance(obj, str):
        return q(obj)
    return obj


# TODO quoting

#           tmp["meta"] = quote_textlike(sub_source_meta)
#        tmp = {
#            "uuid": q(st_uuid),
#            "name": q(f"{combined_name}-{sub_name}"),
#            "class": q(sub_class),
#            "devicetype": q(dt),
#            "type": stype,  # bare literal
#            "unit": q(unit),
#            "unitencoding": q("meta:quantity_kind")
#        }


def main():

    if not sys.stdin.isatty():
        parse = parse_stdin
    else:
        p = os.path.dirname(os.path.realpath(__file__)) + '/maestro-basin-source-gen.ucum.yaml'
        pi = input(f"Enter path to units/meta file ([{p}]): ").strip()
        p = pi if pi else p
        global ucum_registry
        ucum_registry = get_units_registry()

        parse = parse_interactive

    sensor_libs = []

    # quote stringlike
    def quoted_representer(dumper, data):
        return dumper.represent_scalar("tag:yaml.org,2002:str", data, style="'")
    yaml.add_representer(Quoted, quoted_representer)

    do_continue = True
    while do_continue:
        a_source = parse()
        if not a_source:
            do_continue = False
        else:
            sensor_libs.append(a_source)

    # from here on, replace `None` resp. `null` with ``
    def none_representer(dumper, _):
        return dumper.represent_scalar('tag:yaml.org,2002:null', '', style=None)
    yaml.add_representer(type(None), none_representer)

    container = {
        "sources": {},
        "sourcetypes": {},
    }

    for l in sensor_libs:
        l.serialize_deep(container)

    if "sources" in container and "sourcetypes" in container:

        print("\n--- YAML output for 'Sources' ---")
        source_yaml = yaml.dump(
            list(container["sources"].values()),
            sort_keys=False,
            default_flow_style=False,
            allow_unicode=True,
            width=80,
        )
        print("".join(Source.LEADING_SPACES + line for line in source_yaml.splitlines(True)))
        print("\n--- YAML output for 'SourceTypes' ---")
        sourcetypes_yaml = yaml.dump(
            list(container["sourcetypes"].values()),
            sort_keys=False,
            default_flow_style=False,
            allow_unicode=True,
            width=80,
        )
        print(
            "".join(SourceType.LEADING_SPACES +
            line for line in sourcetypes_yaml.splitlines(True))
        )


if __name__ == "__main__":
    main()

