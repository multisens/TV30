import { Request, Response } from "express";
import service from "./service";

function GETRenderers(req: Request, res: Response): void {
  const renderers = service.getRenderersMetadata();
  if (!renderers || renderers.length === 0) {
    res.status(200).json({
      renderers: [],
    });
    return;
  }

  res.status(200).json({
    renderers,
  });
}

function GETRenderer(req: Request, res: Response): void {
  const rendererId = req.params["rendererId"];
  if (!rendererId) {
    res.status(400).json({
      error: 105,
      description: "Missing argument: renderer-id",
    });
    return;
  }

  const renderer = service.getRendererMetadata(rendererId);
  if (!renderer) {
    res.status(400).json({
      error: 101,
      description: "Invalid renderer-id, renderer not found",
    });
    return;
  }

  res.status(200).json({
    renderer,
  });
}

function POSTControlRenderer(req: Request, res: Response): void {
  console.log("[POSTControlRenderer] Action received at ", Date.now());

  const rendererId = req.params["rendererId"];
  if (!rendererId) {
    res.status(400).json({
      error: 105,
      description: "Missing argument: renderer-id",
    });
    return;
  }
  const body = req.body;
  if (!body || !body.effectType || !body.action) {
    res.status(400).json({
      error: 101,
      description: "No body defined or body malformed",
    });
    return;
  }

  const renderer = service.getRendererMetadata(rendererId);
  if (!renderer) {
    res.status(400).json({
      error: 105,
      description: "Invalid renderer-id, renderer not found",
    });
    return;
  }

  try {
    service.controlRenderer(rendererId, body);
    res.status(204).json({});
  } catch (error) {
    res.status(400).json({
      error: 101,
      description: error,
    });
  }
}

export default { GETRenderers, GETRenderer, POSTControlRenderer };
