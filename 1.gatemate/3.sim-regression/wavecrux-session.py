#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Chili.CHIPS
#
# SPDX-License-Identifier: BSD-3-Clause
#
# Writes a WaveCrux session for an FST of a test bench (make waves): the rows
# of LAYOUTS below, bound to that file. A session binds by signal number in
# the file ("ref": the order in which the FST's signal handles first appear),
# and that number differs from one simulator to the next, so each FST gets
# its own session, made from the signal names.
#
#   wavecrux-session.py TEST_BENCH FST SESSION
#
# TEST_BENCH is tb_modes or tb_rules. The session names the FST by its file
# name: keep the two side by side. The view shows the whole run. Needs
# fst2vcd (GTKWave or the OSS CAD Suite) on PATH. Standard library only.
#
# Colours: TX orange, RX blue, clocks, resets and lock yellow.

import json
import os
import struct
import subprocess
import sys

TX, RX, CTL = 4294948685, 4283417591, 4294962776   # ARGB: #FFB74D, #4FC3F7, #FFF176


def rows(tb, ctl, tx, rx):
    return ([('%s.%s' % (tb, s), CTL) for s in ctl] + [('%s.%s' % (tb, s), TX) for s in tx]
            + [('%s.%s' % (tb, s), RX) for s in rx])


LAYOUTS = {
    # one BFM looped back (rxp = txp): the TX data and K flags, the line, the
    # recovered clock, the RX data and its 8b/10b and alignment flags
    'tb_modes': rows('tb_modes',
                     ['clk_ref', 'arst_n', 'rst_core_n', 'u_serdes.pll_locked', 'tx_ready'],
                     ['clk_tx', 'tx_d', 'tx_k', 'tx_err', 'txp'],
                     ['rxp', 'u_serdes.rx_cdr_locked', 'clk_rx', 'rx_d', 'rx_k', 'rx_aligned',
                      'rx_nit', 'rx_disp', 'rx_err', 'prbs_err', 'rx_ready']),
    # the rules at the ports: resets, power down, the line cut and resumed
    'tb_rules': rows('tb_rules',
                     ['clk_ref', 'arst_n', 'tx_rst', 'rx_rst', 'rx_pcs', 'txpd', 'rxpd',
                      'u_serdes.pll_locked', 'txdone'],
                     ['txd', 'txk', 'tx_err', 'tx_ei', 'txp'],
                     ['cut', 'rxp', 'u_serdes.rx_cdr_locked', 'clk_rxo', 'rxd', 'rxk', 'aligned',
                      'realign', 'prbs_err', 'ei_o', 'rxdone']),
}


def fst_refs(fst):
    """path -> ref: the number of the path's handle (its VCD id code), in the
    order the handles first appear. Reads the header only."""
    p = subprocess.Popen(['fst2vcd', fst], stdout=subprocess.PIPE, text=True, errors='replace')
    refs, handles, scope = {}, {}, []
    for line in p.stdout:
        w = line.split()
        if line.startswith('$enddefinitions'):
            break
        if line.startswith('$scope'):
            scope.append(w[2])
        elif line.startswith('$upscope'):
            scope.pop()
        elif line.startswith('$var'):
            h = handles.setdefault(w[3], str(len(handles)))
            refs.setdefault('.'.join(scope + [w[4]]), h)
    p.kill()
    p.wait()
    return refs


def fst_end_ticks(fst):
    """the FST's end time in WaveCrux ticks (100 fs), from its header block"""
    with open(fst, 'rb') as f:
        h = f.read(74)
    if len(h) < 74 or h[0] != 0:
        return 0
    end = struct.unpack('>Q', h[17:25])[0]
    exp = struct.unpack('b', h[73:74])[0]   # time unit, 10**exp s
    return end * 10 ** (exp + 13) if exp + 13 >= 0 else end // 10 ** -(exp + 13)


def main():
    if len(sys.argv) != 4 or sys.argv[1] not in LAYOUTS:
        sys.exit('usage: wavecrux-session.py tb_modes|tb_rules FST SESSION')
    name, fst, out = sys.argv[1:]
    sig = LAYOUTS[name]
    refs = fst_refs(fst)
    missing = sorted({p for p, _ in sig} - set(refs))
    if missing:
        sys.exit('wavecrux-session.py: not in %s: %s' % (fst, ', '.join(missing)))

    ticks = fst_end_ticks(fst)
    d = {
        'version': 4,
        'sourceFilePath': os.path.basename(fst),
        'signals': [{'kind': 'signal', 'id': 'bfm-%d' % i, 'ref': refs[p], 'path': p,
                     'name': p.rsplit('.', 1)[1], 'color': c, 'format': 'hexadecimal', 'height': 30.0}
                    for i, (p, c) in enumerate(sig)],
        'cursor': {'primary': None, 'secondary': None},
        'markers': {},
        'view': {'ticksPerPixel': float(max(ticks // 1300, 1)), 'panOffsetTicks': 0.0, 'scrollOffset': 0.0},
        'panels': {'signalTree': False, 'valueColumn': False, 'transactionView': False, 'stageView': False,
                   'statisticsStrip': False, 'cocotbLogPanel': False, 'rtlSource': False,
                   'sizes': {'left': 301.6, 'right': 150.0}},
        'signalTreeState': {'expanded': [], 'selected': [], 'scroll': 0.0},
        'translateFilters': {},
        'stage': {'panels': []},
        'activeTheme': 'wavecrux-dark',
        'decoders': [],
    }
    with open(out, 'w') as f:
        json.dump(d, f, indent=2)
        f.write('\n')
    print('%s: %d rows, for %s' % (out, len(sig), os.path.basename(fst)))


if __name__ == '__main__':
    main()

# -----------------------------------------------------------------------------
# Project:     openSERDES_BFM
# Description: open-source SerDes BFM
# -----------------------------------------------------------------------------
