public with sharing class RecipeOptimizerController {
    public class RecipeLineInput {
        @AuraEnabled public Id id;
        @AuraEnabled public Id ingredientId;
        @AuraEnabled public Decimal quantity;
        @AuraEnabled public String unit;
    }

    public class RecipeLineView {
        @AuraEnabled public Id id;
        @AuraEnabled public Id ingredientId;
        @AuraEnabled public String ingredientName;
        @AuraEnabled public Decimal quantity;
        @AuraEnabled public String unit;
        @AuraEnabled public Decimal pricePerUnit;
        @AuraEnabled public Decimal lineCost;
    }

    public class RecipeSummary {
        @AuraEnabled public Decimal totalCost;
        @AuraEnabled public Decimal totalQuantity;
        @AuraEnabled public Decimal estimatedMargin;
    }

    public class CommodityPriceView {
        @AuraEnabled public Id ingredientId;
        @AuraEnabled public String ingredientName;
        @AuraEnabled public Decimal currentPrice;
        @AuraEnabled public Date updatedDate;
    }

    public class ProductView {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String category;
        @AuraEnabled public Decimal targetMargin;
        @AuraEnabled public Decimal lastPrice;
    }

    public class IngredientView {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String unit;
        @AuraEnabled public Decimal defaultCost;
        @AuraEnabled public String flavorProfile;
    }

    public class AgentIngredientSuggestion {
        @AuraEnabled public Id ingredientId;
        @AuraEnabled public String ingredientName;
        @AuraEnabled public Decimal suggestedPrice;
        @AuraEnabled public Decimal suggestedQuantity;
        @AuraEnabled public String comment;
    }

    public class AgentRecommendationResult {
        @AuraEnabled public String rawResponse;
        @AuraEnabled public List<AgentIngredientSuggestion> suggestions;
    }

    @AuraEnabled(cacheable=true)
    public static List<ProductView> getProducts() {
        List<ProductView> result = new List<ProductView>();
        for (Product__c row : [
            SELECT Id, Name, Category__c, Target_Margin__c, Last_Price__c
            FROM Product__c
            ORDER BY Name ASC
            LIMIT 200
        ]) {
            ProductView dto = new ProductView();
            dto.id = row.Id;
            dto.name = row.Name;
            dto.category = row.Category__c;
            dto.targetMargin = row.Target_Margin__c;
            dto.lastPrice = row.Last_Price__c;
            result.add(dto);
        }
        return result;
    }

    @AuraEnabled
    public static Id createProduct(String name, String category, Decimal targetMargin) {
        if (String.isBlank(name)) {
            throw new AuraHandledException('Product name is required.');
        }
        try {
            Product__c product = new Product__c(
                Name = name.trim(),
                Category__c = category,
                Target_Margin__c = targetMargin
            );
            insert product;
            return product.Id;
        } catch (Exception ex) {
            throw new AuraHandledException('Unable to create product: ' + ex.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<IngredientView> getIngredients() {
        List<IngredientView> result = new List<IngredientView>();
        for (Ingredient__c row : [
            SELECT Id, Name, Unit__c, Default_Cost__c, Flavor_Profile__c
            FROM Ingredient__c
            ORDER BY Name ASC
            LIMIT 500
        ]) {
            IngredientView dto = new IngredientView();
            dto.id = row.Id;
            dto.name = row.Name;
            dto.unit = row.Unit__c;
            dto.defaultCost = row.Default_Cost__c;
            dto.flavorProfile = row.Flavor_Profile__c;
            result.add(dto);
        }
        return result;
    }

    @AuraEnabled
    public static Id createIngredient(String name, String unit, Decimal defaultCost, String flavorProfile) {
        if (String.isBlank(name)) {
            throw new AuraHandledException('Ingredient name is required.');
        }
        try {
            Ingredient__c ingredient = new Ingredient__c(
                Name = name.trim(),
                Unit__c = unit,
                Default_Cost__c = defaultCost,
                Flavor_Profile__c = flavorProfile
            );
            insert ingredient;

            if (defaultCost != null) {
                insert new Commodity_Price__c(
                    Name = ingredient.Name + ' Price',
                    Ingredient__c = ingredient.Id,
                    Current_Price__c = defaultCost,
                    Updated_Date__c = Date.today()
                );
            }
            return ingredient.Id;
        } catch (Exception ex) {
            throw new AuraHandledException('Unable to create ingredient: ' + ex.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<RecipeLineView> getRecipe(Id productId) {
        List<RecipeLineView> result = new List<RecipeLineView>();
        if (productId == null) {
            return result;
        }

        Map<Id, Decimal> latestPriceByIngredient = getLatestPriceByIngredient(productId);
        for (Recipe_Line__c line : [
            SELECT Id, Ingredient__c, Ingredient__r.Name, Quantity__c, Unit__c
            FROM Recipe_Line__c
            WHERE Product__c = :productId
            ORDER BY CreatedDate ASC
        ]) {
            RecipeLineView dto = new RecipeLineView();
            dto.id = line.Id;
            dto.ingredientId = line.Ingredient__c;
            dto.ingredientName = line.Ingredient__r != null ? line.Ingredient__r.Name : null;
            dto.quantity = line.Quantity__c;
            dto.unit = line.Unit__c;
            dto.pricePerUnit = latestPriceByIngredient.get(line.Ingredient__c);
            dto.lineCost = (dto.pricePerUnit == null || dto.quantity == null) ? 0 : dto.pricePerUnit * dto.quantity;
            result.add(dto);
        }
        return result;
    }

    @AuraEnabled
    public static void updateRecipe(Id productId, List<RecipeLineInput> lines) {
        if (productId == null) {
            throw new AuraHandledException('Product is required.');
        }

        List<Recipe_Line__c> upserts = new List<Recipe_Line__c>();
        Set<Id> keepIds = new Set<Id>();
        if (lines != null) {
            for (RecipeLineInput line : lines) {
                if (line == null || line.ingredientId == null) {
                    continue;
                }
                Recipe_Line__c row = new Recipe_Line__c(
                    Id = line.id,
                    Name = 'Line ' + String.valueOf(line.ingredientId),
                    Product__c = productId,
                    Ingredient__c = line.ingredientId,
                    Quantity__c = line.quantity == null ? 0 : line.quantity,
                    Unit__c = line.unit
                );
                if (line.id != null) {
                    keepIds.add(line.id);
                }
                upserts.add(row);
            }
        }

        if (!upserts.isEmpty()) {
            upsert upserts;
            for (Recipe_Line__c r : upserts) {
                keepIds.add(r.Id);
            }
        }

        List<Recipe_Line__c> toDelete = new List<Recipe_Line__c>();
        for (Recipe_Line__c existing : [
            SELECT Id
            FROM Recipe_Line__c
            WHERE Product__c = :productId
        ]) {
            if (!keepIds.contains(existing.Id)) {
                toDelete.add(existing);
            }
        }
        if (!toDelete.isEmpty()) {
            delete toDelete;
        }
    }

    @AuraEnabled(cacheable=true)
    public static RecipeSummary calculateCost(Id productId) {
        RecipeSummary summary = new RecipeSummary();
        summary.totalCost = 0;
        summary.totalQuantity = 0;
        summary.estimatedMargin = 0;

        if (productId == null) {
            return summary;
        }

        Product__c product = [
            SELECT Id, Target_Margin__c
            FROM Product__c
            WHERE Id = :productId
            LIMIT 1
        ];
        Map<Id, Decimal> latestPriceByIngredient = getLatestPriceByIngredient(productId);
        for (Recipe_Line__c line : [
            SELECT Ingredient__c, Quantity__c
            FROM Recipe_Line__c
            WHERE Product__c = :productId
        ]) {
            Decimal quantity = line.Quantity__c == null ? 0 : line.Quantity__c;
            Decimal ingredientPrice = latestPriceByIngredient.containsKey(line.Ingredient__c)
                ? latestPriceByIngredient.get(line.Ingredient__c)
                : 0;
            summary.totalQuantity += quantity;
            summary.totalCost += quantity * ingredientPrice;
        }

        Decimal targetMargin = product.Target_Margin__c == null ? 0 : product.Target_Margin__c;
        summary.estimatedMargin = targetMargin;
        return summary;
    }

    @AuraEnabled(cacheable=true)
    public static List<CommodityPriceView> getCommodityPrices(Id productId) {
        List<CommodityPriceView> result = new List<CommodityPriceView>();
        if (productId == null) {
            return result;
        }

        Set<Id> ingredientIds = getIngredientIdsForProduct(productId);
        if (ingredientIds.isEmpty()) {
            return result;
        }

        Map<Id, Commodity_Price__c> latest = new Map<Id, Commodity_Price__c>();
        for (Commodity_Price__c price : [
            SELECT Ingredient__c, Ingredient__r.Name, Current_Price__c, Updated_Date__c
            FROM Commodity_Price__c
            WHERE Ingredient__c IN :ingredientIds
            ORDER BY Updated_Date__c DESC NULLS LAST, CreatedDate DESC
        ]) {
            if (!latest.containsKey(price.Ingredient__c)) {
                latest.put(price.Ingredient__c, price);
            }
        }

        for (Id ingredientId : latest.keySet()) {
            Commodity_Price__c p = latest.get(ingredientId);
            CommodityPriceView dto = new CommodityPriceView();
            dto.ingredientId = ingredientId;
            dto.ingredientName = p.Ingredient__r != null ? p.Ingredient__r.Name : null;
            dto.currentPrice = p.Current_Price__c;
            dto.updatedDate = p.Updated_Date__c;
            result.add(dto);
        }
        return result;
    }

    @AuraEnabled
    public static AgentRecommendationResult getAgentRecommendations(Id productId, String promptText, String agentApiName) {
        if (productId == null) {
            throw new AuraHandledException('Product is required.');
        }
        String effectivePrompt = String.isBlank(promptText)
            ? 'Reduce total recipe cost by 10% while maintaining similar flavor profile.'
            : promptText;

        RecipeSummary summary = calculateCost(productId);
        List<RecipeLineView> lines = getRecipe(productId);
        List<CommodityPriceView> prices = getCommodityPrices(productId);

        Map<String, Object> contextPayload = new Map<String, Object>{
            'prompt' => effectivePrompt,
            'totalCost' => summary.totalCost,
            'totalQuantity' => summary.totalQuantity,
            'estimatedMargin' => summary.estimatedMargin,
            'recipeLines' => lines,
            'commodityPrices' => prices,
            'outputFormat' => 'JSON array under key suggestions, each item with ingredientName, suggestedPrice, suggestedQuantity, comment'
        };

        String rawText = invokeAgentforce(agentApiName, contextPayload);
        AgentRecommendationResult result = new AgentRecommendationResult();
        result.rawResponse = rawText;
        result.suggestions = parseSuggestions(rawText, lines, prices);
        return result;
    }

    private static Set<Id> getIngredientIdsForProduct(Id productId) {
        Set<Id> ingredientIds = new Set<Id>();
        for (Recipe_Line__c line : [
            SELECT Ingredient__c
            FROM Recipe_Line__c
            WHERE Product__c = :productId AND Ingredient__c != null
        ]) {
            ingredientIds.add(line.Ingredient__c);
        }
        return ingredientIds;
    }

    private static Map<Id, Decimal> getLatestPriceByIngredient(Id productId) {
        Set<Id> ingredientIds = getIngredientIdsForProduct(productId);
        Map<Id, Decimal> prices = new Map<Id, Decimal>();
        if (ingredientIds.isEmpty()) {
            return prices;
        }

        for (Commodity_Price__c price : [
            SELECT Ingredient__c, Current_Price__c
            FROM Commodity_Price__c
            WHERE Ingredient__c IN :ingredientIds
            ORDER BY Updated_Date__c DESC NULLS LAST, CreatedDate DESC
        ]) {
            if (!prices.containsKey(price.Ingredient__c)) {
                prices.put(price.Ingredient__c, price.Current_Price__c);
            }
        }
        return prices;
    }

    @TestVisible
    private static String invokeAgentforce(String agentApiName, Map<String, Object> payload) {
        String resolvedAgent = String.isBlank(agentApiName) ? 'Recipe_Optimizer_Agent' : agentApiName;
        HttpRequest req = new HttpRequest();
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setEndpoint(
            'callout:Agentforce_NC/services/data/v66.0/agentforce/agents/' + EncodingUtil.urlEncode(resolvedAgent, 'UTF-8') + '/invocations'
        );
        req.setBody(JSON.serialize(payload));

        try {
            HttpResponse res = new Http().send(req);
            if (res.getStatusCode() >= 200 && res.getStatusCode() < 300) {
                Map<String, Object> responseBody = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                if (responseBody.containsKey('outputText')) {
                    return (String) responseBody.get('outputText');
                }
                return res.getBody();
            }
            return 'Agentforce call failed: ' + res.getStatusCode() + ' - ' + res.getBody();
        } catch (Exception ex) {
            return 'Agentforce endpoint is not configured yet. Configure Named Credential "Agentforce_NC". Error: ' + ex.getMessage();
        }
    }

    @TestVisible
    private static List<AgentIngredientSuggestion> parseSuggestions(
        String rawText,
        List<RecipeLineView> lines,
        List<CommodityPriceView> prices
    ) {
        List<AgentIngredientSuggestion> result = new List<AgentIngredientSuggestion>();
        Map<String, Id> ingredientIdByName = new Map<String, Id>();
        Map<Id, Decimal> priceByIngredient = new Map<Id, Decimal>();
        for (RecipeLineView line : lines) {
            if (!String.isBlank(line.ingredientName)) {
                ingredientIdByName.put(line.ingredientName.toLowerCase(), line.ingredientId);
            }
        }
        for (CommodityPriceView p : prices) {
            if (p.ingredientId != null) {
                priceByIngredient.put(p.ingredientId, p.currentPrice);
            }
        }

        try {
            Object parsed = JSON.deserializeUntyped(rawText);
            if (parsed instanceof Map<String, Object>) {
                Map<String, Object> mapValue = (Map<String, Object>) parsed;
                if (mapValue.containsKey('suggestions') && mapValue.get('suggestions') instanceof List<Object>) {
                    for (Object rowObj : (List<Object>) mapValue.get('suggestions')) {
                        if (!(rowObj instanceof Map<String, Object>)) {
                            continue;
                        }
                        Map<String, Object> row = (Map<String, Object>) rowObj;
                        AgentIngredientSuggestion s = new AgentIngredientSuggestion();
                        String ingredientName = (String) row.get('ingredientName');
                        s.ingredientName = ingredientName;
                        if (!String.isBlank(ingredientName) && ingredientIdByName.containsKey(ingredientName.toLowerCase())) {
                            s.ingredientId = ingredientIdByName.get(ingredientName.toLowerCase());
                        }
                        s.suggestedPrice = toDecimal(row.get('suggestedPrice'));
                        s.suggestedQuantity = toDecimal(row.get('suggestedQuantity'));
                        s.comment = (String) row.get('comment');
                        result.add(s);
                    }
                }
            }
        } catch (Exception ex) {
            // Fall through to deterministic fallback suggestions.
        }

        if (!result.isEmpty()) {
            return result;
        }

        for (RecipeLineView line : lines) {
            AgentIngredientSuggestion fallback = new AgentIngredientSuggestion();
            fallback.ingredientId = line.ingredientId;
            fallback.ingredientName = line.ingredientName;
            Decimal currentPrice = priceByIngredient.containsKey(line.ingredientId) ? priceByIngredient.get(line.ingredientId) : 0;
            fallback.suggestedPrice = currentPrice > 0 ? currentPrice * 0.95 : null;
            fallback.suggestedQuantity = line.quantity == null ? null : line.quantity * 0.95;
            fallback.comment =
                'AI response was unstructured. Suggested 5% optimization based on current values. Raw response: ' +
                rawText;
            result.add(fallback);
        }
        return result;
    }

    private static Decimal toDecimal(Object value) {
        if (value == null) {
            return null;
        }
        if (value instanceof Decimal) {
            return (Decimal) value;
        }
        return Decimal.valueOf(String.valueOf(value));
    }
}