import argparse
import os
import glob
import sys
import json
import random
from collections import OrderedDict


def main(args):
    import glob, os
    pwd = os.getcwd()
    os.chdir(args.input)
    config_file =  random.choice(glob.glob("*.config"))

    with open(config_file, "r") as f:
        conf = json.load(f,
                         encoding="UTF-8",
                         object_pairs_hook=OrderedDict)

    os.chdir(pwd)
    conf = conf['recommendation']
    with open(args.config, "r+") as postgresqlconf:
        lines = postgresqlconf.readlines()
        settings_idx = lines.index("# Add tunable settings here\n")
        postgresqlconf.seek(0)
        postgresqlconf.truncate(0)

        lines = lines[0:(settings_idx + 1)]
        for line in lines:
            postgresqlconf.write(line)

        for (knob_name, knob_value) in list(conf.items()):
            postgresqlconf.write(str(knob_name) + " = " + str(knob_value) + "\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='EXTRACT PLANS ',
                                     epilog='',
                                     prog='')
    parser.add_argument("-i", "--input", required=True,
                        help="Directory with config files")
    parser.add_argument("-conf","--config", required=False, default="/etc/postgresql/10/main/postgresql.conf",
            help="PostgreSQL config file name")
    args = parser.parse_args()
    main(args)
