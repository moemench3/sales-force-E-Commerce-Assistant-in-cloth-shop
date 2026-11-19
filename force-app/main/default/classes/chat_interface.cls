public with sharing class AgentChatController {

    private static final String CLIENT_ID = 'YOUR_SALESFORCE_CONSUMER_KEY';
    private static final String CLIENT_SECRET = 'YOUR_SALESFORCE_CONSUMER_SECRET';
    
    // استخدام الـ Agent ID الصحيح من الشاشة
    private static final String AGENT_ID = 'youre agent id here';
    private static final String MY_DOMAIN = URL.getOrgDomainUrl().toExternalForm();

    public class ChatResponse {
        public String reply;
        public String sessionId;
        public List<Map<String, Object>> products;

        public ChatResponse(String reply, String sessionId, List<Map<String, Object>> products) {
            this.reply = reply;
            this.sessionId = sessionId;
            this.products = products;
        }
    }

    private static String getAccessToken() {
        HttpRequest tokenReq = new HttpRequest();
        tokenReq.setEndpoint(MY_DOMAIN + '/services/oauth2/token');
        tokenReq.setMethod('POST');
        tokenReq.setHeader('Content-Type', 'application/x-www-form-urlencoded');

        String body = 'grant_type=client_credentials'
            + '&client_id=' + EncodingUtil.urlEncode(CLIENT_ID, 'UTF-8')
            + '&client_secret=' + EncodingUtil.urlEncode(CLIENT_SECRET, 'UTF-8');
        tokenReq.setBody(body);

        Http http = new Http();
        HttpResponse tokenRes = http.send(tokenReq);

        if (tokenRes.getStatusCode() != 200) {
            throw new AuraHandledException('OAuth Error [' + tokenRes.getStatusCode() + ']: ' + tokenRes.getBody());
        }

        Map<String, Object> tokenMap = (Map<String, Object>) JSON.deserializeUntyped(tokenRes.getBody());
        return (String) tokenMap.get('access_token');
    }

    @AuraEnabled
    public static String sendMessageToAgent(String userMessage, String sessionId, String cartJson) {
        String lowerMsg = userMessage != null ? userMessage.toLowerCase().trim() : '';
        List<Map<String, Object>> matchedProducts = new List<Map<String, Object>>();

        String targetCategory = null;
        if (lowerMsg.contains('shirt') || lowerMsg.contains('t-shirt') || lowerMsg.contains('polo') || lowerMsg.contains('sweatshirt')) {
            targetCategory = 'shirt';
        } else if (lowerMsg.contains('pant') || lowerMsg.contains('jean') || lowerMsg.contains('jogger') || lowerMsg.contains('trouser')) {
            targetCategory = 'pant';
        } else if (lowerMsg.contains('shoe') || lowerMsg.contains('sneaker') || lowerMsg.contains('adidas') || lowerMsg.contains('nike')) {
            targetCategory = 'shoe';
        }

        if (targetCategory != null) {
            for (Product2 p : [SELECT Id, Name, ProductCode, Family, Description FROM Product2 WHERE Family = :targetCategory AND IsActive = true LIMIT 10]) {
                matchedProducts.add(new Map<String, Object>{
                    'id' => p.Id,
                    'name' => p.Name,
                    'code' => p.ProductCode,
                    'category' => p.Family,
                    'description' => p.Description
                });
            }
        }

        if (String.isBlank(sessionId)) {
            sessionId = startAgentSession();
        }

        String agentReplyText = sendMessageToSession(sessionId, userMessage);
        return JSON.serialize(new ChatResponse(agentReplyText, sessionId, matchedProducts));
    }

    private static String startAgentSession() {
        String validToken = getAccessToken();
        
        // Use org-specific endpoint with correct API path
        String endpoint = MY_DOMAIN + '/services/data/v60.0/einstein/ai-agent/agents/' + AGENT_ID + '/sessions';

        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('Authorization', 'Bearer ' + validToken);

        Map<String, Object> payload = new Map<String, Object>{
            'externalSessionKey' => generateUuid()
        };
        
        req.setBody(JSON.serialize(payload));
        req.setTimeout(30000);

        Http http = new Http();
        HttpResponse res = http.send(req);

        System.debug('Session Status: ' + res.getStatusCode());
        System.debug('Session Body: ' + res.getBody());

        if (res.getStatusCode() != 200 && res.getStatusCode() != 201) {
            throw new AuraHandledException('Session Error [' + res.getStatusCode() + ']: ' + res.getBody());
        }

        Map<String, Object> resMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        return (String) resMap.get('sessionId');
    }

    private static String sendMessageToSession(String sessionId, String userMessage) {
        String validToken = getAccessToken();

        String endpoint = MY_DOMAIN + '/services/data/v60.0/einstein/ai-agent/sessions/' + sessionId + '/messages';

        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('Authorization', 'Bearer ' + validToken);

        req.setBody(JSON.serialize(new Map<String, Object>{ 'text' => userMessage }));
        req.setTimeout(30000);

        Http http = new Http();
        HttpResponse res = http.send(req);

        System.debug('Message Status: ' + res.getStatusCode());
        System.debug('Message Body: ' + res.getBody());

        if (res.getStatusCode() != 200 && res.getStatusCode() != 201) {
            throw new AuraHandledException('Message Error [' + res.getStatusCode() + ']: ' + res.getBody());
        }

        Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        List<Object> messages = (List<Object>) responseMap.get('messages');
        if (messages != null && !messages.isEmpty()) {
            Map<String, Object> firstMsg = (Map<String, Object>) messages[0];
            Object msgObj = firstMsg.get('message');
            if (msgObj instanceof Map<String, Object>) {
                return (String) ((Map<String, Object>) msgObj).get('text');
            }
            return (String) firstMsg.get('text');
        }
        return 'لم يتم استلام نص من العميل الذكي.';
    }

    private static String generateUuid() {
        Blob b = Crypto.generateAesKey(128);
        String h = EncodingUtil.convertToHex(b);
        return h.substring(0,8) + '-' + h.substring(8,12) + '-' + h.substring(12,16) + '-' + h.substring(16,20) + '-' + h.substring(20);
    }
}
