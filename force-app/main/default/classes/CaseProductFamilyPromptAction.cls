/**
 * CaseProductFamilyPromptAction
 *
 * Invocable Apex action for the Intelligent_Case_Prioritization scheduled path.
 * Step 2 - Product Family Detection. Two modes:
 *
 *   MODE A - Data fetch (caseId + accountId provided):
 *     Fetches up to 20 installed Assets, serialises to JSON with Case context.
 *
 *   MODE B - Prompt parse (promptResponse provided):
 *     Parses JSON output from Agentforce_Case_ProductFamily_Detection.
 *
 * Constraints: no DML, without sharing, one @InvocableMethod. KAN-14.
 */
public without sharing class CaseProductFamilyPromptAction {

    private static final Integer MAX_ASSETS       = 20;
    private static final Integer MAX_DESC_CHARS   = 500;
    private static final Integer MAX_EMAIL_CHARS  = 500;
    private static final Integer MAX_PRODUCT_DESC = 300;

    public class ActionRequest {
        @InvocableVariable(label='Case Id')
        public Id caseId;
        @InvocableVariable(label='Account Id')
        public Id accountId;
        @InvocableVariable(label='Prompt Response JSON')
        public String promptResponse;
    }

    public class ActionResult {
        @InvocableVariable(label='Is Success')
        public Boolean isSuccess;
        @InvocableVariable(label='Assets JSON')
        public String assetsJson;
        @InvocableVariable(label='Case Subject')
        public String caseSubject;
        @InvocableVariable(label='Case Description')
        public String caseDescription;
        @InvocableVariable(label='Case Email Body')
        public String caseEmailBody;
        @InvocableVariable(label='Product Family')
        public String productFamily;
        @InvocableVariable(label='Matched Asset Name')
        public String matchedAssetName;
        @InvocableVariable(label='Error Message')
        public String errorMessage;
    }

    @InvocableMethod(
        label='Detect Product Family from Assets'
        description='MODE A: Fetches Assets + Case context for the Flex Prompt. MODE B: Parses prompt JSON to extract productFamily. KAN-14.'
    )
    public static List<ActionResult> execute(List<ActionRequest> requests) {
        List<ActionResult> results = new List<ActionResult>();
        for (ActionRequest req : requests) {
            if (String.isNotBlank(req.promptResponse)) {
                results.add(parseOne(req.promptResponse));
            } else {
                results.add(detectOne(req));
            }
        }
        return results;
    }

    @TestVisible
    static ActionResult detectOne(ActionRequest req) {
        ActionResult result = new ActionResult();
        result.isSuccess        = false;
        result.productFamily    = '';
        result.matchedAssetName = '';
        result.caseEmailBody    = '';
        result.assetsJson       = '[]';

        try {
            List<Asset> assets = [
                SELECT Name, Product2.Name, Product2.Family, Product2.Description
                FROM   Asset
                WHERE  AccountId = :req.accountId
                AND    Status    = 'Installed'
                ORDER BY InstallDate DESC
                LIMIT  :MAX_ASSETS
            ];

            if (assets.isEmpty()) {
                result.errorMessage = 'No installed assets found on Account';
                return result;
            }

            List<Map<String, String>> assetList = new List<Map<String, String>>();
            for (Asset a : assets) {
                Map<String, String> entry = new Map<String, String>();
                entry.put('assetName',         a.Name ?? '');
                entry.put('productName',        a.Product2 != null ? (a.Product2.Name ?? '') : '');
                entry.put('productFamily',      a.Product2 != null ? (a.Product2.Family ?? '') : '');
                String rawDesc = a.Product2 != null ? (a.Product2.Description ?? '') : '';
                entry.put('productDescription', truncate(rawDesc, MAX_PRODUCT_DESC));
                assetList.add(entry);
            }
            result.assetsJson = JSON.serialize(assetList);

            Case c = [SELECT Subject, Description FROM Case WHERE Id = :req.caseId LIMIT 1];
            result.caseSubject     = truncate(c.Subject ?? '',     MAX_DESC_CHARS);
            result.caseDescription = truncate(c.Description ?? '', MAX_DESC_CHARS);

            List<EmailMessage> emails = [
                SELECT TextBody FROM EmailMessage
                WHERE  ParentId = :req.caseId AND Incoming = true
                ORDER BY CreatedDate DESC LIMIT 1
            ];
            result.caseEmailBody = emails.isEmpty() ? '' : truncate(emails[0].TextBody ?? '', MAX_EMAIL_CHARS);
            result.isSuccess = true;

        } catch (Exception e) {
            result.isSuccess    = false;
            result.errorMessage = e.getMessage();
        }
        return result;
    }

    @TestVisible
    static ActionResult parseOne(String rawJson) {
        ActionResult result = new ActionResult();
        result.isSuccess        = false;
        result.productFamily    = '';
        result.matchedAssetName = '';

        if (String.isBlank(rawJson)) {
            result.errorMessage = 'Prompt response is null or empty.';
            return result;
        }

        String sanitized = sanitizeJson(rawJson);
        try {
            Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(sanitized);
            String family = getStringValue(parsed, 'matched_product_family');
            String asset  = getStringValue(parsed, 'matched_asset_name');
            result.productFamily    = family ?? '';
            result.matchedAssetName = asset  ?? '';
            result.isSuccess        = true;
        } catch (Exception e) {
            result.isSuccess    = false;
            result.errorMessage = 'JSON parse error: ' + e.getMessage();
        }
        return result;
    }

    @TestVisible
    public static String sanitizeJson(String input) {
        if (input == null) { return null; }
        String result = input.replace('\u00A0', ' ');
        result = result.replaceAll('[\\u0000-\\u0008\\u000B\\u000C\\u000E-\\u001F]', '');
        result = result.replaceAll('(?s)```(?:json)?\\s*(\\{.*?\\})\\s*```', '$1');
        return result.trim();
    }

    private static String getStringValue(Map<String, Object> m, String key) {
        Object val = m.get(key);
        if (val == null) { return null; }
        String s = String.valueOf(val).trim();
        return String.isBlank(s) ? null : s;
    }

    private static String truncate(String s, Integer maxLen) {
        if (s == null) { return ''; }
        return s.length() > maxLen ? s.substring(0, maxLen) : s;
    }
}
