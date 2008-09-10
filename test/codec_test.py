#!/usr/bin/env python
#
# Author: Martin Matusiak <numerodix@gmail.com>
# Licensed under the GNU Public License, version 3.
#
# A helper script to test undvd on a range of combinations of codecs and
# containers. Results are written to a report file.

import os
import subprocess
import sys
import time


# downscaled for quick testing
conts = ['mkv', 'mp4']
vcodecs = ['xvid', 'h264']
acodecs = ['mp3', 'aac',]

# definitely insane
conts = ['asf', 'au', 'avi', 'dv', 'flv', 'ipod', 'mkv', 'mov', 'mpg', 'mp4',
         'nut', 'ogm', 'rm', 'swf']
acodecs = ['aac', 'ac3', 'flac', 'mp2', 'mp3', 'sonic', 'sonicls', 'vorbis',
           'wmav1', 'wmav2']
vcodecs = ['asv1', 'asv2', 'dvvideo', 'ffv1', 'flv', 'h261', 'h263', 'h263p',
           'h264', 'mpeg1video', 'mpeg2video', 'mpeg4', 'msmpeg4', 'msmpeg4v2',
           'roqvideo', 'rv10', 'snow', 'svq1', 'wmv1', 'wmv2', 'xvid']

# sane?
conts = ['asf', 'avi', 'flv', 'mkv', 'mov', 'mp4', 'nut', 'ogm']
acodecs = ['aac', 'ac3', 'mp3', 'vorbis']
vcodecs = ['flv', 'h264', 'mpeg4', 'xvid']


workdir = "/tmp"

tool_name = os.path.basename(sys.argv[0])
logfile = os.path.join(workdir, tool_name + '.log')
if os.path.exists(logfile): os.unlink(logfile)


def write(s, ovr=False, end=False):
    line_len = 79
    s = s.ljust(line_len)
    if end:
        s += "\n"
    if ovr:
        s += "\r"
    sys.stdout.write(s)
    sys.stdout.flush()

def invoke(args):
    p = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    stdout = p.stdout.read()
    ret = p.wait()
    return (ret, stdout)

def check_tools():
    os.environ["TERM"] = ""
    (ret, stdout) = invoke(['undvd', '--version'])
    tools = {}
    tools['undvd'] = stdout.split('\n')[0].split()[1]
    for line in stdout.split('\n')[1:]:
        for t in ['mplayer', 'mencoder', 'mp4creator', 'mkvmerge', 'ogmmerge']:
            if t in line:
                if '[*] %s' % t in line:
                    tools[t] = line.split()[2]
                else:
                    tools[t] = None
    return tools

def run_test(source, title, cont, acodec, vcodec):
    args = ['undvd', '--end', '3'] + source
    args.extend(['--title', title, '--audio', 'en'])
    args.extend(['--cont', cont, '--vcodec', vcodec, '--acodec', acodec])

    os.environ["TERM"] = ''

    oldcwd = os.getcwd()
    os.chdir(workdir)

    pre = time.time()
    p = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    stdout = p.stdout.read()
    dur = time.time() - pre

    os.chdir(oldcwd)

    line = "%s\n%s%s\n\n" % (" ".join(args), stdout, "time: %s" % dur)
    open(logfile, 'a').write(line)

    if stdout.find('[ failed ]') > -1:
        return (False, dur)
    elif stdout.find('[ done ]') > -1:
        return (True, dur)
    else:
        return (None, dur)

def run_suite(source, title, cont, acodec, vcodec):
    matrix = [[[None for a in acodecs] for v in vcodecs] for c in conts]
    combs = len(conts) * len(acodecs) * len(vcodecs)

    cw = max([len(j) for j in conts])
    vw = max([len(j) for j in vcodecs])
    aw = max([len(j) for j in vcodecs])

    i = 1
    last_run = 0
    cum = 0
    for c in conts:
        for v in vcodecs:
            for a in acodecs:
                s = "%s%s%s" % (c.ljust(cw+3), v.ljust(vw+3), a.ljust(aw+3))

                cum_i = (int) (cum / 60)
                last_i = (int) (last_run)
                eta_i = (int) ((cum / i) * (combs - i) / 60)

                prog_s = "%s/%s" % (i, combs)
                last_s = "last: %ss" % last_i
                cum_s = "cum: %smin" % cum_i
                eta_s = "eta: %smin" % eta_i
                stat = "  ".join([last_s, cum_s, eta_s])
                write("%s   %s%s" % (s, prog_s.ljust(10), stat), ovr=True)

                (res, last_run) = run_test(source, title, c, a, v)
                cum += last_run

                res_s = "error"
                if res == True:
                    res_s = "ok"
                elif res == False:
                    res_s = "failed"
                write("%s   %s" % (s, res_s), end=True)

                matrix[conts.index(c)][vcodecs.index(v)][acodecs.index(a)] = res

                i += 1

    return (matrix, cum)

def get_report(matrix, cum, tools):
    s = "# Generated with %s (time: %smin)\n\n" % (tool_name, int(cum/60))

    s += "Tool versions:\n"
    ts = tools.items() ; ts.sort()
    for (k, v) in ts:
        if not v:
            v = "missing"
        s += "+ %s %s\n" % (k, v)
    s += "\n"

    w = max( max([len(i) for i in conts+vcodecs+acodecs]), 9)
    we = w + 2

    def bar():
        return "+%s+%s+%s+%s+\n" % ('-'*we, '-'*we, '-'*we, '-'*we)
    def td(c, v, a, val):
        return "| %s | %s | %s | %s |\n" %\
                (c.ljust(w), v.ljust(w), a.ljust(w), val.ljust(w))

    s += bar()
    s += td("container", "vcodec", "acodec", "status")
    s += bar()
    for c in conts:
        for v in vcodecs:
            for a in acodecs:
                val = matrix[conts.index(c)][vcodecs.index(v)][acodecs.index(a)]
                val_s = "ok"
                if not val:
                    val_s = "failed"
                s += td(c, v, a, val_s)
    s += bar()

    return s

def get_svg(matrix, cum, tools):
    def get_s(x, y, fpx, c, th=False, color=None):
        style = ""
        if th:
            style += " font-weight: bold;"
        if color:
            style += " fill: %s;" % color
        s = '\n<text x="%s" y="%s" style="font-size: %spx;%s">' %\
                (x, y, fpx, style)
        s += '\n%s' % c
        s += '\n</text>'
        return s


    margin = 20
    padding = 10

    fpx = 14
    fpl = 12
    fpa = 6

    x, y = margin, margin + (fpx + fpa)
    x_span = x

    s = ""

    # write footer
    header = "Container/codec test matrix"
    s += get_s(x, y, 20, header)
    y += (fpx + fpa) * 2
    x_span = max(x_span, x + (fpx-6) * len(header))


    # write table
    x += padding
    y += padding
    orig_x, orig_y = x, y

    cw = max([len(j) for j in conts])
    vw = max([len(j) for j in vcodecs])
    aw = max([len(j) for j in acodecs])

    for (j, v) in enumerate([None] + vcodecs):
        j -= 1

        row_height = 0
        for (i, c) in enumerate([None] + conts):
            i -= 1

            if i == -1 and j == -1:
                pass
                x += fpx * vw
            elif i > -1 and j == -1:
                s += get_s(x, y, fpx, conts[i], th=True)
                x += fpx * aw
            elif i == -1 and j > -1:
                s += get_s(x, y, fpx, vcodecs[j], th=True)
                x += fpx * vw
            else:
                local_y = y
                for a in acodecs:
                    val = matrix[conts.index(c)][vcodecs.index(v)][acodecs.index(a)]
                    if val:
                        s += get_s(x, local_y, fpx, a)
                        if acodecs.index(a) < len(acodecs) - 1:
                            local_y += fpx + fpa
                        else:
                            local_y += fpx + fpl
                        row_height = max(local_y, row_height)
                x += fpx * aw

        x_span = x
        x = orig_x
        y = max(y + (fpx + fpl), row_height)

    y += padding
    x -= padding

    # write tools
    y += (fpx + fpa) * 1
    s += get_s(x, y, fpx, "Tools available:")
    y += (fpx + fpa) * 1
    ts = tools.items(); ts.sort()
    for (k, v) in ts:
        color = "green"
        if not v:
            color = "red"
            v = "missing"
        s += get_s(x, y, fpx, "+ %s %s" % (k, v), color=color)
        y += fpx + fpa

    # write footer
    y += (fpx + fpa) * 1
    footer = "# Generated with %s (time: %smin)\n\n" % (tool_name, int(cum/60))
    s += get_s(x, y, fpx, footer)
    x_span = max(x_span, x + (fpx-6) * len(footer))


    w, h = x_span + margin, y + margin

    d = '<?xml version="1.0"?>'
    d += '\n<svg height="%s" width="%s" xmlns="http://www.w3.org/2000/svg">' % (h, w)
    d += '\n<rect x="0" y="0" height="%s" width="%s" fill="white"/>' % (h, w)
    d += s
    d += '\n</svg>'
    return d

def main(source, title, reportfile):
    tools = check_tools()

    if not tools.get("mp4creator") and 'mp4' in conts: conts.remove('mp4')
    if not tools.get("mkvmerge") and 'mkv' in conts: conts.remove('mkv')
    if not tools.get("ogmmerge") and 'ogm' in conts: conts.remove('ogm')

    (matrix, cum) = run_suite(source, title, conts, acodecs, vcodecs)

    report_s = get_report(matrix, cum, tools)
    open(reportfile + '.txt', 'w').write(report_s)

    svg_s = get_svg(matrix, cum, tools)
    open(reportfile + '.svg', 'w').write(svg_s)



if __name__ == "__main__":
    from optparse import OptionParser
    parser = OptionParser()
    parser.add_option("-o", "", dest="filename",
        help="write report to file", metavar="file")
    parser.add_option("-t", "", dest="title",
        help="title to rip", metavar="title")
    parser.add_option("-d", "--dev", dest="dev",
        help="dvd device to rip from", metavar="dev")
    parser.add_option("-q", "--dir", dest="dir",
        help="dvd directory to rip from", metavar="dir")
    parser.add_option("-i", "--iso", dest="iso",
        help="dvd iso image to rip from", metavar="iso")
    (opts, args) = parser.parse_args()

    source = []
    if opts.dev:
        source = ['--dev', os.path.abspath(opts.dev)]
    elif opts.dir:
        source = ['--dir', os.path.abspath(opts.dir)]
    elif opts.iso:
        source = ['--iso', os.path.abspath(opts.iso)]

    title = '1'
    if opts.title:
        title = opts.title

    if not opts.filename:
        write("No output file given", end=True)
        sys.exit(1)

    main(source, title, opts.filename)
