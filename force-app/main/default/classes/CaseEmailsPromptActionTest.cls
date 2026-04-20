/**
 * CaseEmailsPromptActionTest
 *
 * Unit tests for CaseEmailsPromptAction. KAN-19.
 * Target: >= 85% code coverage.
 */
@IsTest
private class CaseEmailsPromptActionTest {

    // ── Test data setup ──────────────────────────────────────────────────────

    private static Case createCase() {
        Case c = new Case(Subject = 'Test Escalation Case', Status = 'New', Origin = 'Email');
        insert c;
        return c;
    }

    private static EmailMessage createEmail(Id caseId, String body) {
        EmailMessage em = new EmailMessage(
            ParentId    = caseId,
            Incoming    = true,
            Subject     = 'Customer complaint',
            TextBody    = body,
            FromAddress = 'customer@test.com',
            ToAddress   = 'support@voiceair.com'
        );
        insert em;
        return em;
    }

    // ── Tests ────────────────────────────────────────────────────────────────

    @IsTest
    static void testHappyPath_withEmailsNoMilestones() {
        Case c = createCase();
        createEmail(c.Id, 'This is unacceptable! I have been waiting for 3 days.');

        Test.startTest();
        CaseEmailsPromptAction.ActionRequest req = new CaseEmailsPromptAction.ActionRequest();
        req.caseId = c.Id;
        List<CaseEmailsPromptAction.ActionResult> results =
            CaseEmailsPromptAction.execute(new List<CaseEmailsPromptAction.ActionRequest>{ req });
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should return one result');
        CaseEmailsPromptAction.ActionResult res = results[0];
        System.assert(res.isSuccess, 'Should succeed: ' + res.errorMessage);
        System.assertNotEquals('[]', res.emailsJson, 'emailsJson should not be empty');
        System.assertEquals('[]', res.milestonesJson, 'milestonesJson should be empty (no milestones)');
    }

    @IsTest
    static void testHappyPath_noEmailsNoMilestones() {
        Case c = createCase();

        Test.startTest();
        CaseEmailsPromptAction.ActionRequest req = new CaseEmailsPromptAction.ActionRequest();
        req.caseId = c.Id;
        List<CaseEmailsPromptAction.ActionResult> results =
            CaseEmailsPromptAction.execute(new List<CaseEmailsPromptAction.ActionRequest>{ req });
        Test.stopTest();

        CaseEmailsPromptAction.ActionResult res = results[0];
        System.assert(res.isSuccess, 'Should succeed even with no emails');
        System.assertEquals('[]', res.emailsJson,     'emailsJson should be empty array');
        System.assertEquals('[]', res.milestonesJson,  'milestonesJson should be empty array');
    }

    @IsTest
    static void testMultipleEmails_truncation() {
        Case c = createCase();
        String longBody = 'A'.repeat(1000);
        createEmail(c.Id, longBody);
        createEmail(c.Id, 'Short email body');
        createEmail(c.Id, 'Another short email');

        Test.startTest();
        CaseEmailsPromptAction.ActionRequest req = new CaseEmailsPromptAction.ActionRequest();
        req.caseId = c.Id;
        List<CaseEmailsPromptAction.ActionResult> results =
            CaseEmailsPromptAction.execute(new List<CaseEmailsPromptAction.ActionRequest>{ req });
        Test.stopTest();

        CaseEmailsPromptAction.ActionResult res = results[0];
        System.assert(res.isSuccess, 'Should succeed');
        List<Object> emailsParsed = (List<Object>) JSON.deserializeUntyped(res.emailsJson);
        System.assertEquals(3, emailsParsed.size(), 'Should have 3 emails');
    }

    @IsTest
    static void testFetchOneWithRealCase() {
        // Use a real inserted Case Id to exercise the fetch path cleanly
        Case c = createCase();

        Test.startTest();
        CaseEmailsPromptAction.ActionResult res = CaseEmailsPromptAction.fetchOne(c.Id);
        Test.stopTest();

        System.assertNotEquals(null, res, 'Result should not be null');
        System.assert(res.isSuccess, 'Should succeed with valid Case Id');
        System.assertEquals('[]', res.emailsJson, 'No emails expected');
    }

    // ── safeParseMinutes tests ───────────────────────────────────────────────

    @IsTest
    static void testSafeParseMinutes_validHHMM() {
        System.assertEquals(150, CaseEmailsPromptAction.safeParseMinutes('02:30'), '02:30 should be 150 minutes');
        System.assertEquals(60,  CaseEmailsPromptAction.safeParseMinutes('01:00'), '01:00 should be 60 minutes');
        System.assertEquals(0,   CaseEmailsPromptAction.safeParseMinutes('00:00'), '00:00 should be 0 minutes');
    }

    @IsTest
    static void testSafeParseMinutes_plainInteger() {
        System.assertEquals(45,  CaseEmailsPromptAction.safeParseMinutes('45'),   'Plain int 45');
        System.assertEquals(0,   CaseEmailsPromptAction.safeParseMinutes('0'),    'Plain int 0');
        System.assertEquals(120, CaseEmailsPromptAction.safeParseMinutes('120'),  'Plain int 120');
    }

    @IsTest
    static void testSafeParseMinutes_nullAndBlank() {
        System.assertEquals(0, CaseEmailsPromptAction.safeParseMinutes(null),   'null should return 0');
        System.assertEquals(0, CaseEmailsPromptAction.safeParseMinutes(''),     'blank should return 0');
        System.assertEquals(0, CaseEmailsPromptAction.safeParseMinutes('null'), '"null" string should return 0');
    }

    @IsTest
    static void testSafeParseMinutes_invalidStrings() {
        System.assertEquals(0, CaseEmailsPromptAction.safeParseMinutes('abc'),    'invalid string returns 0');
        System.assertEquals(0, CaseEmailsPromptAction.safeParseMinutes('xx:yy'),  'invalid HH:MM returns 0');
        System.assertEquals(0, CaseEmailsPromptAction.safeParseMinutes('--:--'),  'dash HH:MM returns 0');
    }
}
