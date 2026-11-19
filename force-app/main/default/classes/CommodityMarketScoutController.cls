/**
 * Invokes the Commodity_Market_Scout Agentforce agent for natural-language
 * commodity market questions. Uses the same native Invocable.Action pattern as
 * AgentforceChatController (no REST callout required).
 */
public with sharing class CommodityMarketScoutController {
    private static final String AGENT_API_NAME = 'Commodity_Market_Scout';

    public class CommodityItem {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public Decimal price;
        @AuraEnabled public Decimal changePercent;
        @AuraEnabled public String unit;
        @AuraEnabled public String comment;
        @AuraEnabled public String source;
    }

    public class CommodityMarketData {
        @AuraEnabled public String currencyCode;
        @AuraEnabled public String lastUpdated;
        @AuraEnabled public List<CommodityItem> commodities;
    }

    public class AskResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String answer;
        @AuraEnabled public String sessionId;
        @AuraEnabled public String rawResponse;
        @AuraEnabled public CommodityMarketData marketData;
        @AuraEnabled public String errorMessage;
    }

    /**
     * Sends an NLP question to Commodity_Market_Scout.
     * LWC must use this single method (pass null for sessionId/contextJson when unused).
     *
     * @param question Natural-language question for the agent
     * @param sessionId Existing Agentforce session id (null for new conversation)
     * @param contextJson Optional JSON string with recipe/ingredient/market context
     */
    @AuraEnabled
    public static AskResult askQuestion(String question, String sessionId, String contextJson) {
        AskResult result = new AskResult();
        result.success = false;

        if (String.isBlank(question)) {
            result.errorMessage = 'Question is required.';
            result.answer = result.errorMessage;
            return result;
        }

        try {
            Invocable.Action action = Invocable.Action.createCustomAction('generateAiAgentResponse', AGENT_API_NAME);

            String contextualizedMessage = buildContextualMessage(question.trim(), contextJson);
            action.setInvocationParameter('userMessage', contextualizedMessage);

            if (String.isNotBlank(sessionId)) {
                action.setInvocationParameter('sessionId', sessionId);
            }

            List<Invocable.Action.Result> results = action.invoke();

            if (results.isEmpty() || !results[0].isSuccess()) {
                String err = !results.isEmpty() ? results[0].getErrors()[0].getMessage() : 'Unknown agent error';
                result.errorMessage = err;
                result.answer = 'Agent Error: ' + err;
                return result;
            }

            Map<String, Object> outputs = results[0].getOutputParameters();
            String rawResponse = extractRawResponse(outputs);
            result.rawResponse = rawResponse;
            result.marketData = parseMarketData(rawResponse);
            result.answer = extractTextFromJson(rawResponse);
            result.success = true;

            if (outputs.containsKey('sessionId')) {
                result.sessionId = (String) outputs.get('sessionId');
            }
        } catch (Exception ex) {
            result.errorMessage = ex.getMessage();
            result.answer = 'System Exception: ' + ex.getMessage();
        }

        return result;
    }

    /**
     * Fetches live commodity prices for recipe ingredients via the agent.
     * Returns structured marketData for direct LWC consumption.
     */
    @AuraEnabled
    public static AskResult fetchCommodityPrices(String contextJson) {
        String prompt =
            'Return current commodity market prices for the ingredients in the provided context. ' +
            'Respond with JSON only using this exact structure: ' +
            '{"currency":"USD","lastUpdated":"<ISO-8601>","commodities":[' +
            '{"id":"<string>","name":"<string>","price":<number>,"changePercent":<number>,' +
            '"unit":"<string>","comment":"<string>","source":"<string>"}]}';
        return askQuestion(prompt, null, contextJson);
    }

    /**
     * Apex-only convenience for a single question (no session/context).
     */
    public static AskResult askQuestionSimple(String question) {
        return askQuestion(question, null, null);
    }

    /**
     * Apex-only helper that returns only the answer text.
     */
    public static String askQuestionText(String question) {
        AskResult result = askQuestionSimple(question);
        return result.answer;
    }

    @TestVisible
    private static String buildContextualMessage(String question, String contextJson) {
        if (String.isBlank(contextJson)) {
            return question;
        }
        return '[System Context: ' + contextJson + ']\n\n' + question;
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

    /**
     * Parses Agentforce JSON payloads into the AI commodity market structure.
     */
    @TestVisible
    private static CommodityMarketData parseMarketData(String jsonString) {
        CommodityMarketData data = new CommodityMarketData();
        data.commodities = new List<CommodityItem>();

        String payload = unwrapAgentPayload(jsonString);
        if (String.isBlank(payload)) {
            return data;
        }

        try {
            if (!payload.trim().startsWith('{')) {
                return data;
            }

            Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(payload);
            data.currencyCode = safeString(root.get('currency'));
            data.lastUpdated = safeString(root.get('lastUpdated'));

            if (root.containsKey('commodities') && root.get('commodities') != null) {
                List<Object> rawList = (List<Object>) root.get('commodities');
                for (Object item : rawList) {
                    if (!(item instanceof Map<String, Object>)) {
                        continue;
                    }
                    CommodityItem commodity = parseCommodityItem((Map<String, Object>) item);
                    if (commodity != null) {
                        data.commodities.add(commodity);
                    }
                }
            }
        } catch (Exception ex) {
            System.debug('Failed to parse Commodity_Market_Scout market data: ' + ex.getMessage());
        }

        return data;
    }

    @TestVisible
    private static CommodityItem parseCommodityItem(Map<String, Object> item) {
        if (item == null || item.isEmpty()) {
            return null;
        }

        CommodityItem commodity = new CommodityItem();
        commodity.id = safeString(item.get('id'));
        commodity.name = safeString(item.get('name'));
        commodity.price = safeDecimal(item.get('price'));
        commodity.changePercent = safeDecimal(item.get('changePercent'));
        commodity.unit = safeString(item.get('unit'));
        commodity.comment = safeString(item.get('comment'));
        commodity.source = safeString(item.get('source'));

        if (String.isBlank(commodity.name) && commodity.price == null) {
            return null;
        }

        return commodity;
    }

    /**
     * Unwraps Agentforce envelopes and markdown code fences to expose the JSON payload.
     */
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
                if (jsonObj.containsKey('commodities')) {
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
            System.debug('Failed to unwrap Commodity_Market_Scout payload: ' + ex.getMessage());
        }

        return payload;
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

    /**
     * Parses Agentforce JSON payloads and extracts human-readable text.
     */
    @TestVisible
    private static String extractTextFromJson(String jsonString) {
        if (String.isBlank(jsonString)) {
            return 'No response generated.';
        }

        CommodityMarketData data = parseMarketData(jsonString);
        if (data != null && data.commodities != null && !data.commodities.isEmpty()) {
            List<String> lines = new List<String>();
            for (CommodityItem item : data.commodities) {
                if (String.isBlank(item.name)) {
                    continue;
                }
                String line = item.name;
                if (item.price != null) {
                    line += ': ' + item.price;
                    if (String.isNotBlank(item.unit)) {
                        line += ' ' + item.unit;
                    }
                }
                if (item.changePercent != null) {
                    line += ' (' + item.changePercent + '%)';
                }
                lines.add(line);
            }
            if (!lines.isEmpty()) {
                return String.join(lines, '\n');
            }
        }

        String payload = unwrapAgentPayload(jsonString);
        if (!payload.trim().startsWith('{') && !payload.trim().startsWith('[')) {
            return payload;
        }

        try {
            if (payload.trim().startsWith('{')) {
                Map<String, Object> jsonObj = (Map<String, Object>) JSON.deserializeUntyped(payload);
                if (jsonObj.containsKey('value')) {
                    return String.valueOf(jsonObj.get('value'));
                }
            }

            if (payload.trim().startsWith('[')) {
                List<Object> jsonArray = (List<Object>) JSON.deserializeUntyped(payload);
                if (!jsonArray.isEmpty() && jsonArray[0] instanceof Map<String, Object>) {
                    Map<String, Object> firstObj = (Map<String, Object>) jsonArray[0];
                    if (firstObj.containsKey('value')) {
                        return String.valueOf(firstObj.get('value'));
                    }
                }
            }
        } catch (Exception ex) {
            System.debug('Failed to parse Commodity_Market_Scout JSON: ' + ex.getMessage());
        }

        return jsonString;
    }
}