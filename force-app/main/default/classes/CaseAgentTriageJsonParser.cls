/**
 * CaseAgentTriageJsonParser
 *
 * Parses the JSON response from the Intelligent Case Prioritization flex prompt.
 * Invoked by the Intelligent_Case_Prioritization record-triggered flow as an
 * @InvocableMethod action.
 *
 * Sharing model: without sharing — consistent with org-wide constraint.
 */
public without sharing class CaseAgentTriageJsonParser {

    // Allowed value sets
    private static final Set<String> ALLOWED_PRIORITIES = new Set<String>{
        'Low', 'Medium', 'High', 'Critical'
    };

    private static final Set<String> ALLOWED_REASONS = new Set<String>{
        'User didn\'t attend training',
        'Complex functionality',
        'Existing problem',
        'Instructions not clear',
        'New problem'
    };

    private static final Set<String> ALLOWED_TYPES = new Set<String>{
        'Product Support', 'Account Support', 'General', 'Technical Issue'
    };

    // ─── Input / Output wrappers ─────────────────────────────────────────────

    public class ParseRequest {
        @InvocableVariable(label='JSON String from Prompt' required=true)
        public String json;
    }

    public class ParseResult {
        @InvocableVariable(label='Is Success')
        public Boolean isSuccess;

        @InvocableVariable(label='Priority')
        public String priority;

        @InvocableVariable(label='Reason')
        public String reason;

        @InvocableVariable(label='Type')
        public String caseType;  // 'type' is a reserved word in Apex

        @InvocableVariable(label='Contact Id')
        public Id contactId;

        @InvocableVariable(label='Account Id')
        public Id accountId;

        @InvocableVariable(label='Error Message')
        public String errorMessage;
    }

    // ─── Entry point ─────────────────────────────────────────────────────────

    @InvocableMethod(label='Parse Case Triage JSON' description='Parses and validates the JSON output from the Intelligent Case Prioritization flex prompt.')
    public static List<ParseResult> parse(List<ParseRequest> requests) {
        List<ParseResult> results = new List<ParseResult>();
        for (ParseRequest req : requests) {
            results.add(parseOne(req.json));
        }
        return results;
    }

    // ─── Core parsing logic ───────────────────────────────────────────────────

    @TestVisible
    private static ParseResult parseOne(String rawJson) {
        ParseResult result = new ParseResult();
        result.isSuccess = false;

        if (String.isBlank(rawJson)) {
            result.errorMessage = 'Input JSON is null or empty.';
            return result;
        }

        String sanitized = sanitizeJson(rawJson);

        Map<String, Object> parsed;
        try {
            parsed = (Map<String, Object>) JSON.deserializeUntyped(sanitized);
        } catch (Exception e) {
            result.errorMessage = 'JSON parse error: ' + e.getMessage();
            return result;
        }

        List<String> warnings = new List<String>();
        Boolean atLeastOneValid = false;

        // --- priority ---
        String rawPriority = getStringValue(parsed, 'priority');
        if (rawPriority != null) {
            if (ALLOWED_PRIORITIES.contains(rawPriority)) {
                result.priority = rawPriority;
                atLeastOneValid = true;
            } else {
                warnings.add('Invalid priority value: "' + rawPriority + '".');
            }
        }

        // --- reason ---
        String rawReason = getStringValue(parsed, 'reason');
        if (rawReason != null) {
            if (ALLOWED_REASONS.contains(rawReason)) {
                result.reason = rawReason;
                atLeastOneValid = true;
            } else {
                warnings.add('Invalid reason value: "' + rawReason + '".');
            }
        }

        // --- type ---
        String rawType = getStringValue(parsed, 'type');
        if (rawType != null) {
            if (ALLOWED_TYPES.contains(rawType)) {
                result.caseType = rawType;
                atLeastOneValid = true;
            } else {
                warnings.add('Invalid type value: "' + rawType + '".');
            }
        }

        // --- contactId ---
        String rawContactId = getStringValue(parsed, 'contactId');
        if (rawContactId != null) {
            if (rawContactId.length() >= 15 && rawContactId.startsWith('003')) {
                try {
                    result.contactId = (Id) rawContactId;
                } catch (Exception e) {
                    warnings.add('Invalid contactId format: "' + rawContactId + '".');
                }
            } else {
                warnings.add('Invalid contactId (must start with 003): "' + rawContactId + '".');
            }
        }

        // --- accountId ---
        String rawAccountId = getStringValue(parsed, 'accountId');
        if (rawAccountId != null) {
            if (rawAccountId.length() >= 15 && rawAccountId.startsWith('001')) {
                try {
                    result.accountId = (Id) rawAccountId;
                } catch (Exception e) {
                    warnings.add('Invalid accountId format: "' + rawAccountId + '".');
                }
            } else {
                warnings.add('Invalid accountId (must start with 001): "' + rawAccountId + '".');
            }
        }

        result.isSuccess = atLeastOneValid;
        result.errorMessage = warnings.isEmpty() ? null : String.join(warnings, ' ');

        return result;
    }

    // ─── Helpers ─────────────────────────────────────────────────────────────

    /**
     * Strips U+00A0 non-breaking spaces and Unicode control characters that
     * LLMs occasionally emit, which cause JSON.deserializeUntyped to fail.
     */
    @TestVisible
    private static String sanitizeJson(String input) {
        if (input == null) {
            return null;
        }
        // Replace non-breaking space (U+00A0) with regular space
        String result = input.replace('\u00A0', ' ');
        // Strip C0 control characters (U+0000–U+001F) except tab, newline, carriage return
        result = result.replaceAll('[\\u0000-\\u0008\\u000B\\u000C\\u000E-\\u001F]', '');
        // Strip markdown code fences if LLM wrapped output
        result = result.replaceAll('(?s)```(?:json)?\\s*(\\{.*?\\})\\s*```', '$1');
        return result.trim();
    }

    private static String getStringValue(Map<String, Object> m, String key) {
        Object val = m.get(key);
        if (val == null) {
            return null;
        }
        String s = String.valueOf(val).trim();
        return String.isBlank(s) ? null : s;
    }
}
