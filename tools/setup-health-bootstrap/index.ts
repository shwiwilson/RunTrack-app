import { createHandler } from "./bridge.ts";

Deno.serve(createHandler({
  env: (name) => Deno.env.get(name) ?? "",
  fetch,
  now: () => Math.floor(Date.now() / 1000),
  sleep: (milliseconds) =>
    new Promise((resolve) => setTimeout(resolve, milliseconds)),
}));
