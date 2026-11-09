"""Converts a MediaPipe .tflite model into the app's own simple model format (.nnm).

Format: b'NNM1' + uint32 json_len + json + zero padding to 4 bytes + blob.
JSON lists tensors (shape, constant data offset/type) and ops with their parameters.
DEQUANTIZE ops are folded: their float16 inputs become constant tensors.
Usage: python convert_tflite.py in.tflite out.nnm   (needs: pip install tflite numpy)
"""
import sys, json, struct, numpy as np, tflite

BO = tflite.BuiltinOperator
NAMES = {v: k for k, v in BO.__dict__.items() if not k.startswith('_')}


def opts(op, cls):
    t = op.BuiltinOptions()
    o = cls()
    o.Init(t.Bytes, t.Pos)
    return o


def main(src, dst):
    m = tflite.Model.GetRootAsModel(open(src, 'rb').read(), 0)
    g = m.Subgraphs(0)
    blob = bytearray()
    tensors = []
    alias = {}  # dequantize output -> its constant input

    def tensor_data(i):
        t = g.Tensors(i)
        b = m.Buffers(t.Buffer()).DataAsNumpy()
        return None if isinstance(b, int) or b is None or len(b) == 0 else (t.Type(), np.asarray(b, dtype=np.uint8).tobytes())

    for i in range(g.TensorsLength()):
        t = g.Tensors(i)
        shape = t.ShapeAsNumpy().tolist() if t.ShapeLength() else []
        e = {'shape': shape}
        d = tensor_data(i)
        if d:
            typ, raw = d
            while len(blob) % 4:
                blob.append(0)
            if typ == 0:
                e.update(dt='f32', off=len(blob)); blob += raw
            elif typ == 1:
                e.update(dt='f16', off=len(blob)); blob += raw
            elif typ == 2:
                e['ints'] = np.frombuffer(raw, dtype=np.int32).tolist()
            else:
                raise SystemExit(f'tensor type {typ} not supported')
        tensors.append(e)

    ops = []
    for k in range(g.OperatorsLength()):
        op = g.Operators(k)
        oc = m.OperatorCodes(op.OpcodeIndex())
        code = max(oc.BuiltinCode(), oc.DeprecatedBuiltinCode())
        ins = [int(x) for x in op.InputsAsNumpy()] if op.InputsLength() else []
        outs = [int(x) for x in op.OutputsAsNumpy()]
        name = oc.CustomCode().decode() if code == BO.CUSTOM else NAMES[code]
        if name == 'DEQUANTIZE':
            src_t = tensors[ins[0]]
            tensors[outs[0]].update({k2: v for k2, v in src_t.items() if k2 in ('dt', 'off')})
            continue
        e = {'op': name, 'in': ins, 'out': outs}
        if name == 'CONV_2D':
            o = opts(op, tflite.Conv2DOptions)
            e.update(pad=o.Padding(), sw=o.StrideW(), sh=o.StrideH(), dw=o.DilationWFactor(), dh=o.DilationHFactor(), act=o.FusedActivationFunction())
        elif name == 'DEPTHWISE_CONV_2D':
            o = opts(op, tflite.DepthwiseConv2DOptions)
            e.update(pad=o.Padding(), sw=o.StrideW(), sh=o.StrideH(), dw=o.DilationWFactor(), dh=o.DilationHFactor(), mult=o.DepthMultiplier(), act=o.FusedActivationFunction())
        elif name in ('MAX_POOL_2D', 'AVERAGE_POOL_2D'):
            o = opts(op, tflite.Pool2DOptions)
            e.update(pad=o.Padding(), sw=o.StrideW(), sh=o.StrideH(), fw=o.FilterWidth(), fh=o.FilterHeight(), act=o.FusedActivationFunction())
        elif name in ('ADD', 'MUL'):
            o = opts(op, tflite.AddOptions if name == 'ADD' else tflite.MulOptions)
            e['act'] = o.FusedActivationFunction()
        elif name == 'CONCATENATION':
            o = opts(op, tflite.ConcatenationOptions)
            e.update(axis=o.Axis(), act=o.FusedActivationFunction())
        elif name == 'RESIZE_BILINEAR':
            o = opts(op, tflite.ResizeBilinearOptions)
            e.update(align=bool(o.AlignCorners()), half=bool(o.HalfPixelCenters()))
        elif name == 'Convolution2DTransposeBias':
            pad, sw, sh = struct.unpack('<3i', op.CustomOptionsAsNumpy().tobytes()[:12])
            e.update(op='TRANSPOSE_CONV_BIAS', pad=pad, sw=sw, sh=sh)
        elif name in ('RELU', 'PRELU', 'HARD_SWISH', 'LOGISTIC', 'PAD', 'RESHAPE'):
            pass
        else:
            raise SystemExit(f'op {name} not supported')
        ops.append(e)

    head = json.dumps({'tensors': tensors, 'ops': ops, 'inputs': g.InputsAsNumpy().tolist(), 'outputs': g.OutputsAsNumpy().tolist()}, separators=(',', ':')).encode()
    out = bytearray(b'NNM1') + struct.pack('<I', len(head)) + head
    while len(out) % 4:
        out.append(32)  # pad json with spaces... (length already written, padding is skipped by reader)
    open(dst, 'wb').write(bytes(out) + bytes(blob))
    print(dst, len(ops), 'ops', len(out) + len(blob), 'bytes')


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
