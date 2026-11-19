/**
 * Invokes the Ingredient_Optimization_AI Agentforce agent with unified io_json
 * and returns per-ingredient AI weight suggestions for recipeOptimizer LWC.
 */
public with sharing class IngredientOptimizationController {
    private static final String AGENT_API_NAME = 'Ingredient_Optimization_AI';

    public class IngredientRecommendation {
        @AuraEnabled public String ingredientId;
        @AuraEnabled public String ingredientName;
        @AuraEnabled public Decimal aiWeightSuggestion;
        @AuraEnabled public Decimal aiPercentageSuggestion;
        @AuraEnabled public String aiComment;
    }

    public class OptimizeResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String rawResponse;
        @AuraEnabled public List<IngredientRecommendation> recommendations;
        @AuraEnabled public String errorMessage;
    }

    /**
     * Sends unified recipe JSON to Ingredient_Optimization_AI.
     * The agent expects the same schema in user_message (preview chat pattern).
     *
     * @param ioJson JSON string: currency, ProductName, ProductId, Target_Margin, Ingredients[]
     */
    @AuraEnabled
    public static OptimizeResult optimizeRecipe(String ioJson) {
        System.debug('ioJson ---------------------------------------- before : ' + ioJson);
       // ioJson = ioJson.replaceAll('\\n', '').replaceAll('\\t', '').replaceAll('\\r', '').replaceAll('\\f', '').replaceAll('\\b', '').replaceAll('\\', '');
        ioJson = ioJson.replaceAll('null', '');
        ioJson = ioJson.replaceAll('NULL', '');
        System.debug('ioJson ---------------------------------------- after : '+ ioJson);
        OptimizeResult result = new OptimizeResult();
        result.success = false;
        result.recommendations = new List<IngredientRecommendation>();

        if (String.isBlank(ioJson)) {
            result.errorMessage = 'Recipe JSON (ioJson) is required.';
            return result;
        }

        try {
            Invocable.Action action = Invocable.Action.createCustomAction('generateAiAgentResponse', AGENT_API_NAME);
            action.setInvocationParameter('userMessage', ioJson.trim());

            List<Invocable.Action.Result> results = action.invoke();

            if (results.isEmpty() || !results[0].isSuccess()) {
                String err = !results.isEmpty() ? results[0].getErrors()[0].getMessage() : 'Unknown agent error';
                result.errorMessage = err;
                return result;
            }

            Map<String, Object> outputs = results[0].getOutputParameters();
            String rawResponse = extractRawResponse(outputs);
            result.rawResponse = rawResponse;
            result.recommendations = parseRecommendations(rawResponse);
            result.success = !result.recommendations.isEmpty() || containsIngredientsInPayload(rawResponse);
            if (!result.success && String.isBlank(result.errorMessage)) {
                result.errorMessage = 'Agent returned no ingredient recommendations.';
            }
        } catch (Exception ex) {
            result.errorMessage = ex.getMessage();
        }

        return result;
    }

    @TestVisible
    private static String extractRawResponse(Map<String, Object> outputs) {
        if (outputs == null) {
            return '';
        }
        if (outputs.containsKey('response')) {
            return (String) outputs.get('response');
        }
        if (outputs.containsKey('agentResponse')) {
            return (String) outputs.get('agentResponse');
        }
        if (outputs.containsKey('output')) {
            return (String) outputs.get('output');
        }
        return '';
    }

    @TestVisible
    private static String unwrapAgentPayload(String jsonString) {
        if (String.isBlank(jsonString)) {
            return '';
        }

        String payload = jsonString.trim();

        if (payload.startsWith('```')) {
            payload = payload.replaceAll('(?i)^```json\\s*', '');
            payload = payload.replaceAll('```\\s*$', '');
            payload = payload.trim();
        }

        if (!payload.startsWith('{') && !payload.startsWith('[')) {
            return payload;
        }

        try {
            if (payload.startsWith('{')) {
                Map<String, Object> jsonObj = (Map<String, Object>) JSON.deserializeUntyped(payload);
                if (jsonObj.containsKey('Ingredients') || jsonObj.containsKey('ingredients')) {
                    return payload;
                }
                if (jsonObj.containsKey('value')) {
                    Object value = jsonObj.get('value');
                    if (value instanceof String) {
                        return unwrapAgentPayload((String) value);
                    }
                }
            }

            if (payload.startsWith('[')) {
                List<Object> jsonArray = (List<Object>) JSON.deserializeUntyped(payload);
                if (!jsonArray.isEmpty() && jsonArray[0] instanceof Map<String, Object>) {
                    Map<String, Object> firstObj = (Map<String, Object>) jsonArray[0];
                    if (firstObj.containsKey('value')) {
                        return unwrapAgentPayload(String.valueOf(firstObj.get('value')));
                    }
                }
            }
        } catch (Exception ex) {
            System.debug('Failed to unwrap Ingredient_Optimization_AI payload: ' + ex.getMessage());
        }

        return payload;
    }

    @TestVisible
    private static List<IngredientRecommendation> parseRecommendations(String jsonString) {
        List<IngredientRecommendation> result = new List<IngredientRecommendation>();
        String payload = unwrapAgentPayload(jsonString);

        if (String.isBlank(payload) || !payload.trim().startsWith('{')) {
            return result;
        }

        try {
            Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(payload);
            List<Object> ingredients = null;

            if (root.containsKey('Ingredients') && root.get('Ingredients') instanceof List<Object>) {
                ingredients = (List<Object>) root.get('Ingredients');
            } else if (root.containsKey('ingredients') && root.get('ingredients') instanceof List<Object>) {
                ingredients = (List<Object>) root.get('ingredients');
            }

            if (ingredients == null) {
                return result;
            }

            for (Object rowObj : ingredients) {
                if (!(rowObj instanceof Map<String, Object>)) {
                    continue;
                }
                IngredientRecommendation rec = parseIngredientRow((Map<String, Object>) rowObj);
                if (rec != null) {
                    result.add(rec);
                }
            }
        } catch (Exception ex) {
            System.debug('Failed to parse Ingredient_Optimization_AI response: ' + ex.getMessage());
        }

        return result;
    }

    @TestVisible
    private static IngredientRecommendation parseIngredientRow(Map<String, Object> row) {
        if (row == null || row.isEmpty()) {
            return null;
        }

        IngredientRecommendation rec = new IngredientRecommendation();
        rec.ingredientId = safeString(firstPresent(row, new List<String>{ 'id', 'Id' }));
        rec.ingredientName = safeString(firstPresent(row, new List<String>{ 'name', 'Name' }));
        rec.aiWeightSuggestion = safeDecimal(firstPresent(row, new List<String>{ 'aiSuggestedWeight', 'aiWeightSuggestion' }));
        rec.aiPercentageSuggestion = safeDecimal(
            firstPresent(row, new List<String>{ 'aiSuggestedPercent', 'aiPercentageSuggestion' })
        );
        rec.aiComment = safeString(firstPresent(row, new List<String>{ 'aiComment' }));

        if (String.isBlank(rec.ingredientId) && String.isBlank(rec.ingredientName)) {
            return null;
        }

        return rec;
    }

    @TestVisible
    private static Object firstPresent(Map<String, Object> row, List<String> keys) {
        for (String key : keys) {
            if (row.containsKey(key) && row.get(key) != null) {
                return row.get(key);
            }
        }
        return null;
    }

    @TestVisible
    private static Boolean containsIngredientsInPayload(String jsonString) {
        String payload = unwrapAgentPayload(jsonString);
        if (String.isBlank(payload) || !payload.trim().startsWith('{')) {
            return false;
        }
        try {
            Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(payload);
            return root.containsKey('Ingredients') || root.containsKey('ingredients');
        } catch (Exception ex) {
            return false;
        }
    }

    @TestVisible
    private static String safeString(Object value) {
        return value == null ? null : String.valueOf(value);
    }

    @TestVisible
    private static Decimal safeDecimal(Object value) {
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
        try {
            return Decimal.valueOf(String.valueOf(value));
        } catch (Exception ex) {
            return null;
        }
    }
}