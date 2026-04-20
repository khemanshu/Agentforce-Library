/**
 * EscalationRiskFromPromptActionTest
 *
 * Unit tests for EscalationRiskFromPromptAction. KAN-19.
 * Target: >= 85% code coverage.
 */
@IsTest
private class EscalationRiskFromPromptActionTest {

    // ── Test data setup ──────────────────────────────────────────────────────

    private static Case createCase() {
        Case c = new Case(Subject = 'Escalation Risk Test Case', Status = 'New', Origin = 'Email');
        insert c;
        return c;
    }

    private static String validJson(Integer score, String level, String signals, String action) {
        Map<String, Object> m = new Map<String, Object>{
            'escalation_risk_score'         => score,
            'escalation_risk_level'         => level,
            'escalation_risk_signals'       => signals,
            'escalation_recommended_action' => action
        };
        return JSON.serialize(m);
    }

    // ── Happy path ───────────────────────────────────────────────────────────

    @IsTest
    static void testHappyPath_highRisk() {
        Case c = createCase();
        String json = validJson(85, 'High',
            '3 unanswered emails; First Response violated',
            'Contact customer by phone within 30 minutes');

        Test.startTest();
        EscalationRiskFromPromptAction.ActionRequest req = new EscalationRiskFromPromptAction.ActionRequest();
        req.caseId            = c.Id;
        req.promptResponseJson = json;
        List<EscalationRiskFromPromptAction.ActionResult> results =
            EscalationRiskFromPromptAction.execute(
                new List<EscalationRiskFromPromptAction.ActionRequest>{ req });
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assert(results[0].isSuccess, 'Should succeed: ' + results[0].errorMessage);

        Case updated = [SELECT Escalation_Risk_Score__c, Escalation_Risk_Level__c,
                               Escalation_Risk_Signals__c, Escalation_Recommended_Action__c,
                               Last_Risk_Assessment__c
                        FROM Case WHERE Id = :c.Id];
        System.assertEquals(85,     updated.Escalation_Risk_Score__c, 'Score should be 85');
        System.assertEquals('High', updated.Escalation_Risk_Level__c, 'Level should be High');
        System.assertNotEquals(null, updated.Last_Risk_Assessment__c, 'Timestamp should be set');
        System.assertNotEquals(null, updated.Escalation_Risk_Signals__c, 'Signals should be set');
        System.assertNotEquals(null, updated.Escalation_Recommended_Action__c, 'Action should be set');
    }

    @IsTest
    static void testHappyPath_criticalRisk() {
        Case c = createCase();
        String json = validJson(95, 'Critical', 'Customer threatened to leave', 'Escalate to senior engineer immediately');

        Test.startTest();
        EscalationRiskFromPromptAction.ActionRequest req = new EscalationRiskFromPromptAction.ActionRequest();
        req.caseId            = c.Id;
        req.promptResponseJson = json;
        EscalationRiskFromPromptAction.execute(
            new List<EscalationRiskFromPromptAction.ActionRequest>{ req });
        Test.stopTest();

        Case updated = [SELECT Escalation_Risk_Level__c, Escalation_Risk_Score__c FROM Case WHERE Id = :c.Id];
        System.assertEquals('Critical', updated.Escalation_Risk_Level__c);
        System.assertEquals(95, updated.Escalation_Risk_Score__c);
    }

    @IsTest
    static void testHappyPath_lowRisk() {
        Case c = createCase();
        String json = validJson(10, 'Low', 'Single email, polite tone', 'No immediate action required');

        Test.startTest();
        EscalationRiskFromPromptAction.ActionRequest req = new EscalationRiskFromPromptAction.ActionRequest();
        req.caseId            = c.Id;
        req.promptResponseJson = json;
        EscalationRiskFromPromptAction.execute(
            new List<EscalationRiskFromPromptAction.ActionRequest>{ req });
        Test.stopTest();

        Case updated = [SELECT Escalation_Risk_Level__c FROM Case WHERE Id = :c.Id];
        System.assertEquals('Low', updated.Escalation_Risk_Level__c);
    }

    // ── Null / empty prompt ──────────────────────────────────────────────────

    @IsTest
    static void testNullPromptResponse_writesFallback() {
        Case c = createCase();

        Test.startTest();
        EscalationRiskFromPromptAction.ActionRequest req = new EscalationRiskFromPromptAction.ActionRequest();
        req.caseId            = c.Id;
        req.promptResponseJson = null;
        List<EscalationRiskFromPromptAction.ActionResult> results =
            EscalationRiskFromPromptAction.execute(
                new List<EscalationRiskFromPromptAction.ActionRequest>{ req });
        Test.stopTest();

        System.assertEquals(false, results[0].isSuccess, 'Should report failure for null prompt');
        Case updated = [SELECT Escalation_Risk_Score__c, Escalation_Risk_Signals__c,
                               Escalation_Recommended_Action__c
                        FROM Case WHERE Id = :c.Id];
        System.assertEquals(0,                      updated.Escalation_Risk_Score__c, 'Fallback score should be 0');
        System.assertEquals('Assessment unavailable', updated.Escalation_Risk_Signals__c, 'Fallback signals');
        System.assertEquals('Manual review required', updated.Escalation_Recommended_Action__c, 'Fallback action');
    }

    @IsTest
    static void testEmptyPromptResponse_writesFallback() {
        Case c = createCase();

        Test.startTest();
        EscalationRiskFromPromptAction.ActionRequest req = new EscalationRiskFromPromptAction.ActionRequest();
        req.caseId            = c.Id;
        req.promptResponseJson = '   ';
        List<EscalationRiskFromPromptAction.ActionResult> results =
            EscalationRiskFromPromptAction.execute(
                new List<EscalationRiskFromPromptAction.ActionRequest>{ req });
        Test.stopTest();

        System.assertEquals(false, results[0].isSuccess, 'Blank prompt should fail');
    }

    // ── Invalid risk level ───────────────────────────────────────────────────

    @IsTest
    static void testInvalidRiskLevel_fieldLeftNull() {
        Case c = createCase();
        // LLM returns a level not in the allowed set
        String json = validJson(60, 'Moderate', 'Some signals', 'Some action');

        Test.startTest();
        EscalationRiskFromPromptAction.ActionRequest req = new EscalationRiskFromPromptAction.ActionRequest();
        req.caseId            = c.Id;
        req.promptResponseJson = json;
        List<EscalationRiskFromPromptAction.ActionResult> results =
            EscalationRiskFromPromptAction.execute(
                new List<EscalationRiskFromPromptAction.ActionRequest>{ req });
        Test.stopTest();

        // Should succeed (other 4 fields written) but level stays null
        System.assert(results[0].isSuccess, 'Should succeed even with invalid level');
        Case updated = [SELECT Escalation_Risk_Level__c, Escalation_Risk_Score__c FROM Case WHERE Id = :c.Id];
        System.assertEquals(null, updated.Escalation_Risk_Level__c, 'Invalid level should be null');
        System.assertEquals(60,   updated.Escalation_Risk_Score__c, 'Score should still be written');
    }

    // ── sanitizeJson tests ───────────────────────────────────────────────────

    @IsTest
    static void testSanitizeJson_stripsNonBreakingSpaces() {
        String dirty = '{"escalation_risk_level":\u00A0"High"\u00A0}';
        String clean = EscalationRiskFromPromptAction.sanitizeJson(dirty);
        System.assert(!clean.contains('\u00A0'), 'Non-breaking spaces should be removed');
    }

    @IsTest
    static void testSanitizeJson_unwrapsMarkdownFence() {
        String fenced = '```json\n{"escalation_risk_score": 80}\n```';
        String clean  = EscalationRiskFromPromptAction.sanitizeJson(fenced);
        System.assert(clean.startsWith('{'), 'Should unwrap markdown code fence');
    }

    @IsTest
    static void testSanitizeJson_nullInput() {
        System.assertEquals(null, EscalationRiskFromPromptAction.sanitizeJson(null),
            'Null input should return null');
    }

    // ── Malformed JSON ───────────────────────────────────────────────────────

    @IsTest
    static void testMalformedJson_writesFallback() {
        Case c = createCase();

        Test.startTest();
        EscalationRiskFromPromptAction.ActionRequest req = new EscalationRiskFromPromptAction.ActionRequest();
        req.caseId            = c.Id;
        req.promptResponseJson = 'NOT VALID JSON {{{{';
        List<EscalationRiskFromPromptAction.ActionResult> results =
            EscalationRiskFromPromptAction.execute(
                new List<EscalationRiskFromPromptAction.ActionRequest>{ req });
        Test.stopTest();

        System.assertEquals(false, results[0].isSuccess, 'Malformed JSON should fail');
        System.assert(results[0].errorMessage.contains('JSON parse error'), 'Error should mention JSON parse');
    }

    // ── writeFallback direct test ────────────────────────────────────────────

    @IsTest
    static void testWriteFallback_directly() {
        Case c = createCase();

        Test.startTest();
        EscalationRiskFromPromptAction.ActionResult res =
            EscalationRiskFromPromptAction.writeFallback(c.Id, 'Test fallback reason');
        Test.stopTest();

        System.assertEquals(false, res.isSuccess, 'writeFallback should report isSuccess=false');
        System.assert(res.errorMessage.contains('Test fallback reason'), 'Should preserve reason');
        Case updated = [SELECT Escalation_Risk_Signals__c FROM Case WHERE Id = :c.Id];
        System.assertEquals('Assessment unavailable', updated.Escalation_Risk_Signals__c);
    }
}
