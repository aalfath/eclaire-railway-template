// Writes Eclaire's AI config (config/ai/*.json) for one OpenAI-compatible endpoint
// from LLM_BASE_URL / LLM_MODEL. The key itself stays in the environment (LLM_API_KEY).
import fs from "node:fs";

const dir = "/app/config/ai";
const model = process.env.LLM_MODEL;
const vision = (process.env.LLM_VISION ?? "true") !== "false";
const ctx = Number(process.env.LLM_CONTEXT_WINDOW || 128000);
const id = "railway:" + model.toLowerCase().replace(/[^a-z0-9.-]+/g, "-");

const providers = {
  providers: {
    railway: {
      dialect: "openai_compatible",
      baseUrl: process.env.LLM_BASE_URL,
      auth: { type: "bearer", header: "Authorization", value: "Bearer ${ENV:LLM_API_KEY}" },
    },
  },
};
const models = {
  models: {
    [id]: {
      name: model,
      provider: "railway",
      providerModel: model,
      capabilities: {
        modalities: { input: vision ? ["text", "image"] : ["text"], output: ["text"] },
        streaming: true,
        tools: true,
        jsonSchema: true,
        structuredOutputs: false,
        reasoning: { supported: false },
        contextWindow: ctx,
      },
      source: { url: process.env.LLM_BASE_URL },
    },
  },
};
const selection = { active: { backend: id, workers: id } };

fs.mkdirSync(dir, { recursive: true });
fs.writeFileSync(`${dir}/providers.json`, JSON.stringify(providers, null, 2));
fs.writeFileSync(`${dir}/models.json`, JSON.stringify(models, null, 2));
fs.writeFileSync(`${dir}/selection.json`, JSON.stringify(selection, null, 2));
console.log(`[railway] AI: model ${model} at ${process.env.LLM_BASE_URL} (vision ${vision ? "on" : "off"})`);
