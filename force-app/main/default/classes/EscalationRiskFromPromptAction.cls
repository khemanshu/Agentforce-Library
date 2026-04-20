/**
 * EscalationRiskFromPromptAction
 *
 * Invocable Apex action for the Escalation Risk Assessment flow paths (KAN-19).
 * Receives the raw JSON string from the Agentforce_Escalation_Risk_Assessment
 * Flex Prompt Template, sanitises it, parses it, and writes the five custom
 * escalation risk fields back to the Case record.
 *
 * Expected JSON schema from the prompt:
 * {
 *   "escalation_risk_score":      <integer 0-100>,
 *   "escalation_risk_level":      "Low|Medium|High|Critical",
 *   "escalation_risk_signals":    "<free text>",
 *   "escalation_recommended_action": "<free text>"
 * }
 *
 * Notes:
 *   - No DML on input records; updates Case directly by Id.
 *   - without sharing (Agentforce platform constraint).
 *   - sanitizeJson() strips U+00A0 non-breaking spaces before JSON.deserialize.
 *   - Invalid escalation_risk_level leaves the picklist field null — no exception.
 *   - KAN-19.
 */
public without sharing class EscalationRiskFromPromptAction {

    private static final Set<String> VALID_LEVELS = new Set<String>{
        'Low', 'Medium', 'High', 'Critical'
    };

    public class ActionRequest {
        @InvocableVariable(label='Case Id' required=true)
        public Id caseId;
        @InvocableVariable(label='Prompt Response JSON' required=true)
        public String promptResponseJson;
    }

    public class ActionResult {
        @InvocableVariable(label='Is Success')
        public Boolean isSuccess;
        @InvocableVariable(label='Error Message')
        public String errorMessage;
    }

    @InvocableMethod(
        label='Write Escalation Risk Fields from Prompt Response'
        description='Parses escalation risk JSON from Agentforce_Escalation_Risk_Assessment and writes 5 custom fields to the Case record. KAN-19.'
    )
    public static List<ActionResult> execute(List<ActionRequest> requests) {
        List<ActionResult> results = new List<ActionResult>();
        for (ActionRequest req : requests) {
            results.add(processOne(req));
        }
        return results;
    }

    @TestVisible
    static ActionResult processOne(ActionRequest req) {
        ActionResult result = new ActionResult();
        result.isSuccess = false;

        // ── Null / empty prompt response — write fallback ───────────────────
        if (String.isBlank(req.promptResponseJson)) {
            return writeFallback(req.caseId, 'Prompt response is null or empty.');
        }

        String sanitized = sanitizeJson(req.promptResponseJson);
        Map<String, Object> parsed;
        try {
            parsed = (Map<String, Object>) JSON.deserializeUntyped(sanitized);
        } catch (Exception e) {
            return writeFallback(req.caseId, 'JSON parse error: ' + e.getMessage());
        }

        // ── Extract fields ──────────────────────────────────────────────────
        Integer riskScore = null;
        Object scoreRaw = parsed.get('escalation_risk_score');
        if (scoreRaw != null) {
            try { riskScore = Integer.valueOf(String.valueOf(scoreRaw)); } catch (Exception e) {}
        }

        String riskLevel = null;
        String levelRaw  = getStringValue(parsed, 'escalation_risk_level');
        if (levelRaw != null && VALID_LEVELS.contains(levelRaw)) {
            riskLevel = levelRaw;
        }

        String signals   = getStringValue(parsed, 'escalation_risk_signals');
        String action    = getStringValue(parsed, 'escalation_recommended_action');

        // ── Write to Case ───────────────────────────────────────────────────
        try {
            Case c = new Case(
                Id                              = req.caseId,
                Escalation_Risk_Score__c        = riskScore,
                Escalation_Risk_Level__c        = riskLevel,
                Escalation_Risk_Signals__c      = signals,
                Escalation_Recommended_Action__c = action,
                Last_Risk_Assessment__c         = System.now()
            );
            update c;
            result.isSuccess = true;
        } catch (Exception e) {
            result.isSuccess    = false;
            result.errorMessage = 'Case update failed: ' + e.getMessage();
        }
        return result;
    }

    /**
     * writeFallback
     * Writes safe defaults to the Case when the prompt response is unusable.
     */
    @TestVisible
    static ActionResult writeFallback(Id caseId, String reason) {
        ActionResult result = new ActionResult();
        try {
            Case c = new Case(
                Id                              = caseId,
                Escalation_Risk_Score__c        = 0,
                Escalation_Risk_Level__c        = null,
                Escalation_Risk_Signals__c      = 'Assessment unavailable',
                Escalation_Recommended_Action__c = 'Manual review required',
                Last_Risk_Assessment__c         = System.now()
            );
            update c;
            result.isSuccess    = false;
            result.errorMessage = reason;
        } catch (Exception e) {
            result.isSuccess    = false;
            result.errorMessage = reason + ' | Fallback write also failed: ' + e.getMessage();
        }
        return result;
    }

    /**
     * sanitizeJson
     * Strips U+00A0 non-breaking spaces and other control characters that
     * Agentforce LLM responses sometimes include, and unwraps markdown
     * code fences if present.
     */
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
}
