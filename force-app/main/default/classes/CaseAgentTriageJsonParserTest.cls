@IsTest
private class CaseAgentTriageJsonParserTest {

    // ─── 1. Valid JSON — all fields correct ──────────────────────────────────

    @IsTest
    static void testValidJsonAllFields() {
        String json = '{"priority":"High","reason":"New problem","type":"Product Support"}';

        Test.startTest();
        List<CaseAgentTriageJsonParser.ParseResult> results = CaseAgentTriageJsonParser.parse(
            new List<CaseAgentTriageJsonParser.ParseRequest>{ buildRequest(json) }
        );
        Test.stopTest();

        System.assertEquals(1, results.size());
        CaseAgentTriageJsonParser.ParseResult r = results[0];
        System.assertEquals(true,  r.isSuccess,  'isSuccess should be true');
        System.assertEquals('High',            r.priority);
        System.assertEquals('New problem',     r.reason);
        System.assertEquals('Product Support', r.caseType);
        System.assertEquals(null, r.errorMessage, 'No error expected');
    }

    // ─── 2. Partial success — invalid priority, valid reason and type ─────────

    @IsTest
    static void testPartialSuccessInvalidPriority() {
        String json = '{"priority":"Urgent","reason":"Existing problem","type":"General"}';

        Test.startTest();
        CaseAgentTriageJsonParser.ParseResult r = CaseAgentTriageJsonParser.parseOne(json);
        Test.stopTest();

        System.assertEquals(true,  r.isSuccess, 'Partial success: at least one valid field');
        System.assertEquals(null,  r.priority,  'Invalid priority should be null');
        System.assertEquals('Existing problem', r.reason);
        System.assertEquals('General',          r.caseType);
        System.assertNotEquals(null, r.errorMessage, 'Warning expected for invalid priority');
        System.assert(r.errorMessage.contains('priority'), 'Error message should mention priority');
    }

    // ─── 3. JSON with U+00A0 non-breaking spaces ──────────────────────────────

    @IsTest
    static void testSanitizeNonBreakingSpaces() {
        // U+00A0 embedded in the value string
        String json = '{"priority":"High","reason":"New\u00A0problem","type":"Technical Issue"}';

        Test.startTest();
        CaseAgentTriageJsonParser.ParseResult r = CaseAgentTriageJsonParser.parseOne(json);
        Test.stopTest();

        // sanitizeJson replaces U+00A0 with regular space, so "New problem" should match
        System.assertEquals(true,  r.isSuccess);
        System.assertEquals('High', r.priority);
        System.assertEquals('New problem', r.reason, 'Non-breaking space should be replaced');
    }

    // ─── 4. Null input ────────────────────────────────────────────────────────

    @IsTest
    static void testNullInput() {
        Test.startTest();
        CaseAgentTriageJsonParser.ParseResult r = CaseAgentTriageJsonParser.parseOne(null);
        Test.stopTest();

        System.assertEquals(false, r.isSuccess);
        System.assertNotEquals(null, r.errorMessage);
    }

    // ─── 5. Empty string input ────────────────────────────────────────────────

    @IsTest
    static void testEmptyStringInput() {
        Test.startTest();
        CaseAgentTriageJsonParser.ParseResult r = CaseAgentTriageJsonParser.parseOne('');
        Test.stopTest();

        System.assertEquals(false, r.isSuccess);
        System.assertNotEquals(null, r.errorMessage);
    }

    // ─── 6. Malformed JSON ────────────────────────────────────────────────────

    @IsTest
    static void testMalformedJson() {
        String json = '{priority: High, broken}';

        Test.startTest();
        CaseAgentTriageJsonParser.ParseResult r = CaseAgentTriageJsonParser.parseOne(json);
        Test.stopTest();

        System.assertEquals(false, r.isSuccess);
        System.assertNotEquals(null, r.errorMessage);
        System.assert(r.errorMessage.toLowerCase().contains('parse') ||
                       r.errorMessage.toLowerCase().contains('json'),
                       'Error should mention parse/JSON issue');
    }

    // ─── 7. Valid contactId (starts 003) and accountId (starts 001) ───────────

    @IsTest
    static void testValidContactAndAccountId() {
        // Use known-good 18-char fake IDs matching the correct prefixes
        String contactId = '0031000000000001AAA';
        String accountId = '0011000000000001AAA';
        String json = '{"priority":"Low","reason":"Complex functionality","type":"General",' +
                      '"contactId":"' + contactId + '","accountId":"' + accountId + '"}';

        Test.startTest();
        CaseAgentTriageJsonParser.ParseResult r = CaseAgentTriageJsonParser.parseOne(json);
        Test.stopTest();

        System.assertEquals(true, r.isSuccess);
        System.assertNotEquals(null, r.contactId, 'contactId should be set');
        System.assertNotEquals(null, r.accountId, 'accountId should be set');
    }

    // ─── 8. Invalid contactId (wrong prefix) ─────────────────────────────────

    @IsTest
    static void testInvalidContactId() {
        String json = '{"priority":"Medium","reason":"New problem","type":"Account Support",' +
                      '"contactId":"0051000000000001AAA"}';

        Test.startTest();
        CaseAgentTriageJsonParser.ParseResult r = CaseAgentTriageJsonParser.parseOne(json);
        Test.stopTest();

        System.assertEquals(true, r.isSuccess, 'Other fields still valid');
        System.assertEquals(null, r.contactId, 'Invalid contactId should be null');
        System.assertNotEquals(null, r.errorMessage);
        System.assert(r.errorMessage.contains('contactId'), 'Error should mention contactId');
    }

    // ─── 9. JSON wrapped in markdown fences (LLM misbehaviour) ───────────────

    @IsTest
    static void testMarkdownFenceStripping() {
        String json = '```json\n{"priority":"Critical","reason":"Instructions not clear","type":"Technical Issue"}\n```';

        Test.startTest();
        CaseAgentTriageJsonParser.ParseResult r = CaseAgentTriageJsonParser.parseOne(json);
        Test.stopTest();

        System.assertEquals(true, r.isSuccess);
        System.assertEquals('Critical', r.priority);
    }

    // ─── 10. sanitizeJson standalone tests ────────────────────────────────────

    @IsTest
    static void testSanitizeJsonHelper() {
        String input = 'hello\u00A0world\u0001\u0007';
        String output = CaseAgentTriageJsonParser.sanitizeJson(input);
        System.assert(!output.contains('\u00A0'), 'Non-breaking space should be removed');
        System.assert(!output.contains('\u0001'), 'Control char should be removed');
        System.assertEquals('hello world', output);
    }

    @IsTest
    static void testSanitizeJsonNull() {
        System.assertEquals(null, CaseAgentTriageJsonParser.sanitizeJson(null));
    }

    // ─── Helper ───────────────────────────────────────────────────────────────

    private static CaseAgentTriageJsonParser.ParseRequest buildRequest(String json) {
        CaseAgentTriageJsonParser.ParseRequest req = new CaseAgentTriageJsonParser.ParseRequest();
        req.json = json;
        return req;
    }
}
