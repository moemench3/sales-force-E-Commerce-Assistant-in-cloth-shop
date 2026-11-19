/**
 * Builds schema catalogs for the Negoptim SOQL Assistant / SOQL Builder agent.
 * Invocable GetSchema returns JSON (objects, fields, relationships, picklists, limits).
 * Also used to inject a compact catalog into LWC → agent messages.
 */
public with sharing class SoqlSchemaCatalog {
    @TestVisible
    private static final Integer MAX_OBJECTS = 80;
    @TestVisible
    private static final Integer MAX_FIELDS_PER_OBJECT = 60;
    @TestVisible
    private static final Integer MAX_CATALOG_CHARS = 120000;
    @TestVisible
    private static final Integer DEFAULT_LIMIT = 100;
    @TestVisible
    private static final Integer MAX_LIMIT = 1000;
    @TestVisible
    private static final Integer MAX_RUNTIME_MS = 10000;
    @TestVisible
    private static final Boolean EXECUTE_BY_DEFAULT = false;

    private static final Set<String> EXCLUDED_SUFFIXES = new Set<String>{
        '__mdt',
        '__e',
        '__b',
        '__x',
        '__hd',
        '__xo',
        '__dlm'
    };

    /** High-volume / sensitive objects blocked for SOQL Builder (adjustable). */
    @TestVisible
    private static final Set<String> EXCLUDED_OBJECTS = new Set<String>{
        'EmailMessage',
        'ContentDocument',
        'ContentVersion',
        'ContentDocumentLink',
        'LoginHistory',
        'LoginIp',
        'AsyncApexJob',
        'ApexLog'
    };

    public class Request {
        @InvocableVariable(
            label='Object Names'
            description='Optional comma-separated object API names to describe. Blank = compact list of allowed objects.'
        )
        public String objectNames;
    }

    public class Response {
        @InvocableVariable(label='Schema JSON' description='JSON catalog: config, objects, fields, relationships, picklists')
        public String schemaJson;
    }

    @InvocableMethod(
        label='Get SOQL Schema Catalog'
        description='Returns org metadata for SOQL building: objects, fields, relationships, picklists, and safety limits.'
    )
    public static List<Response> getSchema(List<Request> requests) {
        List<Response> responses = new List<Response>();
        if (requests == null || requests.isEmpty()) {
            Response empty = new Response();
            empty.schemaJson = buildSchemaJson(null);
            responses.add(empty);
            return responses;
        }
        for (Request req : requests) {
            Response res = new Response();
            res.schemaJson = buildSchemaJson(req != null ? req.objectNames : null);
            responses.add(res);
        }
        return responses;
    }

    /**
     * Human-readable catalog for agent System Context (LWC path).
     */
    public static String buildCatalogText() {
        Map<String, Set<String>> schema = buildSchemaMap();
        List<String> objectNames = new List<String>(schema.keySet());
        objectNames.sort();

        List<String> lines = new List<String>();
        lines.add('ALLOWED SCHEMA (use ONLY these objects and fields; do not invent names):');
        Integer objectCount = 0;
        for (String apiName : objectNames) {
            if (objectCount >= MAX_OBJECTS) {
                lines.add('... catalog truncated: more objects exist but were omitted for size limits.');
                break;
            }
            Set<String> fields = schema.get(apiName);
            List<String> fieldList = new List<String>(fields);
            fieldList.sort();
            if (fieldList.size() > MAX_FIELDS_PER_OBJECT) {
                List<String> clipped = new List<String>();
                for (Integer i = 0; i < MAX_FIELDS_PER_OBJECT; i++) {
                    clipped.add(fieldList[i]);
                }
                fieldList = clipped;
                fieldList.add('/* +more fields omitted */');
            }
            lines.add('- ' + apiName + ': ' + String.join(fieldList, ', '));
            objectCount++;
        }

        String text = String.join(lines, '\n');
        if (text.length() > MAX_CATALOG_CHARS) {
            text = text.substring(0, MAX_CATALOG_CHARS) + '\n... catalog truncated for size.';
        }
        return text;
    }

    /**
     * JSON schema for GetSchema invocable / SOQL Builder tool.
     */
    public static String buildSchemaJson(String objectNamesCsv) {
        Map<String, Object> root = new Map<String, Object>();
        root.put('success', true);
        root.put('config', buildConfigMap());
        root.put('excludedObjects', new List<String>(EXCLUDED_OBJECTS));

        Set<String> filter = parseObjectFilter(objectNamesCsv);
        List<Map<String, Object>> objects = new List<Map<String, Object>>();

        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
        List<String> keys = new List<String>(globalDescribe.keySet());
        keys.sort();

        Integer objectCount = 0;
        for (String key : keys) {
            if (objectCount >= MAX_OBJECTS) {
                root.put('truncated', true);
                break;
            }
            Schema.SObjectType sType = globalDescribe.get(key);
            if (sType == null) {
                continue;
            }
            Schema.DescribeSObjectResult d = sType.getDescribe();
            String apiName = d.getName();
            if (!d.isAccessible() || !d.isQueryable()) {
                continue;
            }
            if (isExcludedObject(apiName)) {
                continue;
            }
            if (!isObjectAllowed(apiName)) {
                continue;
            }
            if (!filter.isEmpty() && !filter.contains(apiName.toLowerCase())) {
                continue;
            }

            // Detail mode when filtered; compact when listing all
            Boolean detail = !filter.isEmpty();
            objects.add(describeObject(d, detail));
            objectCount++;
        }

        root.put('objects', objects);
        if (!filter.isEmpty() && objects.isEmpty()) {
            root.put('success', false);
            root.put(
                'error',
                'No matching queryable objects for filter. Refine object names or check access.'
            );
        }
        return JSON.serialize(root);
    }

    /**
     * Returns map of ObjectApiName -> set of field API names (compact catalog).
     */
    public static Map<String, Set<String>> buildSchemaMap() {
        Map<String, Set<String>> result = new Map<String, Set<String>>();
        Map<String, Set<String>> cmdtOverrides = loadCmdtFieldOverrides();

        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
        for (String key : globalDescribe.keySet()) {
            Schema.SObjectType sType = globalDescribe.get(key);
            if (sType == null) {
                continue;
            }
            Schema.DescribeSObjectResult d = sType.getDescribe();
            if (!d.isAccessible() || !d.isQueryable()) {
                continue;
            }

            String apiName = d.getName();
            if (isExcludedObject(apiName)) {
                continue;
            }
            if (!isIncludedObject(apiName, cmdtOverrides.containsKey(apiName.toLowerCase()))) {
                continue;
            }

            Set<String> fields = collectAccessibleFields(d, cmdtOverrides.get(apiName.toLowerCase()));
            if (!fields.isEmpty()) {
                result.put(apiName, fields);
            }
        }
        return result;
    }

    public static Boolean isObjectAllowed(String objectApiName) {
        if (String.isBlank(objectApiName)) {
            return false;
        }
        String key = objectApiName.trim();
        if (isExcludedObject(key)) {
            return false;
        }
        Map<String, Set<String>> cmdt = loadCmdtFieldOverrides();
        if (cmdt.containsKey(key.toLowerCase())) {
            return true;
        }
        if (isCustomQueryableName(key)) {
            return true;
        }
        // Standard objects: allow if queryable/accessible and not excluded
        Schema.SObjectType sType = Schema.getGlobalDescribe().get(key);
        if (sType == null) {
            // try lowercase key
            sType = Schema.getGlobalDescribe().get(key.toLowerCase());
        }
        if (sType == null) {
            return false;
        }
        Schema.DescribeSObjectResult d = sType.getDescribe();
        return d.isAccessible() && d.isQueryable();
    }

    public static Boolean isFieldAllowed(String objectApiName, String fieldApiName) {
        if (String.isBlank(objectApiName) || String.isBlank(fieldApiName)) {
            return false;
        }
        Map<String, Set<String>> cmdt = loadCmdtFieldOverrides();
        Set<String> allowed = cmdt.get(objectApiName.toLowerCase());
        if (allowed == null || allowed.isEmpty()) {
            return true;
        }
        String f = fieldApiName.toLowerCase();
        if (f.contains('.')) {
            f = f.substring(f.lastIndexOf('.') + 1);
        }
        return allowed.contains(f) || allowed.contains(fieldApiName.toLowerCase());
    }

    public static Boolean isExcludedObject(String apiName) {
        if (String.isBlank(apiName)) {
            return true;
        }
        return EXCLUDED_OBJECTS.contains(apiName) || EXCLUDED_OBJECTS.contains(apiName.trim());
    }

    public static Integer getDefaultLimit() {
        return DEFAULT_LIMIT;
    }

    public static Integer getMaxLimit() {
        return MAX_LIMIT;
    }

    public static Boolean getExecuteByDefault() {
        return EXECUTE_BY_DEFAULT;
    }

    @TestVisible
    private static Boolean isIncludedObject(String apiName, Boolean listedInCmdt) {
        if (isExcludedObject(apiName)) {
            return false;
        }
        if (listedInCmdt) {
            return true;
        }
        return isCustomQueryableName(apiName);
    }

    @TestVisible
    private static Boolean isCustomQueryableName(String apiName) {
        if (String.isBlank(apiName) || !apiName.endsWith('__c')) {
            return false;
        }
        String lower = apiName.toLowerCase();
        for (String suffix : EXCLUDED_SUFFIXES) {
            if (lower.endsWith(suffix)) {
                return false;
            }
        }
        if (lower.endsWith('__history') || lower.endsWith('__share') || lower.endsWith('__feed')) {
            return false;
        }
        return true;
    }

    /** Cached CMDT field overrides for the transaction (avoids SOQL-in-loop). */
    @TestVisible
    private static Map<String, Set<String>> cmdtOverridesCache;

    public static Map<String, Set<String>> loadCmdtFieldOverrides() {
        if (cmdtOverridesCache != null) {
            return cmdtOverridesCache;
        }
        Map<String, Set<String>> result = new Map<String, Set<String>>();
        try {
            List<SObject> rows = Database.query(
                'SELECT DeveloperName, Object_API_Name__c, Allowed_Fields__c FROM Queryable_Object__mdt'
            );
            for (SObject row : rows) {
                String objectApiName = (String) row.get('Object_API_Name__c');
                if (String.isBlank(objectApiName)) {
                    continue;
                }
                String objKey = objectApiName.trim().toLowerCase();
                Set<String> fields = new Set<String>();
                String allowedFields = (String) row.get('Allowed_Fields__c');
                if (String.isNotBlank(allowedFields)) {
                    for (String part : allowedFields.split(',')) {
                        String f = part != null ? part.trim() : '';
                        if (String.isNotBlank(f)) {
                            fields.add(f.toLowerCase());
                        }
                    }
                }
                result.put(objKey, fields);
            }
        } catch (Exception ex) {
            System.debug(
                LoggingLevel.WARN,
                'SoqlSchemaCatalog.loadCmdtFieldOverrides skipped: ' + ex.getMessage()
            );
        }
        cmdtOverridesCache = result;
        return cmdtOverridesCache;
    }

    public static String buildAgentUserMessage(String userPrompt) {
        String catalog = buildCatalogText();
        return '[System Context: Live Salesforce schema catalog for this org]\n' +
            catalog +
            '\n\n[Agent Preferences]\nexecute=true\n' +
            'default_limit=' +
            String.valueOf(DEFAULT_LIMIT) +
            '\nmax_limit=' +
            String.valueOf(MAX_LIMIT) +
            '\n\n[User Question]\n' +
            (userPrompt == null ? '' : userPrompt.trim());
    }

    private static Map<String, Object> buildConfigMap() {
        Map<String, Object> cfg = new Map<String, Object>();
        cfg.put('execute_by_default', EXECUTE_BY_DEFAULT);
        cfg.put('default_limit', DEFAULT_LIMIT);
        cfg.put('max_limit', MAX_LIMIT);
        cfg.put('max_runtime_ms', MAX_RUNTIME_MS);
        cfg.put('excluded_objects', new List<String>(EXCLUDED_OBJECTS));
        return cfg;
    }

    private static Set<String> parseObjectFilter(String csv) {
        Set<String> filter = new Set<String>();
        if (String.isBlank(csv)) {
            return filter;
        }
        for (String part : csv.split(',')) {
            String n = part != null ? part.trim() : '';
            if (String.isNotBlank(n)) {
                filter.add(n.toLowerCase());
            }
        }
        return filter;
    }

    private static Set<String> collectAccessibleFields(
        Schema.DescribeSObjectResult d,
        Set<String> cmdtFields
    ) {
        Set<String> fields = new Set<String>();
        Map<String, Schema.SObjectField> fieldMap = d.fields.getMap();

        if (cmdtFields != null && !cmdtFields.isEmpty()) {
            for (String f : cmdtFields) {
                Schema.SObjectField sof = fieldMap.containsKey(f)
                    ? fieldMap.get(f)
                    : fieldMap.get(f.toLowerCase());
                if (sof != null && sof.getDescribe().isAccessible()) {
                    fields.add(sof.getDescribe().getName());
                }
            }
            return fields;
        }

        Integer added = 0;
        for (Schema.SObjectField sof : fieldMap.values()) {
            if (added >= MAX_FIELDS_PER_OBJECT) {
                break;
            }
            Schema.DescribeFieldResult fd = sof.getDescribe();
            if (!fd.isAccessible()) {
                continue;
            }
            if (fd.getType() == Schema.DisplayType.ADDRESS || fd.getType() == Schema.DisplayType.LOCATION) {
                continue;
            }
            fields.add(fd.getName());
            added++;
        }
        return fields;
    }

    private static Map<String, Object> describeObject(Schema.DescribeSObjectResult d, Boolean detail) {
        Map<String, Object> obj = new Map<String, Object>();
        obj.put('apiName', d.getName());
        obj.put('label', d.getLabel());
        obj.put('custom', d.isCustom());

        if (!detail) {
            obj.put('fieldCount', d.fields.getMap().size());
            obj.put('hint', 'Pass objectNames to GetSchema for field/relationship/picklist detail.');
            return obj;
        }

        Map<String, Set<String>> cmdt = loadCmdtFieldOverrides();
        Set<String> cmdtFields = cmdt.get(d.getName().toLowerCase());
        List<Map<String, Object>> fieldInfos = new List<Map<String, Object>>();
        List<Map<String, Object>> relationships = new List<Map<String, Object>>();
        Integer added = 0;

        for (Schema.SObjectField sof : d.fields.getMap().values()) {
            if (added >= MAX_FIELDS_PER_OBJECT) {
                obj.put('fieldsTruncated', true);
                break;
            }
            Schema.DescribeFieldResult fd = sof.getDescribe();
            if (!fd.isAccessible()) {
                continue;
            }
            if (cmdtFields != null && !cmdtFields.isEmpty()) {
                if (!cmdtFields.contains(fd.getName().toLowerCase())) {
                    continue;
                }
            }
            if (fd.getType() == Schema.DisplayType.ADDRESS || fd.getType() == Schema.DisplayType.LOCATION) {
                continue;
            }

            Map<String, Object> fi = new Map<String, Object>();
            fi.put('apiName', fd.getName());
            fi.put('label', fd.getLabel());
            fi.put('type', String.valueOf(fd.getType()));
            fi.put('filterable', fd.isFilterable());
            fi.put('sortable', fd.isSortable());
            fi.put('nillable', fd.isNillable());

            if (fd.getType() == Schema.DisplayType.PICKLIST || fd.getType() == Schema.DisplayType.MULTIPICKLIST) {
                List<String> vals = new List<String>();
                for (Schema.PicklistEntry pe : fd.getPicklistValues()) {
                    if (pe.isActive()) {
                        vals.add(pe.getValue());
                    }
                    if (vals.size() >= 40) {
                        break;
                    }
                }
                fi.put('picklistValues', vals);
            }

            List<Schema.SObjectType> refs = fd.getReferenceTo();
            if (refs != null && !refs.isEmpty()) {
                List<String> refNames = new List<String>();
                for (Schema.SObjectType rt : refs) {
                    refNames.add(rt.getDescribe().getName());
                }
                fi.put('referenceTo', refNames);
                Map<String, Object> rel = new Map<String, Object>();
                rel.put('field', fd.getName());
                rel.put('relationshipName', fd.getRelationshipName());
                rel.put('referenceTo', refNames);
                rel.put('type', 'lookup');
                relationships.add(rel);
            }

            fieldInfos.add(fi);
            added++;
        }

        obj.put('fields', fieldInfos);
        obj.put('relationships', relationships);
        return obj;
    }
}