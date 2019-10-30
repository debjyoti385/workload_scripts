import sys
import argparse
import glob, os, sys, subprocess
import pickle,re
import json
import re
from enum import Enum


class ExplainType(Enum):
    text = 'text'
    json = 'json'
    parsed = 'parsed'

    def __str__(self):
        return self.value

def type_match(type_dict, key, default = None):
    types = sorted(type_dict.keys(), key=len, reverse=True)
    for t in types:
        if t.lower() in key.lower():
            return type_dict[t]['id']
    return default 



regex_dict = re.compile(r'''
    [[\S]*[\s]*]*[\S]+\s*:                 # a key (any word followed by a colon)
    (?:
    \s*                                    # then a space in between
    \d+\.*\d*\s+ | \s*(?!\S+\s*:)\S+       # then a value (any word not followed by a colon)
    )+                                     # match multiple values if present
    ''', re.VERBOSE)


def parse(text):
    try:
        return json.loads(text)
    except ValueError as e:
        #print('invalid json: %s' % e)
        return None # or: raise

def log_line_type(line):
    if line.startswith('    !'):
        return 0
    elif line.startswith('|'):
        if 'plan:' in  line:
            return 1
        else:
            return 0
    else:
        return 2


def extract_plans(args):
    filename = args.input
    if args.type == ExplainType.json:
        with open(filename, 'r') as logfile:
            buffer=""
            is_plan=False
            for line in logfile:
                line_type= log_line_type(line)
                if line_type == 1:
                    buffer =""
                    is_plan=True
                if line_type == 2 and is_plan:
                    buffer=buffer+line.strip()
                if line_type != 2 and len(buffer) > 1:
                    yield buffer
                    is_plan=False
    elif args.type == ExplainType.parsed:
        with open(filename, 'r') as logfile:
            for line in logfile:
                id, plan = line.split("\t",1)
                if not args.stats:
                    print( "#".ljust(80,"#") )
                    print( ("##### ID: " +  id + " ").ljust(80,"#") )
                yield plan
    return 

def main(args):
    for plan in extract_plans(args):
        json_plan = parse(plan)
        if json_plan:
            print(plan)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='EXTRACT PLANS ',
                                     epilog='',
                                     prog='')
    parser.add_argument("-i", "--input", required=True,
                        help="Input log file name")
    parser.add_argument("-type","--type", type=ExplainType, choices=list(ExplainType),  
            help="ExplainType {json, text, parsed}")
    args = parser.parse_args()
    main(args)
