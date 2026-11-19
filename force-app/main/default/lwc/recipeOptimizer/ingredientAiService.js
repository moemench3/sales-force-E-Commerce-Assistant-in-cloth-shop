import fetchCommodityPrices from '@salesforce/apex/CommodityMarketScoutController.fetchCommodityPrices';
import optimizeRecipe from '@salesforce/apex/IngredientOptimizationController.optimizeRecipe';
import projectPrices from '@salesforce/apex/RecipePriceProjectionAction.projectPrices';
import { MOCK_INGREDIENT_CATALOG, MOCK_PRICE_HISTORY } from './mockIngredientData';

const SIMULATED_DELAY_MS = 450;

function delay(ms = SIMULATED_DELAY_MS) {
    return new Promise((resolve) => {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(resolve, ms);
    });
}

function getTrend(currentPrice, previousPrice) {
    if (currentPrice > previousPrice) {
        return {
            direction: 'up',
            label: 'Increase',
            percent: (((currentPrice - previousPrice) / previousPrice) * 100).toFixed(1)
        };
    }
    if (currentPrice < previousPrice) {
        return {
            direction: 'down',
            label: 'Decrease',
            percent: (((previousPrice - currentPrice) / previousPrice) * 100).toFixed(1)
        };
    }
    return { direction: 'neutral', label: 'Unchanged', percent: '0.0' };
}

function findMockByName(name) {
    if (!name) {
        return null;
    }
    const normalized = name.toLowerCase();
    return MOCK_INGREDIENT_CATALOG.find((row) => row.name.toLowerCase() === normalized) || null;
}

function buildMockCommodityCard(row, index) {
    const mock = findMockByName(row.ingredientName) || MOCK_INGREDIENT_CATALOG[0];
    const trend = getTrend(mock.currentPrice, mock.previousPrice);
    const changePercent = Number(trend.percent) * (trend.direction === 'down' ? -1 : 1);

    return {
        id: row.ingredientId || mock.id || `mock-${index}`,
        name: row.ingredientName || mock.name,
        price: mock.currentPrice,
        changePercent,
        unit: 'per kg',
        comment: `${trend.label} vs prior period (mock data).`,
        source: 'Mock Catalog'
    };
}

function buildContextJson(ingredientRows) {
    return JSON.stringify({
        ingredients: ingredientRows.map((row) => ({
            id: row.ingredientId,
            name: row.ingredientName
        }))
    });
}

function toDisplayCard(commodity, index, currencyCode, lastUpdated) {
    return {
        cardId: commodity.id || `commodity-${index}`,
        locked: false,
        id: commodity.id,
        name: commodity.name,
        price: commodity.price,
        changePercent: commodity.changePercent,
        unit: commodity.unit,
        comment: commodity.comment,
        source: commodity.source,
        currencyCode: currencyCode || commodity.currencyCode,
        lastUpdated: lastUpdated || commodity.lastUpdated
    };
}

function commodityLookup(commodityCards = []) {
    const byId = new Map();
    const byName = new Map();
    commodityCards.forEach((card) => {
        if (card.id) {
            byId.set(card.id, card);
        }
        if (card.name) {
            byName.set(card.name.toLowerCase(), card);
        }
    });
    return { byId, byName };
}

/**
 * Builds unified io_json for Ingredient_Optimization_AI from scout commodity data.
 */
export function buildIoJson(ingredientRows = [], productMeta = {}, commodityCards = []) {
    const { byId, byName } = commodityLookup(commodityCards);
    const firstCard = commodityCards[0] || {};

    return {
        currency: firstCard.currencyCode || 'USD',
        lastUpdated: firstCard.lastUpdated || new Date().toISOString(),
        ProductName: productMeta.name || '',
        ProductId: productMeta.id || '',
        Target_Margin: productMeta.targetMargin != null ? productMeta.targetMargin : null,
        Ingredients: ingredientRows.map((row) => {
            const commodity =
                byId.get(row.ingredientId) ||
                byName.get((row.ingredientName || '').toLowerCase()) ||
                {};
            return {
                id: row.ingredientId,
                name: row.ingredientName,
                price: commodity.price != null ? commodity.price : null,
                changePercent: commodity.changePercent != null ? commodity.changePercent : null,
                unit: commodity.unit || '',
                comment: commodity.comment ?? '',
                source: commodity.source ?? '',
                CurrentWeight: Number(row.weight) || 0,
                aiSuggestedWeight: '',
                aiSuggestedPercent: '',
                aiComment: ''
            };
        })
    };
}

function parseOptionalNumber(value) {
    if (value == null || value === '' || value === '—') {
        return null;
    }
    const parsed = Number(String(value).replace('%', '').trim());
    return Number.isFinite(parsed) ? parsed : null;
}

const GRAMS_BY_UNIT = {
    mg: 0.001,
    milligram: 0.001,
    milligrams: 0.001,
    g: 1,
    gram: 1,
    grams: 1,
    kg: 1000,
    kilogram: 1000,
    kilograms: 1000,
    kgs: 1000,
    mt: 1000000,
    tonne: 1000000,
    tonnes: 1000000,
    t: 907184.74,
    ton: 907184.74,
    lb: 453.59237,
    lbs: 453.59237,
    pound: 453.59237,
    pounds: 453.59237,
    oz: 28.349523125,
    ounce: 28.349523125,
    ounces: 28.349523125,
    ml: 1,
    milliliter: 1,
    millilitre: 1,
    l: 1000,
    liter: 1000,
    litre: 1000
};

function normalizeUnit(rawUnit) {
    if (!rawUnit) {
        return '';
    }
    return String(rawUnit)
        .toLowerCase()
        .replace(/usd|eur|\$/g, ' ')
        .replace(/per|[/_-]/g, ' ')
        .replace(/\s+/g, ' ')
        .trim();
}

function gramsInUnit(rawUnit) {
    const unit = normalizeUnit(rawUnit);
    if (!unit) {
        return 1;
    }
    if (unit.includes('metric ton') || unit.includes('tonne')) {
        return 1000000;
    }
    if (unit.includes('short ton') || unit === 'ton' || unit.endsWith(' ton') || unit === 't') {
        return 907184.74;
    }
    if (GRAMS_BY_UNIT[unit] != null) {
        return GRAMS_BY_UNIT[unit];
    }
    const token = unit.split(' ').pop();
    if (GRAMS_BY_UNIT[token] != null) {
        return GRAMS_BY_UNIT[token];
    }
    return 1;
}

function conversionFactor(weightUnit, priceUnit) {
    const hasWeight = Boolean(normalizeUnit(weightUnit));
    const hasPrice = Boolean(normalizeUnit(priceUnit));
    if (!hasWeight && !hasPrice) {
        return 1;
    }
    const priceGrams = gramsInUnit(hasPrice ? priceUnit : hasWeight ? weightUnit : 'g');
    if (!priceGrams) {
        return 0;
    }
    return gramsInUnit(hasWeight ? weightUnit : 'g') / priceGrams;
}

function toPriceUnit(rawUnit) {
    const unit = normalizeUnit(rawUnit);
    if (!unit) {
        return 'per ton';
    }
    if (unit.includes('ton') || unit.includes('tonne') || unit === 'mt' || unit === 't') {
        return 'per ton';
    }
    return rawUnit;
}

/**
 * Payload for Recipe_Price_Projection_AI / RecipePriceProjectionAction.
 * Old mix = CurrentWeight; new mix = AI weight suggestion; prices = latest scout unit prices.
 */
export function buildPriceProjectionPayload(
    ingredientRows = [],
    productMeta = {},
    commodityCards = [],
    tableRows = [],
    persistLastPrice = false
) {
    const { byId, byName } = commodityLookup(commodityCards);
    const firstCard = commodityCards[0] || {};
    const aiById = new Map();
    const aiByName = new Map();
    (tableRows || []).forEach((row) => {
        const weight = parseOptionalNumber(row.aiWeightSuggestion);
        if (weight == null) {
            return;
        }
        if (row.ingredientId) {
            aiById.set(row.ingredientId, weight);
        }
        if (row.ingredientName) {
            aiByName.set(row.ingredientName.toLowerCase(), weight);
        }
    });

    return {
        currency: firstCard.currencyCode || 'USD',
        ProductId: productMeta.id || '',
        persistLastPrice: !!persistLastPrice,
        Ingredients: ingredientRows.map((row) => {
            const commodity =
                byId.get(row.ingredientId) ||
                byName.get((row.ingredientName || '').toLowerCase()) ||
                {};
            const aiWeight =
                aiById.get(row.ingredientId) ??
                aiByName.get((row.ingredientName || '').toLowerCase()) ??
                parseOptionalNumber(row.aiSuggestedWeight);
            const priceUnit = toPriceUnit(commodity.unit);
            return {
                id: row.ingredientId,
                name: row.ingredientName,
                CurrentWeight: Number(row.weight) || 0,
                weightUnit: 'g',
                aiSuggestedWeight: aiWeight,
                price: commodity.price != null ? Number(commodity.price) : 0,
                priceUnit
            };
        })
    };
}

export function computePriceProjectionLocally(payload) {
    const ingredients = payload?.Ingredients || [];
    let oldTotal = 0;
    let newTotal = 0;
    let hasAiWeight = false;
    ingredients.forEach((row) => {
        const unitPrice = Number(row.price) || 0;
        const factor = conversionFactor(row.weightUnit, row.priceUnit);
        oldTotal += (Number(row.CurrentWeight) || 0) * unitPrice * factor;
        const aiWeight = parseOptionalNumber(row.aiSuggestedWeight);
        if (aiWeight != null) {
            newTotal += aiWeight * unitPrice * factor;
            hasAiWeight = true;
        }
    });
    return {
        success: true,
        currencyCode: payload?.currency || 'USD',
        oldDistributionNewPrice: Number(oldTotal.toFixed(4)),
        newDistributionNewPrice: hasAiWeight ? Number(newTotal.toFixed(4)) : null
    };
}

/**
 * Step 3: Recipe_Price_Projection_AI calculator (Apex source of truth).
 */
export async function projectRecipePrices(payload) {
    try {
        const result = await projectPrices({ payloadJson: JSON.stringify(payload) });
        if (result?.success) {
            return result;
        }
        // eslint-disable-next-line no-console
        console.warn('Price projection Apex returned an error, using local fallback.', result?.error);
    } catch (error) {
        // eslint-disable-next-line no-console
        console.warn('Price projection Apex unavailable, using local fallback.', error);
    }
    return computePriceProjectionLocally(payload);
}

function unwrapJsonPayload(text) {
    if (!text) {
        return null;
    }
    let payload = text.trim();
    if (payload.startsWith('```')) {
        payload = payload.replace(/^```json\s*/i, '').replace(/```\s*$/, '').trim();
    }
    if (!payload.startsWith('{')) {
        return null;
    }
    try {
        const parsed = JSON.parse(payload);
        if (parsed.value && typeof parsed.value === 'string') {
            return unwrapJsonPayload(parsed.value);
        }
        return parsed;
    } catch (e) {
        return null;
    }
}

function mapAgentRecommendations(agentRows = []) {
    return agentRows.map((row) => ({
        ingredientId: row.ingredientId,
        ingredientName: row.ingredientName,
        aiWeightSuggestion: row.aiWeightSuggestion,
        aiPercentageSuggestion: row.aiPercentageSuggestion,
        aiComment: row.aiComment || ''
    }));
}

/**
 * Client-side parse when Apex returns raw JSON but empty recommendations list.
 */
function parseRecommendationsFromRaw(rawResponse) {
    const root = unwrapJsonPayload(rawResponse);
    if (!root) {
        return [];
    }
    const ingredients = root.Ingredients || root.ingredients || [];
    if (!Array.isArray(ingredients)) {
        return [];
    }
    return ingredients
        .map((ing) => ({
            ingredientId: ing.id,
            ingredientName: ing.name,
            aiWeightSuggestion: ing.aiSuggestedWeight ?? ing.aiWeightSuggestion ?? null,
            aiPercentageSuggestion: ing.aiSuggestedPercent ?? ing.aiPercentageSuggestion ?? null,
            aiComment: ing.aiComment || ''
        }))
        .filter((row) => row.ingredientId || row.ingredientName);
}

function marketDataToCards(marketData) {
    if (!marketData?.commodities?.length) {
        return [];
    }
    const { currencyCode, lastUpdated, commodities } = marketData;
    return commodities.map((commodity, index) =>
        toDisplayCard(commodity, index, currencyCode, lastUpdated)
    );
}

async function getMockRecommendations(ingredientRows = [], totalProductWeight = 0) {
    await delay();
    const total =
        totalProductWeight > 0
            ? totalProductWeight
            : ingredientRows.reduce((sum, row) => sum + (Number(row.weight) || 0), 0);

    return ingredientRows.map((row, index) => {
        const weight = Number(row.weight) || 0;
        const currentPct = total > 0 ? (weight / total) * 100 : 0;
        const suggestedWeight = Math.max(0, Number((weight * (index % 2 === 0 ? 0.93 : 1.04)).toFixed(2)));
        const suggestedPct = total > 0 ? (suggestedWeight / total) * 100 : 0;
        const delta = Math.abs(suggestedPct - currentPct);

        return {
            ingredientId: row.ingredientId,
            ingredientName: row.ingredientName,
            aiWeightSuggestion: suggestedWeight,
            aiPercentageSuggestion: Number(suggestedPct.toFixed(2)),
            aiComment:
                delta >= 5
                    ? 'AI suggests adjusting this ingredient to optimize cost while preserving flavor balance.'
                    : 'Current ratio is close to optimal. Minor tuning optional.'
        };
    });
}

/**
 * Step 1: Commodity_Market_Scout via fetchCommodityPrices (askQuestion under the hood).
 */
export async function getIngredientPrices(ingredientRows = []) {
    if (!ingredientRows.length) {
        return { commodityCards: [], scoutResult: null };
    }

    try {
        const contextJson = buildContextJson(ingredientRows);
        const scoutResult = await fetchCommodityPrices({ contextJson });

        if (scoutResult?.success && scoutResult.marketData?.commodities?.length) {
            return {
                commodityCards: marketDataToCards(scoutResult.marketData),
                scoutResult
            };
        }
    } catch (error) {
        // eslint-disable-next-line no-console
        console.warn('Commodity market scout unavailable, using mock fallback.', error);
    }

    return {
        commodityCards: ingredientRows.map((row, index) =>
            toDisplayCard(buildMockCommodityCard(row, index), index)
        ),
        scoutResult: null
    };
}

/**
 * Step 2: Ingredient_Optimization_AI using commodity scout output in io_json.
 */
export async function getIngredientRecommendations(
    ingredientRows = [],
    totalProductWeight = 0,
    productMeta = {},
    commodityCards = []
) {
    if (!ingredientRows.length) {
        return [];
    }

    try {
        const ioJson = buildIoJson(ingredientRows, productMeta, commodityCards);
        const optimizeResult = await optimizeRecipe({ ioJson: JSON.stringify(ioJson) });
        let recommendations = [];
        if (optimizeResult?.recommendations?.length) {
            recommendations = mapAgentRecommendations(optimizeResult.recommendations);
        } else if (optimizeResult?.rawResponse) {
            recommendations = parseRecommendationsFromRaw(optimizeResult.rawResponse);
        }

        if (recommendations.length) {
            return recommendations;
        }

        // eslint-disable-next-line no-console
        console.warn(
            'Ingredient optimization agent returned no rows.',
            optimizeResult?.errorMessage,
            optimizeResult?.rawResponse
        );
    } catch (error) {
        // eslint-disable-next-line no-console
        console.warn('Ingredient_Optimization_AI unavailable, using mock fallback.', error);
    }

    return getMockRecommendations(ingredientRows, totalProductWeight);
}

/**
 * Legacy chained call. UI no longer uses this — scout and optimize are separate buttons.
 */
export async function runScoutThenOptimize(ingredientRows = [], totalProductWeight = 0, productMeta = {}) {
    const { commodityCards, scoutResult } = await getIngredientPrices(ingredientRows);
    const recommendations = await getIngredientRecommendations(
        ingredientRows,
        totalProductWeight,
        productMeta,
        commodityCards
    );

    return {
        commodityCards,
        recommendations,
        scoutResult
    };
}

export async function getPriceHistory(ingredientName) {
    await delay(300);
    return {
        ingredientName: ingredientName || 'Ingredient',
        points: MOCK_PRICE_HISTORY
    };
}

export function getRandomCatalogCards(count = 5, excludeIds = []) {
    const pool = MOCK_INGREDIENT_CATALOG.filter((item) => !excludeIds.includes(item.id));
    const shuffled = [...pool].sort(() => Math.random() - 0.5);
    return shuffled.slice(0, count).map((item, index) => {
        const trend = getTrend(item.currentPrice, item.previousPrice);
        const changePercent = Number(trend.percent) * (trend.direction === 'down' ? -1 : 1);
        return toDisplayCard(
            {
                id: item.id,
                name: item.name,
                price: item.currentPrice,
                changePercent,
                unit: 'per kg',
                comment: 'Discovery mode sample pricing.',
                source: 'Mock Catalog'
            },
            index
        );
    });
}