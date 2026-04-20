/**
 * CaseEmailsPromptAction
 *
 * Invocable Apex action for the Escalation Risk Assessment flow paths (KAN-19).
 * Fetches the last 10 inbound EmailMessages and all CaseMilestone records
 * for a given caseId and serialises them as JSON strings for the
 * Agentforce_Escalation_Risk_Assessment Flex Prompt Template.
 *
 * Notes:
 *   - No DML, without sharing (Agentforce platform constraint).
 *   - CaseMilestone.ElapsedTimeInMins may return HH:MM strings in some orgs
 *     -- use safeParseMinutes() to convert safely.
 *   - RemainingTimeInMins is not available in all orgs; omitted from query.
 *   - KAN-19.
 */
public without sharing class CaseEmailsPromptAction {

    private static final Integer MAX_EMAILS      = 10;
    private static final Integer MAX_BODY_CHARS  = 500;

    public class ActionRequest {
        @InvocableVariable(label='Case Id' required=true)
        public Id caseId;
    }

    public class ActionResult {
        @InvocableVariable(label='Emails JSON')
        public String emailsJson;
        @InvocableVariable(label='Milestones JSON')
        public String milestonesJson;
        @InvocableVariable(label='Is Success')
        public Boolean isSuccess;
        @InvocableVariable(label='Error Message')
        public String errorMessage;
    }

    @InvocableMethod(
        label='Fetch Case Emails and Milestones for Escalation Risk'
        description='Fetches last 10 inbound emails and all CaseMilestone records for a Case. Returns emailsJson and milestonesJson for the Escalation Risk Flex Prompt. KAN-19.'
    )
    public static List<ActionResult> execute(List<ActionRequest> requests) {
        List<ActionResult> results = new List<ActionResult>();
        for (ActionRequest req : requests) {
            results.add(fetchOne(req.caseId));
        }
        return results;
    }

    @TestVisible
    static ActionResult fetchOne(Id caseId) {
        ActionResult result = new ActionResult();
        result.isSuccess      = false;
        result.emailsJson     = '[]';
        result.milestonesJson = '[]';

        try {
            // -- Emails --
            List<EmailMessage> emails = [
                SELECT Subject, TextBody, FromAddress, CreatedDate, Incoming
                FROM   EmailMessage
                WHERE  ParentId = :caseId
                AND    Incoming = true
                ORDER BY CreatedDate DESC
                LIMIT  :MAX_EMAILS
            ];

            List<Map<String, Object>> emailList = new List<Map<String, Object>>();
            for (EmailMessage em : emails) {
                Map<String, Object> row = new Map<String, Object>();
                row.put('subject',    em.Subject ?? '');
                row.put('from',       em.FromAddress ?? '');
                row.put('body',       truncate(em.TextBody ?? '', MAX_BODY_CHARS));
                row.put('receivedAt', em.CreatedDate != null ? String.valueOf(em.CreatedDate) : '');
                emailList.add(row);
            }
            result.emailsJson = JSON.serialize(emailList);

            // -- Milestones --
            List<CaseMilestone> milestones = [
                SELECT MilestoneType.Name, IsCompleted, IsViolated,
                       CompletionDate, ElapsedTimeInMins, TargetDate
                FROM   CaseMilestone
                WHERE  CaseId = :caseId
                ORDER BY TargetDate ASC NULLS LAST
            ];

            List<Map<String, Object>> msList = new List<Map<String, Object>>();
            for (CaseMilestone ms : milestones) {
                Map<String, Object> row = new Map<String, Object>();
                row.put('milestoneName',  ms.MilestoneType != null ? ms.MilestoneType.Name : '');
                row.put('isCompleted',    ms.IsCompleted);
                row.put('isViolated',     ms.IsViolated);
                row.put('targetDate',     ms.TargetDate != null ? String.valueOf(ms.TargetDate) : '');
                row.put('completionDate', ms.CompletionDate != null ? String.valueOf(ms.CompletionDate) : '');
                row.put('elapsedMinutes', safeParseMinutes(String.valueOf(ms.ElapsedTimeInMins)));
                msList.add(row);
            }
            result.milestonesJson = JSON.serialize(msList);
            result.isSuccess = true;

        } catch (Exception e) {
            result.isSuccess    = false;
            result.errorMessage = e.getMessage();
        }
        return result;
    }

    /**
     * safeParseMinutes
     * CaseMilestone time fields may return an HH:MM string (e.g. "02:30")
     * rather than a plain integer. Handles both formats; returns 0 on failure.
     */
    @TestVisible
    public static Integer safeParseMinutes(String raw) {
        if (String.isBlank(raw) || raw == 'null') { return 0; }
        raw = raw.trim();
        if (raw.contains(':')) {
            List<String> parts = raw.split(':');
            try {
                Integer hours   = Integer.valueOf(parts[0]);
                Integer minutes = Integer.valueOf(parts[1]);
                return (hours * 60) + minutes;
            } catch (Exception e) {
                return 0;
            }
        }
        try {
            return Integer.valueOf(raw);
        } catch (Exception e) {
            return 0;
        }
    }

    private static String truncate(String s, Integer maxLen) {
        if (s == null) { return ''; }
        return s.length() > maxLen ? s.substring(0, maxLen) : s;
    }
}
