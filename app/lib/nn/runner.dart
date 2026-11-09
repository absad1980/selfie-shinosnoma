import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

/// Our own small neural-network runner for the bundled .nnm models (made by tools/convert_tflite.py).
/// Pure Dart: no Google services, no native engine — works the same on every phone.
/// Tensors are NHWC float32, batch 1. Only the layers our three models use are implemented.
class NnModel {
  final List<List<int>> _shapes;
  final List<Float32List?> _const;
  final List<List<int>?> _ints;
  final List<Map<String, dynamic>> _ops;
  final List<int> inputs, outputs;
  final Map<int, Float32List> _prepared = {}; // re-ordered conv weights

  NnModel._(this._shapes, this._const, this._ints, this._ops, this.inputs, this.outputs);

  static Float32List? _halfTable;
  static Float32List _halves() {
    final t = Float32List(65536);
    for (var h = 0; h < 65536; h++) {
      final s = (h >> 15) & 1, e = (h >> 10) & 0x1f, f = h & 0x3ff;
      double v;
      if (e == 0) {
        v = f * math.pow(2, -24).toDouble();
      } else if (e == 31) {
        v = f == 0 ? double.infinity : double.nan;
      } else {
        v = (1 + f / 1024) * math.pow(2, e - 15).toDouble();
      }
      t[h] = s == 1 ? -v : v;
    }
    return t;
  }

  factory NnModel.load(Uint8List bytes) {
    final bd = ByteData.sublistView(bytes);
    if (String.fromCharCodes(bytes.sublist(0, 4)) != 'NNM1') throw const FormatException('not an NNM model');
    final jl = bd.getUint32(4, Endian.little);
    final j = jsonDecode(utf8.decode(bytes.sublist(8, 8 + jl))) as Map<String, dynamic>;
    var blob = 8 + jl;
    while (blob % 4 != 0) {
      blob++;
    }
    final half = _halfTable ??= _halves();
    final ts = (j['tensors'] as List).cast<Map<String, dynamic>>();
    final shapes = <List<int>>[], consts = <Float32List?>[], ints = <List<int>?>[];
    for (final t in ts) {
      final shape = (t['shape'] as List).cast<int>();
      shapes.add(shape);
      ints.add((t['ints'] as List?)?.cast<int>());
      final dt = t['dt'] as String?;
      if (dt == null) {
        consts.add(null);
        continue;
      }
      final n = shape.fold<int>(1, (a, b) => a * b);
      final off = blob + (t['off'] as int);
      final out = Float32List(n);
      if (dt == 'f32') {
        for (var i = 0; i < n; i++) {
          out[i] = bd.getFloat32(off + i * 4, Endian.little);
        }
      } else {
        for (var i = 0; i < n; i++) {
          out[i] = half[bd.getUint16(off + i * 2, Endian.little)];
        }
      }
      consts.add(out);
    }
    return NnModel._(shapes, consts, ints, (j['ops'] as List).cast<Map<String, dynamic>>(), (j['inputs'] as List).cast<int>(), (j['outputs'] as List).cast<int>());
  }

  List<int> shapeOf(int t) => _shapes[t];

  /// Runs the model on one input tensor; returns the output tensors in order.
  List<Float32List> run(Float32List input) {
    final v = List<Float32List?>.from(_const);
    v[inputs.first] = input;
    for (final op in _ops) {
      final ins = (op['in'] as List).cast<int>(), outT = (op['out'] as List).cast<int>().first;
      final a = v[ins.first]!;
      final os = _shapes[outT];
      Float32List r;
      switch (op['op'] as String) {
        case 'CONV_2D':
          r = _conv(a, _shapes[ins[0]], ins[1], v[ins[1]]!, ins.length > 2 ? v[ins[2]] : null, os, op);
        case 'DEPTHWISE_CONV_2D':
          r = _depthwise(a, _shapes[ins[0]], v[ins[1]]!, _shapes[ins[1]], ins.length > 2 ? v[ins[2]] : null, os, op);
        case 'TRANSPOSE_CONV_BIAS':
          r = _transposeConv(a, _shapes[ins[0]], v[ins[1]]!, _shapes[ins[1]], v[ins[2]]!, os, op);
        case 'MAX_POOL_2D':
          r = _pool(a, _shapes[ins[0]], os, op, true);
        case 'AVERAGE_POOL_2D':
          r = _pool(a, _shapes[ins[0]], os, op, false);
        case 'ADD':
          r = _binary(a, _shapes[ins[0]], v[ins[1]]!, _shapes[ins[1]], os, true, op['act'] as int? ?? 0);
        case 'MUL':
          r = _binary(a, _shapes[ins[0]], v[ins[1]]!, _shapes[ins[1]], os, false, op['act'] as int? ?? 0);
        case 'RELU':
          r = Float32List(a.length);
          for (var i = 0; i < a.length; i++) {
            r[i] = a[i] > 0 ? a[i] : 0;
          }
        case 'PRELU':
          final al = v[ins[1]]!, c = al.length;
          r = Float32List(a.length);
          for (var i = 0; i < a.length; i++) {
            final x = a[i];
            r[i] = x >= 0 ? x : x * al[i % c];
          }
        case 'HARD_SWISH':
          r = Float32List(a.length);
          for (var i = 0; i < a.length; i++) {
            final x = a[i];
            r[i] = x * (x + 3).clamp(0.0, 6.0) / 6;
          }
        case 'LOGISTIC':
          r = Float32List(a.length);
          for (var i = 0; i < a.length; i++) {
            r[i] = 1 / (1 + math.exp(-a[i]));
          }
        case 'PAD':
          r = _pad(a, _shapes[ins[0]], _ints[ins[1]]!, os);
        case 'RESHAPE':
          r = a;
        case 'CONCATENATION':
          r = _concat([for (final i in ins) v[i]!], [for (final i in ins) _shapes[i]], os, op['axis'] as int);
        case 'RESIZE_BILINEAR':
          r = _resize(a, _shapes[ins[0]], os, op['align'] == true, op['half'] == true);
        default:
          throw UnsupportedError('layer ${op['op']}');
      }
      v[outT] = r;
    }
    return [for (final o in outputs) v[o]!];
  }

  static double _act(double x, int act) {
    switch (act) {
      case 1:
        return x > 0 ? x : 0;
      case 2:
        return x.clamp(-1.0, 1.0);
      case 3:
        return x.clamp(0.0, 6.0);
      default:
        return x;
    }
  }

  /// SAME/VALID padding before the first row/column (builtin enum: 0 SAME, 1 VALID).
  static int _padBefore(bool same, int inSize, int outSize, int stride, int k, int dil) {
    if (!same) return 0;
    final eff = (k - 1) * dil + 1;
    return math.max((outSize - 1) * stride + eff - inSize, 0) ~/ 2;
  }

  Float32List _conv(Float32List a, List<int> ish, int wIdx, Float32List w, Float32List? bias, List<int> os, Map<String, dynamic> op) {
    final h = ish[1], wd = ish[2], c = ish[3];
    final oh = os[1], ow = os[2], o = os[3];
    final kh = _shapes[wIdx][1], kw = _shapes[wIdx][2];
    final sh = op['sh'] as int, sw = op['sw'] as int, dh = op['dh'] as int? ?? 1, dw = op['dw'] as int? ?? 1;
    final same = op['pad'] == 0, act = op['act'] as int? ?? 0;
    final pt = _padBefore(same, h, oh, sh, kh, dh), pl = _padBefore(same, wd, ow, sw, kw, dw);
    // weights [O,KH,KW,C] → [KH,KW,C,O] so the inner loop runs over output channels
    final wt = _prepared[wIdx] ??= () {
      final t = Float32List(w.length);
      for (var oc = 0; oc < o; oc++) {
        for (var k = 0; k < kh * kw * c; k++) {
          t[k * o + oc] = w[oc * kh * kw * c + k];
        }
      }
      return t;
    }();
    final out = Float32List(oh * ow * o);
    final acc = Float32List(o);
    for (var oy = 0; oy < oh; oy++) {
      for (var ox = 0; ox < ow; ox++) {
        if (bias != null) {
          for (var oc = 0; oc < o; oc++) {
            acc[oc] = bias[oc];
          }
        } else {
          acc.fillRange(0, o, 0);
        }
        for (var ky = 0; ky < kh; ky++) {
          final iy = oy * sh - pt + ky * dh;
          if (iy < 0 || iy >= h) continue;
          for (var kx = 0; kx < kw; kx++) {
            final ix = ox * sw - pl + kx * dw;
            if (ix < 0 || ix >= wd) continue;
            final ib = (iy * wd + ix) * c;
            final wb = (ky * kw + kx) * c * o;
            for (var ic = 0; ic < c; ic++) {
              final x = a[ib + ic];
              if (x == 0) continue;
              final wo = wb + ic * o;
              for (var oc = 0; oc < o; oc++) {
                acc[oc] += x * wt[wo + oc];
              }
            }
          }
        }
        final ob = (oy * ow + ox) * o;
        for (var oc = 0; oc < o; oc++) {
          out[ob + oc] = act == 0 ? acc[oc] : _act(acc[oc], act);
        }
      }
    }
    return out;
  }

  Float32List _depthwise(Float32List a, List<int> ish, Float32List w, List<int> wsh, Float32List? bias, List<int> os, Map<String, dynamic> op) {
    final h = ish[1], wd = ish[2], c = ish[3];
    final oh = os[1], ow = os[2], o = os[3];
    final kh = wsh[1], kw = wsh[2], mult = o ~/ c;
    final sh = op['sh'] as int, sw = op['sw'] as int, dh = op['dh'] as int? ?? 1, dw = op['dw'] as int? ?? 1;
    final same = op['pad'] == 0, act = op['act'] as int? ?? 0;
    final pt = _padBefore(same, h, oh, sh, kh, dh), pl = _padBefore(same, wd, ow, sw, kw, dw);
    final out = Float32List(oh * ow * o);
    for (var oy = 0; oy < oh; oy++) {
      for (var ox = 0; ox < ow; ox++) {
        final ob = (oy * ow + ox) * o;
        for (var oc = 0; oc < o; oc++) {
          out[ob + oc] = bias == null ? 0 : bias[oc];
        }
        for (var ky = 0; ky < kh; ky++) {
          final iy = oy * sh - pt + ky * dh;
          if (iy < 0 || iy >= h) continue;
          for (var kx = 0; kx < kw; kx++) {
            final ix = ox * sw - pl + kx * dw;
            if (ix < 0 || ix >= wd) continue;
            final ib = (iy * wd + ix) * c, wb = (ky * kw + kx) * o;
            for (var oc = 0; oc < o; oc++) {
              out[ob + oc] += a[ib + oc ~/ mult] * w[wb + oc];
            }
          }
        }
        if (act != 0) {
          for (var oc = 0; oc < o; oc++) {
            out[ob + oc] = _act(out[ob + oc], act);
          }
        }
      }
    }
    return out;
  }

  /// MediaPipe's transposed convolution with bias; its padding enum is 1 SAME, 2 VALID.
  Float32List _transposeConv(Float32List a, List<int> ish, Float32List w, List<int> wsh, Float32List bias, List<int> os, Map<String, dynamic> op) {
    final h = ish[1], wd = ish[2], c = ish[3];
    final oh = os[1], ow = os[2], o = os[3];
    final kh = wsh[1], kw = wsh[2];
    final sh = op['sh'] as int, sw = op['sw'] as int;
    final same = op['pad'] == 1;
    final pt = same ? math.max((h - 1) * sh + kh - oh, 0) ~/ 2 : 0;
    final pl = same ? math.max((wd - 1) * sw + kw - ow, 0) ~/ 2 : 0;
    final out = Float32List(oh * ow * o);
    for (var i = 0; i < oh * ow; i++) {
      for (var oc = 0; oc < o; oc++) {
        out[i * o + oc] = bias[oc];
      }
    }
    for (var iy = 0; iy < h; iy++) {
      for (var ix = 0; ix < wd; ix++) {
        final ib = (iy * wd + ix) * c;
        for (var ky = 0; ky < kh; ky++) {
          final oy = iy * sh + ky - pt;
          if (oy < 0 || oy >= oh) continue;
          for (var kx = 0; kx < kw; kx++) {
            final ox = ix * sw + kx - pl;
            if (ox < 0 || ox >= ow) continue;
            final ob = (oy * ow + ox) * o;
            for (var oc = 0; oc < o; oc++) {
              final wb = ((oc * kh + ky) * kw + kx) * c;
              var s = 0.0;
              for (var ic = 0; ic < c; ic++) {
                s += a[ib + ic] * w[wb + ic];
              }
              out[ob + oc] += s;
            }
          }
        }
      }
    }
    return out;
  }

  Float32List _pool(Float32List a, List<int> ish, List<int> os, Map<String, dynamic> op, bool isMax) {
    final h = ish[1], wd = ish[2], c = ish[3];
    final oh = os[1], ow = os[2];
    final fh = op['fh'] as int, fw = op['fw'] as int, sh = op['sh'] as int, sw = op['sw'] as int;
    final same = op['pad'] == 0, act = op['act'] as int? ?? 0;
    final pt = _padBefore(same, h, oh, sh, fh, 1), pl = _padBefore(same, wd, ow, sw, fw, 1);
    final out = Float32List(oh * ow * c);
    for (var oy = 0; oy < oh; oy++) {
      for (var ox = 0; ox < ow; ox++) {
        final y0 = math.max(0, oy * sh - pt), y1 = math.min(h, oy * sh - pt + fh);
        final x0 = math.max(0, ox * sw - pl), x1 = math.min(wd, ox * sw - pl + fw);
        final n = (y1 - y0) * (x1 - x0);
        for (var ch = 0; ch < c; ch++) {
          var r = isMax ? double.negativeInfinity : 0.0;
          for (var y = y0; y < y1; y++) {
            for (var x = x0; x < x1; x++) {
              final val = a[(y * wd + x) * c + ch];
              if (isMax) {
                if (val > r) r = val;
              } else {
                r += val;
              }
            }
          }
          if (!isMax && n > 0) r /= n;
          out[(oy * ow + ox) * c + ch] = act == 0 ? r : _act(r, act);
        }
      }
    }
    return out;
  }

  static List<int> _pad4(List<int> s) => [for (var i = 0; i < 4 - s.length; i++) 1, ...s];

  Float32List _binary(Float32List a, List<int> as0, Float32List b, List<int> bs0, List<int> os0, bool add, int act) {
    final n = a.length > b.length ? a.length : b.length;
    final out = Float32List(n);
    if (a.length == b.length) {
      for (var i = 0; i < n; i++) {
        out[i] = add ? a[i] + b[i] : a[i] * b[i];
      }
    } else if (b.length == 1 || a.length == 1) {
      final s = b.length == 1 ? b[0] : a[0], big = b.length == 1 ? a : b;
      for (var i = 0; i < n; i++) {
        out[i] = add ? big[i] + s : big[i] * s;
      }
    } else {
      // general broadcast over up to 4 dims
      final as = _pad4(as0), bs = _pad4(bs0), os = _pad4(os0);
      int idx(List<int> s, int i0, int i1, int i2, int i3) =>
          (((i0 % s[0]) * s[1] + (i1 % s[1])) * s[2] + (i2 % s[2])) * s[3] + (i3 % s[3]);
      var k = 0;
      for (var i0 = 0; i0 < os[0]; i0++) {
        for (var i1 = 0; i1 < os[1]; i1++) {
          for (var i2 = 0; i2 < os[2]; i2++) {
            for (var i3 = 0; i3 < os[3]; i3++) {
              final x = a[idx(as, i0, i1, i2, i3)], y = b[idx(bs, i0, i1, i2, i3)];
              out[k++] = add ? x + y : x * y;
            }
          }
        }
      }
    }
    if (act != 0) {
      for (var i = 0; i < n; i++) {
        out[i] = _act(out[i], act);
      }
    }
    return out;
  }

  Float32List _pad(Float32List a, List<int> ish0, List<int> p, List<int> os0) {
    final ish = _pad4(ish0), os = _pad4(os0);
    final out = Float32List(os.fold<int>(1, (x, y) => x * y));
    final off = [for (var d = 0; d < 4; d++) p[d * 2]];
    for (var y = 0; y < ish[1]; y++) {
      for (var x = 0; x < ish[2]; x++) {
        final ib = (y * ish[2] + x) * ish[3];
        final ob = ((y + off[1]) * os[2] + (x + off[2])) * os[3] + off[3];
        for (var ch = 0; ch < ish[3]; ch++) {
          out[ob + ch] = a[ib + ch];
        }
      }
    }
    return out;
  }

  Float32List _concat(List<Float32List> xs, List<List<int>> shapes, List<int> os, int axis) {
    final rank = os.length;
    final ax = axis < 0 ? axis + rank : axis;
    final outer = os.sublist(0, ax).fold<int>(1, (x, y) => x * y);
    final out = Float32List(os.fold<int>(1, (x, y) => x * y));
    var k = 0;
    for (var o = 0; o < outer; o++) {
      for (var t = 0; t < xs.length; t++) {
        final chunk = shapes[t].sublist(ax).fold<int>(1, (x, y) => x * y);
        out.setRange(k, k + chunk, xs[t], o * chunk);
        k += chunk;
      }
    }
    return out;
  }

  Float32List _resize(Float32List a, List<int> ish, List<int> os, bool align, bool half) {
    final h = ish[1], wd = ish[2], c = ish[3], oh = os[1], ow = os[2];
    final syr = align && oh > 1 ? (h - 1) / (oh - 1) : h / oh;
    final sxr = align && ow > 1 ? (wd - 1) / (ow - 1) : wd / ow;
    final out = Float32List(oh * ow * c);
    for (var y = 0; y < oh; y++) {
      final fy = half ? (y + .5) * syr - .5 : y * syr;
      final y0 = math.max(fy.floor(), 0), y1 = math.min(fy.ceil(), h - 1);
      final dy = fy - y0;
      for (var x = 0; x < ow; x++) {
        final fx = half ? (x + .5) * sxr - .5 : x * sxr;
        final x0 = math.max(fx.floor(), 0), x1 = math.min(fx.ceil(), wd - 1);
        final dx = fx - x0;
        for (var ch = 0; ch < c; ch++) {
          final v00 = a[(y0 * wd + x0) * c + ch], v01 = a[(y0 * wd + x1) * c + ch];
          final v10 = a[(y1 * wd + x0) * c + ch], v11 = a[(y1 * wd + x1) * c + ch];
          out[(y * ow + x) * c + ch] = v00 * (1 - dy) * (1 - dx) + v01 * (1 - dy) * dx + v10 * dy * (1 - dx) + v11 * dy * dx;
        }
      }
    }
    return out;
  }
}
