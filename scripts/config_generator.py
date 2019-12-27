#
# OtterTune - lhs.py
#
# Copyright (c) 2017-18, Carnegie Mellon University Database Group
#

import sys
import json
import os
import numpy as np
from pyDOE import lhs
from scipy.stats import uniform
from hurry.filesize import size


BYTES_SYSTEM = [
    (1024 ** 5, 'PB'),
    (1024 ** 4, 'TB'),
    (1024 ** 3, 'GB'),
    (1024 ** 2, 'MB'),
    (1024 ** 1, 'kB'),
    (1024 ** 0, 'B'),
]

TIME_SYSTEM = [
    (1000 * 60 * 60 * 24, 'd'),
    (1000 * 60 * 60, 'h'),
    (1000 * 60, 'min'),
    (1000, 's'),
    (1, 'ms'),
]


def get_raw_size(value, system):
    for factor, suffix in system:
        if value.endswith(suffix):
            if len(value) == len(suffix):
                amount = 1
            else:
                try:
                    amount = int(value[:-len(suffix)])
                except ValueError:
                    continue
            return amount * factor
    return None


def get_knob_raw(value, knob_type):
    if knob_type == 'integer':
        return int(value)
    elif knob_type == 'float':
        return float(value)
    elif knob_type == 'bytes':
        return get_raw_size(value, BYTES_SYSTEM)
    elif knob_type == 'time':
        return get_raw_size(value, TIME_SYSTEM)
    else:
        raise Exception('Knob Type does not support')


def get_knob_readable(value, knob_type):
    if knob_type == 'integer':
        return int(round(value))
    elif knob_type == 'float':
        return float(value)
    elif knob_type == 'bytes':
        value = int(round(value))
        return size(value, system=BYTES_SYSTEM)
    elif knob_type == 'time':
        value = int(round(value))
        return size(value, system=TIME_SYSTEM)
    else:
        raise Exception('Knob Type does not support')


def get_knobs_readable(values, types):
    result = []
    for i, value in enumerate(values):
        result.append(get_knob_readable(value, types[i]))
    return result


def main(args):
    knob_path = args.input
    save_path = args.output
    with open(knob_path, "r") as f:
        tuning_knobs = json.load(f)

    names = []
    maxvals = []
    minvals = []
    types = []

    for knob in tuning_knobs:
        names.append(knob['name'])
        maxvals.append(get_knob_raw(knob['tuning_range']['maxval'], knob['type']))
        minvals.append(get_knob_raw(knob['tuning_range']['minval'], knob['type']))
        types.append(knob['type'])

    nsamples = int(args.n)
    nfeats = len(tuning_knobs)
    samples = lhs(nfeats, samples=nsamples, criterion='maximin')
    maxvals = np.array(maxvals)
    minvals = np.array(minvals)
    scales = maxvals - minvals
    for fidx in range(nfeats):
        samples[:, fidx] = uniform(loc=minvals[fidx], scale=scales[fidx]).ppf(samples[:, fidx])

    samples_readable = []
    for sample in samples:
        samples_readable.append(get_knobs_readable(sample, types))

    config = {'recommendation': {}}
    for sidx in range(nsamples):
        for fidx in range(nfeats):
            config["recommendation"][names[fidx]] = samples_readable[sidx][fidx]
        with open(os.path.join(save_path, 'config_' + str(sidx) + ".config"), 'w+') as f:
            f.write(json.dumps(config))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Generate configs',
                                     epilog='',
                                     prog='"Usage: python config_generator.py -n [Samples Count] -i [Knob Path] -o [Save Path]')
    parser.add_argument("-i", "--input", required=True,
                        help="Input knobs json file")
    parser.add_argument("-o", "--output", required=True,
                    help="Input knobs json file")
    parser.add_argument("-n", "--n", type=int, default=1000,
                    help="number of config to generate")

    args = parser.parse_args()
    main(args)
