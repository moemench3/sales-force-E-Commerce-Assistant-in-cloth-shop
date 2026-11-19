public with sharing class AgentChatController {

    private static final String CLIENT_ID = 'YOUR_SALESFORCE_CONSUMER_KEY';
    private static final String CLIENT_SECRET = 'YOUR_SALESFORCE_CONSUMER_SECRET';
    private static final String MY_DOMAIN = 'https://moemen-dev-ed.develop.my.salesforce.com';
    private static final String AGENT_API_NAME = 'Store_Assistant_Agent';

    public class AgentException extends Exception {}

    // Wrapper Class returned to LWC for Chat
    public class ChatResponse {
        @AuraEnabled public String reply;
        @AuraEnabled public String sessionId;
        @AuraEnabled public List<Map<String, Object>> products;

        public ChatResponse(String reply, String sessionId, List<Map<String, Object>> products) {
            this.reply = reply;
            this.sessionId = sessionId;
            this.products = products;
        }
    }

    // Wrapper Class returned to LWC for User Orders History
    public class OrderHistoryWrapper {
        @AuraEnabled public String id;
        @AuraEnabled public String orderNumber;
        @AuraEnabled public String orderDate;
        @AuraEnabled public Decimal totalAmount;
        @AuraEnabled public String status;
        @AuraEnabled public List<Map<String, Object>> items;

        public OrderHistoryWrapper(Order ord, List<OrderItem> orderItems) {
            this.id = ord.Id;
            this.orderNumber = ord.OrderNumber != null ? ord.OrderNumber : ord.Id;
            this.orderDate = ord.EffectiveDate != null ? String.valueOf(ord.EffectiveDate) : String.valueOf(Date.today());
            this.totalAmount = ord.TotalAmount != null ? ord.TotalAmount : 0;
            this.status = ord.Status;
            this.items = new List<Map<String, Object>>();

            if (orderItems != null) {
                for (OrderItem item : orderItems) {
                    this.items.add(new Map<String, Object>{
                        'name' => item.Product2.Name,
                        'code' => item.Product2.ProductCode,
                        'quantity' => item.Quantity,
                        'unitPrice' => item.UnitPrice,
                        'totalPrice' => item.TotalPrice
                    });
                }
            }
        }
    }

    // 1. Fetch User Orders directly from Salesforce Database (Solves Deployment Error)
    @AuraEnabled(cacheable=true)
    public static List<OrderHistoryWrapper> getUserOrders() {
        List<OrderHistoryWrapper> orderList = new List<OrderHistoryWrapper>();
        try {
            Id accId = getOrCreateAccountId();
            List<Order> orders = [
                SELECT Id, OrderNumber, EffectiveDate, TotalAmount, Status,
                       (SELECT Id, Quantity, UnitPrice, TotalPrice, Product2.Name, Product2.ProductCode FROM OrderItems)
                FROM Order 
                WHERE AccountId = :accId 
                ORDER BY CreatedDate DESC 
                LIMIT 50
            ];

            for (Order ord : orders) {
                orderList.add(new OrderHistoryWrapper(ord, ord.OrderItems));
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error fetching user orders: ' + e.getMessage());
        }
        return orderList;
    }

    // Helper method to extract pure clean text from any JSON wrapper or raw string
    private static String extractCleanMessage(String rawOutput) {
    if (String.isBlank(rawOutput)) {
        return '';
    }

    String trimmed = rawOutput.trim();
    if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
        try {
            Map<String, Object> innerMap = (Map<String, Object>) JSON.deserializeUntyped(trimmed);
            if (innerMap.containsKey('value') && innerMap.get('value') != null) {
                return String.valueOf(innerMap.get('value'));
            } else if (innerMap.containsKey('text') && innerMap.get('text') != null) {
                return String.valueOf(innerMap.get('text'));
            }
        } catch (Exception e) {
            System.debug('JSON unpack skipped: ' + e.getMessage());
        }
    }
    return rawOutput;
}

    // Native Agentforce Invocation
    @AuraEnabled
    public static Map<String, String> sendMessageToSession(String agentApiName, String userMessage, String sessionId) {
        Map<String, String> resultMap = new Map<String, String>();
        try {
            String targetAgent = String.isNotBlank(agentApiName) ? agentApiName : AGENT_API_NAME;
            
            Invocable.Action action = Invocable.Action.createCustomAction('generateAiAgentResponse', targetAgent);
            action.setInvocationParameter('userMessage', userMessage);
            
            if (String.isNotBlank(sessionId)) {
                action.setInvocationParameter('sessionId', sessionId);
            }

            List<Invocable.Action.Result> results = action.invoke();

            if (!results.isEmpty() && results[0].isSuccess()) {
                Invocable.Action.Result res = results[0];
                
                Object agentOutputRaw = res.getOutputParameters().get('agentOutput');
                if (agentOutputRaw == null) {
                    agentOutputRaw = res.getOutputParameters().get('agentResponse');
                }

                String resSessionId = (String) res.getOutputParameters().get('sessionId');
                String cleanReply = extractCleanMessage(String.valueOf(agentOutputRaw));

                resultMap.put('reply', cleanReply);
                resultMap.put('sessionId', resSessionId);
                return resultMap;
            } else if (!results.isEmpty() && !results[0].getErrors().isEmpty()) {
                throw new AuraHandledException('Agentforce Error: ' + results[0].getErrors()[0].getMessage());
            } else {
                throw new AuraHandledException('Unknown error occurred while invoking Agentforce Agent.');
            }

        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Invocable Action Failed: ' + e.getMessage() + ' -> Falling back to REST');
            return sendMessageToSessionREST(agentApiName, userMessage, sessionId);
        }
    }

    // REST API Endpoint Fallback
    public static Map<String, String> sendMessageToSessionREST(String agentApiName, String userMessage, String sessionId) {
        Map<String, String> resultMap = new Map<String, String>();
        try {
            String validToken = getAccessToken();
            String targetAgent = String.isNotBlank(agentApiName) ? agentApiName : AGENT_API_NAME;
            String endpoint = MY_DOMAIN + '/services/data/v62.0/actions/custom/generateAiAgentResponse/' + targetAgent;

            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setHeader('Authorization', 'Bearer ' + validToken);
            req.setTimeout(120000);

            Map<String, Object> singleInput = new Map<String, Object>{ 'userMessage' => userMessage };

            if (String.isNotBlank(sessionId)) {
                singleInput.put('sessionId', sessionId);
            }

            Map<String, Object> payload = new Map<String, Object>{
                'inputs' => new List<Map<String, Object>>{ singleInput }
            };

            req.setBody(JSON.serialize(payload));

            Http http = new Http();
            HttpResponse res = http.send(req);

            if (res.getStatusCode() == 200) {
                resultMap = parseAgentResponseBody(res.getBody());
                return resultMap;
            } else {
                throw new AuraHandledException('Agent API Error (' + res.getStatusCode() + '): ' + res.getBody());
            }

        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Error sending message via REST API: ' + e.getMessage());
        }
    }

    private static String getAccessToken() {
        try {
            HttpRequest tokenReq = new HttpRequest();
            tokenReq.setEndpoint(MY_DOMAIN + '/services/oauth2/token');
            tokenReq.setMethod('POST');
            tokenReq.setHeader('Content-Type', 'application/x-www-form-urlencoded');
            tokenReq.setTimeout(60000);           

            String body = 'grant_type=client_credentials'
                + '&client_id=' + EncodingUtil.urlEncode(CLIENT_ID, 'UTF-8')
                + '&client_secret=' + EncodingUtil.urlEncode(CLIENT_SECRET, 'UTF-8');
            tokenReq.setBody(body);

            Http http = new Http();
            HttpResponse tokenRes = http.send(tokenReq);

            if (tokenRes.getStatusCode() != 200) {
                throw new AgentException('OAuth Token Failed [' + tokenRes.getStatusCode() + ']: ' + tokenRes.getBody());
            }

            Map<String, Object> tokenMap = (Map<String, Object>) JSON.deserializeUntyped(tokenRes.getBody());
            return (String) tokenMap.get('access_token');
        } catch (Exception e) {
            throw new AuraHandledException('Authentication error: ' + e.getMessage());
        }
    }

    // Main LWC Method called from Javascript
    @AuraEnabled
public static String sendMessageToAgent(String userMessage, String sessionId, String cartJson) {
    try {
        // نترك قائمة matchedProducts فارغة حتى يتعاطى الـ LWC حصراً مع مخرجات الـ Agent الديناميكية
        List<Map<String, Object>> matchedProducts = new List<Map<String, Object>>();

        Map<String, String> agentResult = sendMessageToSession(AGENT_API_NAME, userMessage, sessionId);
        
        String agentReplyText = agentResult.get('reply');
        String returnedSessionId = agentResult.get('sessionId');

        return JSON.serialize(new ChatResponse(
            agentReplyText, 
            String.isNotBlank(returnedSessionId) ? returnedSessionId : (String.isNotBlank(sessionId) ? sessionId : 'active-session'), 
            matchedProducts
        ));

    } catch (AuraHandledException e) {
        throw e;
    } catch (Exception e) {
        System.debug(LoggingLevel.ERROR, 'Error in sendMessageToAgent: ' + e.getMessage() + ' | Line: ' + e.getLineNumber());
        throw new AuraHandledException('Failed to process message: ' + e.getMessage());
    }
}

    private static Map<String, String> parseAgentResponseBody(String responseBody) {
        Map<String, String> parsedResult = new Map<String, String>();
        parsedResult.put('reply', '');
        parsedResult.put('sessionId', '');

        try {
            List<Object> responseList = (List<Object>) JSON.deserializeUntyped(responseBody);
            if (!responseList.isEmpty()) {
                Map<String, Object> firstItem = (Map<String, Object>) responseList[0];
                Boolean isSuccess = (Boolean) firstItem.get('isSuccess');
                
                if (isSuccess != null && isSuccess) {
                    Map<String, Object> outputValues = (Map<String, Object>) firstItem.get('outputValues');
                    if (outputValues != null) {
                        if (outputValues.containsKey('sessionId')) {
                            parsedResult.put('sessionId', String.valueOf(outputValues.get('sessionId')));
                        }

                        Object rawAgentMsg = null;
                        if (outputValues.containsKey('agentOutput')) {
                            rawAgentMsg = outputValues.get('agentOutput');
                        } else if (outputValues.containsKey('agentResponse')) {
                            rawAgentMsg = outputValues.get('agentResponse');
                        }

                        if (rawAgentMsg != null) {
                            parsedResult.put('reply', extractCleanMessage(String.valueOf(rawAgentMsg)));
                        }
                    }
                }
            }
        } catch (Exception e) {
            System.debug('Parsing Agent Response Failed: ' + e.getMessage());
            parsedResult.put('reply', responseBody);
        }
        return parsedResult;
    }

    // Creates Order and OrderItems in Salesforce Database from LWC Cart
@AuraEnabled
public static String createSalesforceOrder(String cartDataJson, String paymentMethod) {
    Savepoint sp = Database.setSavepoint();
    try {
        if (String.isBlank(cartDataJson)) {
            throw new AuraHandledException('Cart data is empty.');
        }

        List<Object> cartItems = (List<Object>) JSON.deserializeUntyped(cartDataJson);
        if (cartItems.isEmpty()) {
            throw new AuraHandledException('Cart has no items.');
        }

        Id accountId = getOrCreateAccountId();
        Pricebook2 stdPricebook = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1];

        Order newOrder = new Order(
            AccountId = accountId,
            EffectiveDate = Date.today(),
            Status = 'Draft',
            Pricebook2Id = stdPricebook.Id,
            Description = 'Order created from LWC Smart Cart Assistant. Payment: ' + paymentMethod
        );
        insert newOrder;

        Set<String> productCodes = new Set<String>();
        for (Object itemObj : cartItems) {
            Map<String, Object> item = (Map<String, Object>) itemObj;
            if (item.containsKey('code')) {
                productCodes.add((String) item.get('code'));
            }
        }

        Map<String, Product2> codeToProductMap = new Map<String, Product2>();
        for (Product2 p : [SELECT Id, ProductCode FROM Product2 WHERE ProductCode IN :productCodes]) {
            codeToProductMap.put(p.ProductCode, p);
        }

        List<Product2> productsToInsert = new List<Product2>();

        for (Object itemObj : cartItems) {
            Map<String, Object> item = (Map<String, Object>) itemObj;
            String pCode = item.containsKey('code') ? (String) item.get('code') : 'GEN-01';
            String pName = item.containsKey('name') ? (String) item.get('name') : 'Store Item';

            if (!codeToProductMap.containsKey(pCode)) {
                Product2 prod = new Product2(Name = pName, ProductCode = pCode, IsActive = true);
                codeToProductMap.put(pCode, prod);
                productsToInsert.add(prod);
            }
        }

        if (!productsToInsert.isEmpty()) {
            insert productsToInsert;
        }

        // الاستعلام عن الـ PricebookEntries الموجودة أصلاً لجميع المنتجات
        Map<Id, PricebookEntry> prodToPbeMap = new Map<Id, PricebookEntry>();
        for (PricebookEntry pbe : [SELECT Id, Product2Id FROM PricebookEntry WHERE Pricebook2Id = :stdPricebook.Id AND Product2Id IN :codeToProductMap.values()]) {
            prodToPbeMap.put(pbe.Product2Id, pbe);
        }

        // إنشاء PricebookEntry لأي منتج لا يملك PricebookEntry مسجل في Standard Pricebook
        List<PricebookEntry> newPbes = new List<PricebookEntry>();
        for (Product2 prod : codeToProductMap.values()) {
            if (!prodToPbeMap.containsKey(prod.Id)) {
                PricebookEntry newPbe = new PricebookEntry(
                    Pricebook2Id = stdPricebook.Id,
                    Product2Id = prod.Id,
                    UnitPrice = 0,
                    IsActive = true
                );
                newPbes.add(newPbe);
            }
        }

        if (!newPbes.isEmpty()) {
            insert newPbes;
            for (PricebookEntry pbe : newPbes) {
                prodToPbeMap.put(pbe.Product2Id, pbe);
            }
        }

        List<OrderItem> orderItemsToInsert = new List<OrderItem>();
        for (Object itemObj : cartItems) {
            Map<String, Object> item = (Map<String, Object>) itemObj;
            String pCode = item.containsKey('code') ? (String) item.get('code') : 'GEN-01';
            Decimal pPrice = Decimal.valueOf(String.valueOf(item.get('price')));
            Integer pQty = Integer.valueOf(String.valueOf(item.get('quantity')));

            Product2 p = codeToProductMap.get(pCode);
            PricebookEntry pbe = prodToPbeMap.get(p.Id);

            orderItemsToInsert.add(new OrderItem(
                OrderId = newOrder.Id,
                PricebookEntryId = pbe.Id,
                Quantity = pQty,
                UnitPrice = pPrice
            ));
        }

        insert orderItemsToInsert;
        return newOrder.Id;

    } catch (Exception e) {
        Database.rollback(sp);
        throw new AuraHandledException('Error creating order: ' + e.getMessage());
    }
}

    private static Id getOrCreateAccountId() {
        List<Account> accs = [SELECT Id FROM Account LIMIT 1];
        if (!accs.isEmpty()) {
            return accs[0].Id;
        }
        Account defaultAcc = new Account(Name = 'E-Commerce Guest Customer');
        insert defaultAcc;
        return defaultAcc.Id;
    }

    private static List<Map<String, Object>> getStaticProducts() {
        return new List<Map<String, Object>>{
            new Map<String, Object>{'id'=>'p1', 'name'=>'Classic Cotton T-Shirt', 'code'=>'002044', 'category'=>'shirt', 'price'=>35.00, 'imageUrl'=>'/resource/p1', 'description'=>'Comfortable 100% cotton casual t-shirt.'},
            new Map<String, Object>{'id'=>'p2', 'name'=>'Casual Polo Shirt', 'code'=>'002047', 'category'=>'shirt', 'price'=>55.00, 'imageUrl'=>'/resource/p2', 'description'=>'Classic style polo shirt for everyday wear.'},
            new Map<String, Object>{'id'=>'p4', 'name'=>'Denim Button-Up Shirt', 'code'=>'002051', 'category'=>'shirt', 'price'=>75.00, 'imageUrl'=>'/resource/p4', 'description'=>'Stylish denim shirt with long sleeves.'},
            new Map<String, Object>{'id'=>'p5', 'name'=>'Linen Summer Beach Shirt', 'code'=>'002053', 'category'=>'shirt', 'price'=>80.00, 'imageUrl'=>'/resource/p5', 'description'=>'Lightweight linen shirt for warm days.'},
            new Map<String, Object>{'id'=>'p6', 'name'=>'Winter Heavy Fleece Sweatshirt', 'code'=>'002049', 'category'=>'shirt', 'price'=>110.00, 'imageUrl'=>'/resource/p6', 'description'=>'Warm fleece sweatshirt for cold weather.'},
            new Map<String, Object>{'id'=>'p7', 'name'=>'Relaxed Fit Jogger Pants', 'code'=>'002057', 'category'=>'pant', 'price'=>45.00, 'imageUrl'=>'/resource/p7', 'description'=>'Soft jogger pants with elastic waist.'},
            new Map<String, Object>{'id'=>'p8', 'name'=>'Classic Slim Fit Jeans', 'code'=>'002054', 'category'=>'pant', 'price'=>60.00, 'imageUrl'=>'/resource/p8', 'description'=>'Durable stretch denim slim fit jeans.'},
            new Map<String, Object>{'id'=>'p9', 'name'=>'Cargo Tactical Pants', 'code'=>'002055', 'category'=>'pant', 'price'=>70.00, 'imageUrl'=>'/resource/p9', 'description'=>'Multi-pocket utility tactical pants.'},
            new Map<String, Object>{'id'=>'p10', 'name'=>'Casual Chino Trousers', 'code'=>'002056', 'category'=>'pant', 'price'=>85.00, 'imageUrl'=>'/resource/p10', 'description'=>'Smart casual chino trousers.'},
            new Map<String, Object>{'id'=>'p12', 'name'=>'Urban Canvas Sneakers', 'code'=>'002041', 'category'=>'shoe', 'price'=>40.00, 'imageUrl'=>'/resource/p12', 'description'=>'Classic low-top canvas sneakers.'},
            new Map<String, Object>{'id'=>'p13', 'name'=>'Adidas Running Shoes', 'code'=>'002043', 'category'=>'shoe', 'price'=>90.00, 'imageUrl'=>'/resource/p13', 'description'=>'High performance cushioned running shoes.'},
            new Map<String, Object>{'id'=>'p14', 'name'=>'Nike Air Max Sport', 'code'=>'002042', 'category'=>'shoe', 'price'=>120.00, 'imageUrl'=>'/resource/p14', 'description'=>'Comfortable athletic sports shoes.'},
            new Map<String, Object>{'id'=>'p15', 'name'=>'Leather Formal Shoes', 'code'=>'002045', 'category'=>'shoe', 'price'=>150.00, 'imageUrl'=>'/resource/p15', 'description'=>'Elegant genuine leather formal shoes.'}
        };
    }

    // Invocable Action for Agentforce Order Creation
    public class OrderItemInput {
        @InvocableVariable(label='Product Code' required=true) public String code;
        @InvocableVariable(label='Product Name' required=true) public String name;
        @InvocableVariable(label='Unit Price' required=true) public Decimal price;
        @InvocableVariable(label='Quantity' required=true) public Integer quantity;
    }

    public class PlaceOrderRequest {
        @InvocableVariable(label='Cart Items' required=true) public List<OrderItemInput> cartItems;
    }

    public class PlaceOrderResult {
        @InvocableVariable(label='Order Id') public String orderId;
        @InvocableVariable(label='Success') public Boolean success;
        @InvocableVariable(label='Message') public String message;
    }

    @InvocableMethod(label='Place Store Order' description='Creates a Salesforce Order and Order Items from a customer cart')
    public static List<PlaceOrderResult> placeOrder(List<PlaceOrderRequest> requests) {
        List<PlaceOrderResult> results = new List<PlaceOrderResult>();

        for (PlaceOrderRequest request : requests) {
            PlaceOrderResult result = new PlaceOrderResult();
            Savepoint sp = Database.setSavepoint();
            try {
                if (request.cartItems == null || request.cartItems.isEmpty()) {
                    result.success = false;
                    result.message = 'Cart is empty.';
                    results.add(result);
                    continue;
                }

                Id accountId = getOrCreateAccountId();
                Pricebook2 stdPricebook = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1];

                Order newOrder = new Order(
                    AccountId = accountId,
                    EffectiveDate = Date.today(),
                    Status = 'Draft',
                    Pricebook2Id = stdPricebook.Id,
                    Description = 'Order created from Agentforce chat'
                );
                insert newOrder;

                result.orderId = newOrder.Id;
                result.success = true;
                result.message = 'Order placed successfully.';
            } catch (Exception e) {
                Database.rollback(sp);
                result.success = false;
                result.message = 'Error placing order via Invocable: ' + e.getMessage();
            }
            results.add(result);
        }

        return results;
    }
}