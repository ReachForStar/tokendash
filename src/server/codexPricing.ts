/**
 * Codex token pricing configuration.
 *
 * Pricing formula (confirmed by reverse-engineering @ccusage/codex):
 *   cost = (inputTokens - cachedInputTokens) * input_rate
 *        + cachedInputTokens * cached_rate
 *        + outputTokens * output_rate
 *
 * Reasoning tokens are NOT billed separately (included in outputTokens).
 *
 * Update rates from https://openai.com/api/pricing/ when models change.
 * All prices are USD per 1M tokens.
 */

interface ModelPricing {
  inputPer1M: number;
  cachedInputPer1M: number;
  outputPer1M: number;
}

const MODEL_PRICING: Record<string, ModelPricing> = {
  'gpt-5.5': {
    inputPer1M: 5.00,
    cachedInputPer1M: 0.50,
    outputPer1M: 30.00,
  },
  'gpt-5.4': {
    inputPer1M: 2.50,
    cachedInputPer1M: 0.25,
    outputPer1M: 15.00,
  },
};

const DEFAULT_PRICING: ModelPricing = {
  inputPer1M: 2.50,
  cachedInputPer1M: 0.25,
  outputPer1M: 15.00,
};

interface TokenCounts {
  inputTokens: number;
  cachedInputTokens: number;
  outputTokens: number;
  reasoningOutputTokens: number;
  totalTokens: number;
}

/**
 * Calculate cost in USD from token counts and model pricing.
 * Matches the @ccusage/codex calculateCostUSD function exactly.
 */
export function calculateCost(tokens: TokenCounts, models: Set<string>): number {
  const model = [...models][0] ?? '';
  const pricing = MODEL_PRICING[model] ?? DEFAULT_PRICING;

  const nonCachedInput = Math.max(tokens.inputTokens - tokens.cachedInputTokens, 0);
  const cachedInput = Math.min(tokens.cachedInputTokens, tokens.inputTokens);
  const outputTokens = tokens.outputTokens;

  const inputCost = (nonCachedInput / 1_000_000) * pricing.inputPer1M;
  const cachedCost = (cachedInput / 1_000_000) * pricing.cachedInputPer1M;
  const outputCost = (outputTokens / 1_000_000) * pricing.outputPer1M;

  return inputCost + cachedCost + outputCost;
}

export function getModelPricing(model: string): ModelPricing {
  return MODEL_PRICING[model] ?? DEFAULT_PRICING;
}
