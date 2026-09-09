"""Rewrite HardSwish so inbox WinML (max IR 9) can load the model."""

from __future__ import annotations

from pathlib import Path

import numpy as np
from onnx import helper, numpy_helper, save
import onnx

ROOT = Path(__file__).resolve().parent
SRC = ROOT / "selfie_segmentation.onnx"


def main() -> None:
    model = onnx.load(SRC)
    graph = model.graph
    new_nodes = []
    initializers = list(graph.initializer)
    hs = 0
    for node in graph.node:
        if node.op_type != "HardSwish":
            new_nodes.append(node)
            continue
        hs += 1
        x = node.input[0]
        y = node.output[0]
        prefix = f"{y}_hs{hs}"
        c3 = f"{prefix}_c3"
        c0 = f"{prefix}_c0"
        c6 = f"{prefix}_c6"
        inv6 = f"{prefix}_inv6"
        added = f"{prefix}_add"
        clipped = f"{prefix}_clip"
        mixed = f"{prefix}_mul"
        initializers.extend(
            [
                numpy_helper.from_array(np.array(3.0, dtype=np.float32), c3),
                numpy_helper.from_array(np.array(0.0, dtype=np.float32), c0),
                numpy_helper.from_array(np.array(6.0, dtype=np.float32), c6),
                numpy_helper.from_array(np.array(1.0 / 6.0, dtype=np.float32), inv6),
            ]
        )
        new_nodes.extend(
            [
                helper.make_node("Add", [x, c3], [added], name=f"{prefix}_add"),
                helper.make_node(
                    "Clip", [added, c0, c6], [clipped], name=f"{prefix}_clip"
                ),
                helper.make_node("Mul", [x, clipped], [mixed], name=f"{prefix}_mul"),
                helper.make_node("Mul", [mixed, inv6], [y], name=f"{prefix}_scale"),
            ]
        )
    del graph.node[:]
    graph.node.extend(new_nodes)
    del graph.initializer[:]
    graph.initializer.extend(initializers)
    for opset in model.opset_import:
        if opset.domain in ("", "ai.onnx"):
            opset.version = 13
    model.ir_version = 9
    onnx.checker.check_model(model)
    save(model, SRC)
    print(f"rewrote {hs} HardSwish nodes ir={model.ir_version}")


if __name__ == "__main__":
    main()
