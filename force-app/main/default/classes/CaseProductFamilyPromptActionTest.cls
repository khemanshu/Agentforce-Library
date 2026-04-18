/**
 * CaseProductFamilyPromptActionTest
 * Minimum 85% coverage for CaseProductFamilyPromptAction.
 * Pattern reference: CaseAgentTriageJsonParserTest.cls (KAN-12)
 * KAN-14 — AI-Powered ProductFamily__c Population
 */
@IsTest
private class CaseProductFamilyPromptActionTest {

    @TestSetup
    static void makeData() {
        Account acc = new Account(Name = 'Voice Air Telecom Test');
        insert acc;
        Product2 p1 = new Product2(Name = 'Broadband 100Mbps', Family = 'Broadband', IsActive = true, Description = 'High-speed broadband service');
        Product2 p2 = new Product2(Name = 'Mobile Plan Pro',   Family = 'Mobile',    IsActive = true, Description = 'Premium mobile plan');
        Product2 p3 = new Product2(Name = 'TV Plus Bundle',    Family = 'TV',        IsActive = true, Description = 'Full TV bundle');
        insert new List<Product2>{ p1, p2, p3 };
        Asset a1 = new Asset(Name = 'Broadband 100Mbps Plan', AccountId = acc.Id, Product2Id = p1.Id, Status = 'Installed', InstallDate = Date.today().addDays(-90));
        Asset a2 = new Asset(Name = 'Mobile Plan Pro',         AccountId = acc.Id, Product2Id = p2.Id, Status = 'Installed', InstallDate = Date.today().addDays(-60));
        Asset a3 = new Asset(Name = 'TV Plus Bundle',          AccountId = acc.Id, Product2Id = p3.Id, Status = 'Installed', InstallDate = Date.today().addDays(-30));
        insert new List<Asset>{ a1, a2, a3 };
        Case c = new Case(AccountId = acc.Id, Subject = 'Internet very slow', Description = 'Speed dropped below 5Mbps.', Status = 'New', Origin = 'Email');
        insert c;
        EmailMessage em = new EmailMessage(ParentId = c.Id, Subject = 'Re: Slow internet', TextBody = 'My broadband has been terrible for 2 days.', FromAddress = 'customer@example.com', Incoming = true, Status = '0');
        insert em;
    }

    @IsTest
    static void testSuccess() {
        Case c = [SELECT Id, AccountId FROM Case LIMIT 1];
        CaseProductFamilyPromptAction.ActionRequest req = new CaseProductFamilyPromptAction.ActionRequest();
        req.caseId = c.Id; req.accountId = c.AccountId;
        Test.startTest();
        List<CaseProductFamilyPromptAction.ActionResult> results = CaseProductFamilyPromptAction.execute(new List<CaseProductFamilyPromptAction.ActionRequest>{ req });
        Test.stopTest();
        Assert.areEqual(1, results.size());
        CaseProductFamilyPromptAction.ActionResult r = results[0];
        Assert.isTrue(r.isSuccess);
        Assert.isFalse(String.isBlank(r.assetsJson));
        Assert.isFalse(String.isBlank(r.caseSubject));
        Assert.isFalse(String.isBlank(r.caseEmailBody));
        Assert.isNull(r.errorMessage);
        Assert.isTrue(r.assetsJson.contains('Broadband'));
    }

    @IsTest
    static void testNoAssets() {
        Account emptyAcc = new Account(Name = 'No Assets Corp');
        insert emptyAcc;
        Case emptyCase = new Case(AccountId = emptyAcc.Id, Subject = 'Test', Status = 'New', Origin = 'Email');
        insert emptyCase;
        CaseProductFamilyPromptAction.ActionRequest req = new CaseProductFamilyPromptAction.ActionRequest();
        req.caseId = emptyCase.Id; req.accountId = emptyAcc.Id;
        Test.startTest();
        CaseProductFamilyPromptAction.ActionResult r = CaseProductFamilyPromptAction.detectOne(req);
        Test.stopTest();
        Assert.isFalse(r.isSuccess);
        Assert.areEqual('No installed assets found on Account', r.errorMessage);
        Assert.areEqual('[]', r.assetsJson);
    }

    @IsTest
    static void testNullEmail() {
        Account acc2 = new Account(Name = 'No Email Corp');
        insert acc2;
        Product2 p = new Product2(Name = 'Fibre Pro', Family = 'Fibre', IsActive = true);
        insert p;
        Asset a = new Asset(Name = 'Fibre Pro Plan', AccountId = acc2.Id, Product2Id = p.Id, Status = 'Installed', InstallDate = Date.today());
        insert a;
        Case c2 = new Case(AccountId = acc2.Id, Subject = 'Fibre issue', Description = 'Speed slow.', Status = 'New', Origin = 'Web');
        insert c2;
        CaseProductFamilyPromptAction.ActionRequest req = new CaseProductFamilyPromptAction.ActionRequest();
        req.caseId = c2.Id; req.accountId = acc2.Id;
        Test.startTest();
        CaseProductFamilyPromptAction.ActionResult r = CaseProductFamilyPromptAction.detectOne(req);
        Test.stopTest();
        Assert.isTrue(r.isSuccess);
        Assert.areEqual('', r.caseEmailBody);
        Assert.isFalse(String.isBlank(r.assetsJson));
        Assert.isNull(r.errorMessage);
    }

    @IsTest
    static void testJsonParseFailure() {
        CaseProductFamilyPromptAction.ActionRequest req = new CaseProductFamilyPromptAction.ActionRequest();
        req.promptResponse = '{broken json,,}';
        Test.startTest();
        List<CaseProductFamilyPromptAction.ActionResult> results = CaseProductFamilyPromptAction.execute(new List<CaseProductFamilyPromptAction.ActionRequest>{ req });
        Test.stopTest();
        Assert.isFalse(results[0].isSuccess);
        Assert.isNotNull(results[0].errorMessage);
    }

    @IsTest
    static void testParseOneSuccess() {
        String json = '{"matched_product_family":"Broadband","matched_asset_name":"Broadband 100Mbps Plan","confidence":"high","match_reason":"Speed issue"}';
        Test.startTest();
        CaseProductFamilyPromptAction.ActionResult r = CaseProductFamilyPromptAction.parseOne(json);
        Test.stopTest();
        Assert.isTrue(r.isSuccess);
        Assert.areEqual('Broadband', r.productFamily);
        Assert.areEqual('Broadband 100Mbps Plan', r.matchedAssetName);
    }

    @IsTest
    static void testParseOneNoMatch() {
        String json = '{"matched_product_family":"","matched_asset_name":"","confidence":"none","match_reason":"No match"}';
        Test.startTest();
        CaseProductFamilyPromptAction.ActionResult r = CaseProductFamilyPromptAction.parseOne(json);
        Test.stopTest();
        Assert.isTrue(r.isSuccess);
        Assert.areEqual('', r.productFamily);
    }

    @IsTest
    static void testParseOneSanitize() {
        String json = '{"matched_product_family":"Broad\u00A0band","matched_asset_name":"Test","confidence":"high","match_reason":"Test"}';
        Test.startTest();
        CaseProductFamilyPromptAction.ActionResult r = CaseProductFamilyPromptAction.parseOne(json);
        Test.stopTest();
        Assert.isTrue(r.isSuccess);
        Assert.areEqual('Broad band', r.productFamily);
    }

    @IsTest
    static void testParseOneNullInput() {
        Test.startTest();
        CaseProductFamilyPromptAction.ActionResult r = CaseProductFamilyPromptAction.parseOne(null);
        Test.stopTest();
        Assert.isFalse(r.isSuccess);
        Assert.isNotNull(r.errorMessage);
    }

    @IsTest
    static void testSanitizeJson() {
        String output = CaseProductFamilyPromptAction.sanitizeJson('hello\u00A0world\u0001');
        Assert.isFalse(output.contains('\u00A0'));
        Assert.areEqual('hello world', output);
    }

    @IsTest
    static void testSanitizeJsonNull() {
        Assert.isNull(CaseProductFamilyPromptAction.sanitizeJson(null));
    }
}
