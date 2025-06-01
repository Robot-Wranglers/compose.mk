//
// See the main docs: https://robot-wranglers.github.io/compose.mk/demos/ai
//
import { Ollama } from "@langchain/community/llms/ollama";
import { DynamicTool } from "@langchain/core/tools";
import { AgentExecutor, createReactAgent } from "langchain/agents";
import { pull } from "langchain/hub";

const date = new DynamicTool({
  name: "date",
  description: "Use this when asked about today's date, current time, or what day it is.",
  func: async () => {return new Date().toISOString();},
});

const OLLAMA_HOST = process.env.OLLAMA_HOST || "localhost";
const OLLAMA_PORT = process.env.OLLAMA_PORT || "11434";
const OLLAMA_URL = `http://${OLLAMA_HOST}:${OLLAMA_PORT}`;
const llm = new Ollama({model: process.env.LLM_MODEL, baseUrl: OLLAMA_URL,});
const prompt = await pull("hwchase17/react");
const agent = await createReactAgent({llm, tools: [date], prompt,});
const agentExecutor = new AgentExecutor({agent, tools: [date], verbose: false,});

async function askAboutDate() {
  const result = await agentExecutor.invoke({input: process.env.query,});
  console.log("Answer:", result.output);
}

askAboutDate().catch(console.error);