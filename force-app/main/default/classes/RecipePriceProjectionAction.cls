/**
 * Price projection for Recipe Optimizer.
 * Uses current (old) weights and AI-suggested (new) weights against latest ingredient unit prices.
 * Invocable so Agentforce Recipe_Price_Projection_AI can call it; AuraEnabled for the LWC.
 */
public with sharing class RecipePriceProjectionAction {
    public class Request {
        @InvocableVariable(
            required=true
            label='Payload JSON'
            description='JSON with ProductId, currency, Ingredients[{id,name,CurrentWeight,weightUnit,aiSuggestedWeight,price,priceUnit}]'
        )
        public String payloadJson;
    }

    public class Response {
        @InvocableVariable(label='Result JSON')
        public String resultJson;
    }

    public class ProjectionResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String error;
        @AuraEnabled public String currencyCode;
        @AuraEnabled public Decimal oldDistributionNewPrice;
        @AuraEnabled public Decimal newDistributionNewPrice;
        @AuraEnabled public Decimal lastPrice;
    }

    @InvocableMethod(
        label='Project Recipe Prices'
        description='Calculates product cost using current weights vs AI weights at latest ingredient prices.'
    )
    public static List<Response> execute(List<Request> requests) {
        List<Response> responses = new List<Response>();
        if (requests == null || requests.isEmpty()) {
            Response empty = new Response();
            empty.resultJson = JSON.serialize(errorResult('No payload was provided.'));
            responses.add(empty);
            return responses;
        }
        for (Request req : requests) {
            Response res = new Response();
            ProjectionResult projected = projectPrices(req != null ? req.payloadJson : null);
            res.resultJson = JSON.serialize(projected);
            responses.add(res);
        }
        return responses;
    }

    @AuraEnabled
    public static ProjectionResult projectPrices(String payloadJson) {
        try {
            if (String.isBlank(payloadJson)) {
                return errorResult('Payload JSON is required.');
            }
            Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(payloadJson.trim());
            ProjectionResult result = new ProjectionResult();
            result.success = true;
            result.currencyCode = root.containsKey('currency') && root.get('currency') != null
                ? String.valueOf(root.get('currency'))
                : 'USD';

            Object ingredientsRaw = root.containsKey('Ingredients')
                ? root.get('Ingredients')
                : root.get('ingredients');
            if (!(ingredientsRaw instanceof List<Object>)) {
                return errorResult('Ingredients array is required.');
            }

            Decimal oldTotal = 0;
            Decimal newTotal = 0;
            Boolean hasAiWeight = false;

            for (Object rowObj : (List<Object>) ingredientsRaw) {
                if (!(rowObj instanceof Map<String, Object>)) {
                    continue;
                }
                Map<String, Object> row = (Map<String, Object>) rowObj;
                Decimal unitPrice = toDecimal(firstValue(row, new List<String>{ 'price', 'unitPrice' }));
                if (unitPrice == null) {
                    unitPrice = 0;
                }
                Decimal currentWeight = toDecimal(firstValue(row, new List<String>{ 'CurrentWeight', 'currentWeight', 'weight' }));
                Decimal aiWeight = toDecimal(
                    firstValue(row, new List<String>{ 'aiSuggestedWeight', 'aiWeightSuggestion' })
                );
                String weightUnit = toStringValue(
                    firstValue(row, new List<String>{ 'weightUnit', 'CurrentUnit' })
                );
                String priceUnit = toStringValue(
                    firstValue(row, new List<String>{ 'priceUnit', 'price_unit' })
                );
                // Convert recipe weight into the quoted price unit (e.g. 18 g vs $2,000 / metric ton).
                Decimal unitFactor = conversionFactor(weightUnit, priceUnit);

                if (currentWeight != null) {
                    oldTotal += currentWeight * unitPrice * unitFactor;
                }
                if (aiWeight != null) {
                    newTotal += aiWeight * unitPrice * unitFactor;
                    hasAiWeight = true;
                }
            }

            result.oldDistributionNewPrice = oldTotal.setScale(4);
            result.newDistributionNewPrice = hasAiWeight ? newTotal.setScale(4) : null;

            String productId = root.containsKey('ProductId') && root.get('ProductId') != null
                ? String.valueOf(root.get('ProductId'))
                : null;
            Boolean persist = toBoolean(root.get('persistLastPrice'));
            if (persist && String.isNotBlank(productId)) {
                Decimal toStore = result.newDistributionNewPrice != null
                    ? result.newDistributionNewPrice
                    : result.oldDistributionNewPrice;
                if (toStore != null) {
                    updateLastPrice(productId, toStore);
                    result.lastPrice = toStore;
                }
            } else if (String.isNotBlank(productId)) {
                result.lastPrice = loadLastPrice(productId);
            }

            return result;
        } catch (Exception ex) {
            return errorResult('Unable to project prices: ' + ex.getMessage());
        }
    }

    private static void updateLastPrice(String productId, Decimal lastPrice) {
        try {
            Product__c product = new Product__c(Id = productId, Last_Price__c = lastPrice);
            update product;
        } catch (Exception ex) {
            System.debug(LoggingLevel.WARN, 'Last_Price__c update skipped: ' + ex.getMessage());
        }
    }

    private static Decimal loadLastPrice(String productId) {
        try {
            List<Product__c> rows = [
                SELECT Last_Price__c
                FROM Product__c
                WHERE Id = :productId
                LIMIT 1
            ];
            return rows.isEmpty() ? null : rows[0].Last_Price__c;
        } catch (Exception ex) {
            return null;
        }
    }

    /**
     * Recipe weight grams / price-quote grams.
     * Blank units on both sides keep a factor of 1 (same-unit payloads).
     * Recipe weights default to grams; "ton" is US short ton unless labeled metric/tonne.
     */
    @TestVisible
    private static Decimal conversionFactor(String weightUnit, String priceUnit) {
        Boolean hasWeight = String.isNotBlank(normalizeUnit(weightUnit));
        Boolean hasPrice = String.isNotBlank(normalizeUnit(priceUnit));
        if (!hasWeight && !hasPrice) {
            return 1;
        }
        Decimal weightGrams = gramsInUnit(hasWeight ? weightUnit : 'g');
        Decimal priceGrams = gramsInUnit(hasPrice ? priceUnit : (hasWeight ? weightUnit : 'g'));
        if (priceGrams == 0) {
            return 0;
        }
        return weightGrams / priceGrams;
    }

    @TestVisible
    private static Decimal gramsInUnit(String rawUnit) {
        String unit = normalizeUnit(rawUnit);
        if (String.isBlank(unit)) {
            return 1; // default gram
        }
        if (unit.contains('metric ton') || unit.contains('tonne') || unit == 'mt') {
            return 1000000;
        }
        if (unit.contains('short ton') || unit == 'ton' || unit.endsWith(' ton') || unit == 't') {
            return 907184.74;
        }
        if (unit == 'mg' || unit.contains('milligram')) {
            return 0.001;
        }
        if (unit == 'kg' || unit.contains('kilogram') || unit == 'kgs') {
            return 1000;
        }
        if (unit == 'lb' || unit == 'lbs' || unit.contains('pound')) {
            return 453.59237;
        }
        if (unit == 'oz' || unit.contains('ounce')) {
            return 28.349523125;
        }
        if (unit == 'l' || unit.contains('liter') || unit.contains('litre')) {
            return 1000;
        }
        if (unit == 'ml' || unit.contains('milliliter') || unit.contains('millilitre')) {
            return 1;
        }
        if (unit == 'g' || unit.contains('gram')) {
            return 1;
        }
        return 1;
    }

    @TestVisible
    private static String normalizeUnit(String rawUnit) {
        if (String.isBlank(rawUnit)) {
            return '';
        }
        String unit = rawUnit.toLowerCase().trim();
        unit = unit.replace('usd', ' ').replace('eur', ' ').replace('$', ' ');
        unit = unit.replace('per', ' ').replace('/', ' ').replace('-', ' ').replace('_', ' ');
        unit = unit.replaceAll('\\s+', ' ').trim();
        return unit;
    }

    private static String toStringValue(Object value) {
        return value == null ? null : String.valueOf(value).trim();
    }

    private static Object firstValue(Map<String, Object> row, List<String> keys) {
        for (String key : keys) {
            if (row.containsKey(key) && row.get(key) != null && String.valueOf(row.get(key)).trim() != '') {
                return row.get(key);
            }
        }
        return null;
    }

    private static Boolean toBoolean(Object value) {
        if (value instanceof Boolean) {
            return (Boolean) value;
        }
        return value != null && 'true'.equalsIgnoreCase(String.valueOf(value).trim());
    }

    @TestVisible
    private static Decimal toDecimal(Object value) {
        if (value == null) {
            return null;
        }
        if (value instanceof Decimal) {
            return (Decimal) value;
        }
        if (value instanceof Integer) {
            return Decimal.valueOf((Integer) value);
        }
        if (value instanceof Long) {
            return Decimal.valueOf((Long) value);
        }
        if (value instanceof Double) {
            return Decimal.valueOf((Double) value);
        }
        String text = String.valueOf(value).trim();
        if (text == '' || text == 'null') {
            return null;
        }
        return Decimal.valueOf(text);
    }

    private static ProjectionResult errorResult(String message) {
        ProjectionResult result = new ProjectionResult();
        result.success = false;
        result.error = message;
        return result;
    }
}