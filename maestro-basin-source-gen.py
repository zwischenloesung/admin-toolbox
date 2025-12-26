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

# some font tweaks
def supports_color():
    return os.isatty(sys.stdout.fileno())
COLOR_RESET = "\033[0m" if supports_color() else ""
COLOR_WHITE_BOLD = "\033[1;39m" if supports_color() else ""
#COLOR_GREEN = "\033[32m" if supports_color() else ""
COLOR_GREEN_BOLD = "\033[1;32m" if supports_color() else ""
COLOR_YELLOW = "\033[33m" if supports_color() else ""
COLOR_YELLOW_BOLD = "\033[1;33m" if supports_color() else ""
#COLOR_RED = "\033[31m" if supports_color() else ""
COLOR_RED_BOLD = "\033[1;31m" if supports_color() else ""
COLOR_CYAN = "\033[36m" if supports_color() else ""
COLOR_CYAN_BOLD = "\033[1;36m" if supports_color() else ""
COLOR_MAGENTA = "\033[35m" if supports_color() else ""
COLOR_MAGENTA_BOLD = "\033[1;35m" if supports_color() else ""

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
                'short': {
                    'en': ""
                },
                'long': {
                    'en': ""
                }
            },
            'description': {
                'short': {
                    'en': ""
                },
                'long': {
                    'en': ""
                }
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
    LEADING_SPACES = "        "  # 8 spaces

    def __init__(self, sourcetype: SourceType, parentsource=None):
        self.uuid = None
        self.name = None
        self.index = '0000'

        self.sourcetype = sourcetype
        self.parentsource = parentsource
        self.sub_sources = []

        self.meta = {
            'displayname': {
                'short': {
                    'en': ""
                },
                'long': {
                    'en': ""
                }
            },
            'description': {
                'short': {
                    'en': ""
                },
                'long': {
                    'en': ""
                }
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
        sourcetype_displaynameshort=None,
        sourcetype_displaynamelong=None,
        source_displaynameshort=None,
        source_displaynamelong=None,
        sourcetype_descriptionshort=None,
        sourcetype_descriptionlong=None,
        source_descriptionshort=None,
        source_descriptionlong=None,
        lang="en",
    ):
        if disable_displaynames:
            self.meta["displayname"] = {
                'short': {
                    lang: ""
                }, 'long': {
                    lang: ""
                }
            }
            self.sourcetype.meta["displayname"] = {
                'short': {
                    lang: ""
                }, 'long': {
                    lang: ""
                }
            }
            self.meta["description"] = {
                'short': {
                    lang: ""
                }, 'long': {
                    lang: ""
                }
            }
            self.sourcetype.meta["description"] = {
                'short': {
                    lang: ""
                }, 'long': {
                    lang: ""
                }
            }
        else:
            if sourcetype_displaynameshort:
                self.sourcetype.meta["displayname"]["short"][lang] = \
                    sourcetype_displaynameshort
            if sourcetype_displaynamelong:
                self.sourcetype.meta["displayname"]["long"][lang] = \
                    sourcetype_displaynamelong
            if source_displaynameshort:
                self.meta["displayname"]["short"][lang] = source_displaynameshort
            if source_displaynamelong:
                self.meta["displayname"]["long"][lang] = source_displaynamelong
            if sourcetype_descriptionshort:
                self.sourcetype.meta["description"]["short"][lang] = sourcetype_descriptionshort
            if sourcetype_descriptionlong:
                self.sourcetype.meta["description"]["long"][lang] = sourcetype_descriptionlong
            if source_descriptionshort:
                self.meta["description"]["short"][lang] = source_descriptionshort
            if source_descriptionlong:
                self.meta["description"]["long"][lang] = source_descriptionlong


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
    print(
        "########################" + \
        f"{COLOR_MAGENTA_BOLD} New {SourceType.DEFAULT_SUPER_TYPE} " + \
        f"{COLOR_RESET}########################"
    )
    name = input(
        f"Enter {SourceType.DEFAULT_SUPER_TYPE} type {COLOR_CYAN}" + \
        f"name{COLOR_RESET} (empty to finish): "
    ).strip()
    if not name:
        return None

    # still here?
    the_source = Source(SourceType())

    disable_index = False
    index = input(
        f"Enter the source {COLOR_CYAN}index{COLOR_RESET}" + \
        f"('-' to skip, [{the_source.index}]): "
    ).strip()
    if index == "-":
        index = ""
        disable_index = True
    devtype = input(
        f"Enter {COLOR_CYAN}device-type{COLOR_RESET} " + \
        "(empty means autogenerate): "
    ).strip()
    the_source.set_names(
        name,
        index,
        disable_index,
        SourceType.DEFAULT_SUPER_TYPE,
        devtype,
    )

    print(f"--- {COLOR_CYAN}Display Names{COLOR_RESET} ---")
    dlangs = []
    tdlangs = input(
        "Enter the languages you plan to support " + \
        "(separated by ';', empty to skip all display names): "
    ).split(";")
    for l in tdlangs: # Needed more than once
        dlangs.append(l.strip())
    for l in dlangs:
        disable_dn = False
        print(
            f"_Language:_{COLOR_YELLOW_BOLD}{l}{COLOR_RESET}_"
        )
        typedisplns = input(
            f"Enter short sourcetype display name: "
        ).strip()
        typedisplnl = input(
            f"Enter long sourcetype display name: "
        ).strip()
        if the_source.index:
            tmps = f"{typedisplns} {the_source.index}"
            tmpl = f"{typedisplnl} {the_source.index}"
        tmpi = input(
            f"Enter source display name ([{tmps}]): "
        ).strip()
        srcdisplns = tmpi if tmpi else tmps
        tmpi = input(
            f"Enter source display name ([{tmpl}]): "
        ).strip()
        srcdisplnl = tmpi if tmpi else tmpl
        typettips = input(
            "Enter short description for sourcetype (empty to skip []): "
        )
        typettipl = input(
            "Enter long description for sourcetype (empty to skip []): "
        )
        srcttips = input(
            f"Enter short description for source ([{typettips}]): "
        ) or typettips
        srcttipl = input(
            f"Enter long description for source ([{typettipl}]): "
        ) or typettipl
        the_source.set_displaynames(
            disable_dn,
            typedisplns,
            typedisplnl,
            srcdisplns,
            srcdisplnl,
            typettips,
            typettipl,
            srcttips,
            srcttipl,
            lang=l,
        )

    print(f"--- {COLOR_CYAN}UUID{COLOR_RESET} ---")
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
        print(
            f"======================= {COLOR_MAGENTA}{name}::{subcount} " + \
            f"{COLOR_RESET}===========================")
        sub_name = input(
            f"Enter sub-sensor {COLOR_CYAN}name{COLOR_RESET} " + \
            f"(empty to end this {SourceType.DEFAULT_SUPER_TYPE}): "
        ).strip()
        if not sub_name:
            break

        # still here?
#        the_child = the_source.parturate()
        the_child = Source(SourceType())

        # names
        sub_index = input(
            f"Enter the sub-sensor {COLOR_CYAN}index{COLOR_RESET} (['']) "
        ).strip()
        sub_dis_index = False if sub_index else True
        sub_class = input(
            f"Enter a {COLOR_CYAN}class name{COLOR_RESET} " + \
            f"(['{SourceType.DEFAULT_SUB_TYPE}']): "
        ).strip() or SourceType.DEFAULT_SUB_TYPE
        sub_dev_type = input(
            f"Enter {COLOR_CYAN}device-type{COLOR_RESET} " + \
            "(empty means autogenerate): "
        ).strip()

        the_child.set_names(
            sub_name, sub_index, sub_dis_index, sub_class, sub_dev_type
        )

        for l in dlangs:
            print(
                f"--- {COLOR_CYAN}Display Names " + \
                f"{COLOR_YELLOW_BOLD}{l}{COLOR_RESET} ---"
            )
            sub_tdisplnames = input(
                f"Enter short sourcetype display name ([{sub_name}] if empty): "
            ).strip() or sub_name
            sub_tdisplnamel = input(
                f"Enter long sourcetype display name ([{sub_name}] if empty): "
            ).strip() or sub_name
            if sub_index:
                ishort = f"{sub_tdisplnames} {sub_index}"
                ilong = f"{sub_tdisplnamel} {sub_index}"
            elif the_source.index:
                ishort = f"{sub_tdisplnames} {the_source.index}"
                ilong = f"{sub_tdisplnamel} {the_source.index}"
            else:
                ishort = sub_tdisplnames
                ilong = sub_tdisplnamel
            sub_sdisplnames = input(
                f"Enter short source display name ([{ishort}]): "
            ).strip() or ishort
            sub_sdisplnamel = input(
                f"Enter long source display name ([{ilong}]): "
            ).strip() or ilong
            sub_tttips = input(
                "Enter short sourcetype description ([]): "
            )
            sub_tttipl = input(
                "Enter long sourcetype description ([]): "
            )
            sub_sttips = input(
                f"Enter short source description ([{sub_tttips}]): "
            ) or sub_tttips
            sub_sttipl = input(
                f"Enter long source description ([{sub_tttipl}]): "
            ) or sub_tttipl
            the_child.set_displaynames(
                False,
                sub_tdisplnames,
                sub_tdisplnamel,
                sub_sdisplnames,
                sub_sdisplnamel,
                sub_tttips,
                sub_tttipl,
                sub_sttips,
                sub_sttipl,
                l
            )

        print(
            f"--- {COLOR_CYAN}UUID{COLOR_RESET} ---"
        )
        tmpuuid = str(uuid.uuid4())
        sub_type_uuid = input(
            f"Enter sourcetype UUID (['{tmpuuid}']): "
        ).strip()
        tmpuuid = str(uuid.uuid4())
        sub_source_uuid = input(
            f"Enter source UUID (['{tmpuuid}']): "
        ).strip()

        print(f"--- {COLOR_CYAN}Unit{COLOR_RESET} ---")
        if ucum_registry:
            qk = search_ucum(sub_name, sub_dev_type)
            the_child.sourcetype.dataunit = qk["default_unit"]
            the_child.sourcetype.meta["quantity_kind"] = qk
            the_child.sourcetype.meta["uncertainty"] = {}
        else:
            the_child.sourcetype.dataunit = input(
                f"Enter {COLOR_CYAN}unit{COLOR_RESET} for '{sub_name}' ['m']: "
            ).strip()

        print(f"--- {COLOR_CYAN}Type{COLOR_RESET} ---")
        the_child.sourcetype.datatype = input(
            f"Enter type for '{sub_name}' (default float): "
        ).strip() or "float"

        print(f"--- {COLOR_CYAN}Meta{COLOR_RESET} ---")
        for k, v in parse_meta().items():
            the_child.meta[k] = v
        print()
        print(f"=== {COLOR_MAGENTA}SourceType{COLOR_RESET} ===")
        print(yaml.dump(
            the_child.sourcetype.serialize_parameters(),
            sort_keys=False,
            default_flow_style=False,
            allow_unicode=True,
            width=80,
        ))
        print(f"=== {COLOR_MAGENTA}Source{COLOR_RESET} ===")
        print(yaml.dump(
            the_child.serialize_parameters(),
            sort_keys=False,
            default_flow_style=False,
            allow_unicode=True,
            width=80,
        ))
        print("=== --- ===")
        skipit = input(
            f"{COLOR_CYAN_BOLD}Please confirm the entry{COLOR_RESET} " + \
            f"(parent is set automatically [Y/n]): "
        ).strip()
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
                f"Enter {COLOR_WHITE_BOLD}meta JSON Level{level}" + \
                f"{COLOR_RESET} (empty to skip, a " + \
                f"{COLOR_CYAN}key{COLOR_RESET} or JSON): "
            ).strip()
        else:
            m = input(
                f"Enter {COLOR_WHITE_BOLD}meta JSON Level{level}" + \
                f"{COLOR_RESET} (empty to skip or the next " + \
                f"{COLOR_CYAN}key{COLOR_RESET}): "
            ).strip()
        if not m:
            return meta
        elif m.startswith("{") or m.startswith("["):
            if not meta:
                try:
                    m = json.loads(m)
                except:
                    input(
                        f"{COLOR_RED_BOLD}WARNING/ERROR: Unable to " + \
                        f"parse JSON, please try again..{COLOR_RESET}"
                    )
                return m
            else:
                input(
                    f"{COLOR_RED_BOLD}WARNING/ERROR: JSON found " + \
                    f"but meta not empty, please try again..{COLOR_RESET}"
                )
        else:
            v = input(
                f"Now enter the {COLOR_CYAN}value{COLOR_RESET} " + \
                f"for '{COLOR_WHITE_BOLD}{m}{COLOR_RESET}' or " + \
                f"leave empty to add {COLOR_CYAN}sub-dict{COLOR_RESET}: "
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
        print(
            "########################################" + \
            "########################################"
        )
        print(
            COLOR_GREEN_BOLD + \
            f"                             W e l c o m e !" + \
            COLOR_RESET
        )
        print(
            "########################################" + \
            "########################################"
        )
        p = os.path.dirname(os.path.realpath(__file__)) + \
            '/maestro-basin-source-gen.ucum.yaml'
        pi = input(
            "Enter path to " + COLOR_CYAN + \
            "units/meta " + COLOR_RESET + f"file ([{p}]): "
        ).strip()
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

        print(
            f"\n--- {COLOR_YELLOW}YAML output for " + \
            f"{COLOR_YELLOW_BOLD}'Sources'{COLOR_RESET} ---"
        )
        source_yaml = yaml.dump(
            list(container["sources"].values()),
            sort_keys=False,
            default_flow_style=False,
            allow_unicode=True,
            width=80,
        )
        print("".join(Source.LEADING_SPACES + line for line in source_yaml.splitlines(True)))
        print(
            f"\n--- {COLOR_YELLOW}YAML output for " + \
            f"{COLOR_YELLOW_BOLD}'SourceTypes'{COLOR_RESET} ---"
        )
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

