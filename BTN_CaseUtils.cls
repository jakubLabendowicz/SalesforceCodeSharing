public class BTN_CaseUtils {
    private static final Id JOB_APPLICATION_ID = BTN_RecordTypeUtils.getRecordTypeIdByDeveloperName(Case.getSObjectType(), BTN_RecordTypeUtils.CASE_JOB_APPLICATION_RECORDTYPE);
    public static Set<Id> recruitmentTeamIdsForUpdate = new Set<Id>();
    private static List<Case> jobApplicationCases;
    private static Map<Id, Id> jobOfferRecruitmentTeamMap = new Map<Id, Id>();
    private static final String TRIGGER_ERROR_SOURCE = 'Case Trigger';

    public static final String STATUS_OPEN = 'Open';
    private static final String TEAM_ROLE_RECRUITER = 'Recruiter';
    private static final String TEAM_ROLE_RECRUITER_LEAD = 'Recruiter Lead';
    private static final String TEAM_ROLE_TECHNICAL_REVIEWER = 'Technical Reviewer';
    private static final String CASE_ASSIGNMENT_RULE_SKIP_NAME = 'Skip Assignment Rules';

    public static final Set<String> CASE_STATUSES_TO_ACCEPTED = new Set<String>{
            BTN_ConstantRepo.CASE_STATUS_OPEN,
            BTN_ConstantRepo.CASE_STATUS_HR_INTERVIEW,
            BTN_ConstantRepo.CASE_STATUS_TECHNICAL_INTERVIEW,
            BTN_ConstantRepo.CASE_STATUS_RECOMMENDED,
            BTN_ConstantRepo.CASE_STATUS_DELIVERED,
            BTN_ConstantRepo.CASE_STATUS_ACCEPTED
    };

    public static Id recruiterRole {
        get {
            if (recruiterRole == null) {
                List<CaseTeamRole> caseTeamRoles = [SELECT Id FROM CaseTeamRole WHERE Name = :TEAM_ROLE_RECRUITER];
                if (caseTeamRoles.size() > 0) {
                    recruiterRole = caseTeamRoles[0].Id;
                }
            }
            return recruiterRole;
        }
        set;
    }

    public static Case updateCaseContactInfo(Case caseItemToUpdate, Id contactId) {
        caseItemToUpdate.ContactId = contactId;
        update caseItemToUpdate;
        return caseItemToUpdate;
    }

    public static void executeCaseStandardAssignmentRule(Set<Id> caseIds) {
        List<Case> cases = new BTN_DAO_Case().findCasesInIdSet(caseIds);
        Database.DMLOptions dmlOpts = new Database.DMLOptions();
        Id caseAssignmentRuleId =
                new BTN_DAO_AssignmentRule().findCaseAssignmentRule().Id;
        dmlOpts.assignmentRuleHeader.useDefaultRule = true;
        for (Case caseItem : cases) {
            caseItem.setOptions(dmlOpts);
        }
        update cases;
    }

    public static void addCaseSharingForLeader(List<Case> caseList) {
        List<CaseShare> caseShareToInsert = new List<CaseShare>();
        Map<Id, Id> contactToUserMap = BTN_Utils.getContactToUserMap(BTN_Utils.getSetOfIds(caseList, 'Leader__c'));

        for (Case newCase : caseList) {
            if (BTN_RecordTypeUtils.isCaseInternalOnBoarding(newCase) && contactToUserMap.get(newCase.Leader__c) != null && !newCase.Freelancer__c) {
                CaseShare share = new CaseShare();
                share.CaseAccessLevel = 'Edit';
                share.CaseId = newCase.Id;
                share.RowCause = 'Manual';
                share.UserOrGroupId = contactToUserMap.get(newCase.Leader__c);
                caseShareToInsert.add(share);
            }
        }
        insert caseShareToInsert;
    }

    public static void replaceCaseSharingForLeader(Map<Id, Case> newCaseMap, Map<Id, Case> oldCaseMap) {
        List<Case> caseToInsert = new List<Case>();
        Map<Id, Id> caseToDelete = new Map<Id, Id>();

        for (Id caseId : newCaseMap.keySet()) {
            if (newCaseMap.get(caseId).Leader__c != oldCaseMap.get(caseId).Leader__c) {
                caseToInsert.add(newCaseMap.get(caseId));
                caseToDelete.put(oldCaseMap.get(caseId).Leader__c, caseId);
            }
        }
        addCaseSharingForLeader(caseToInsert);
        removeCaseSharingForLeader(caseToDelete);
    }

    public static void removeCaseSharingForLeader(Map<Id, Id> caseMap) {
        Map<Id, Id> contactToUserMap = BTN_Utils.getContactToUserMap(caseMap.keySet());
        if (!contactToUserMap.values().isEmpty()) {
            List<CaseShare> caseShareToDelete = [
                    select id
                    from CaseShare
                    where CaseId in :caseMap.values()
                    and UserOrGroupId in:contactToUserMap.values()
            ];
            delete caseShareToDelete;
        }
    }

    public static void addCaseTeamMembersToJobApplication() {
        Map<String, CaseTeamMember> newCaseTeamMembers = getNewCaseMembersForCase(jobApplicationCases);
        if (!newCaseTeamMembers.values().isEmpty()) {
            insert newCaseTeamMembers.values();
        }
    }

    public static void updateRecruitmentTeamBaseOnJobOffer(Case jobApp, Case oldJobApp) {
        if (jobOfferRecruitmentTeamMap.containsKey(jobApp.Job_Offer__c)
                && oldJobApp == null
                || BTN_UTIL_SObject.hasSObjectFieldChanged(oldJobApp, jobApp, Case.Job_Offer__c)) {
            jobApp.Recruitment_Team__c = jobOfferRecruitmentTeamMap.get(jobApp.Job_Offer__c);
        }
    }

    public static void updateCaseTeamMembersOnJobApplication(Map<Id, Case> newCaseMap, Map<Id, Case> oldCaseMap) {
        List<CaseTeamMember> membersForDelete = new List<CaseTeamMember>();
        Set<Id> caseToDeleteMembersIds = new Set<Id>();
        List<Case> caseWithNewHRecruitmentTeam = new List<Case>();

        for (Id caseId : newCaseMap.keySet()) {
            if (newCaseMap.get(caseId).Recruitment_Team__c != oldCaseMap.get(caseId).Recruitment_Team__c) {
                caseToDeleteMembersIds.add(caseId);
                if (newCaseMap.get(caseId).Recruitment_Team__c != null) {
                    caseWithNewHRecruitmentTeam.add(newCaseMap.get(caseId));
                }
            }
        }
        Map<String, CaseTeamMember> newCaseTeamMembers = getNewCaseMembersForCase(getJobApplicationCases(caseWithNewHRecruitmentTeam));
        if (!caseToDeleteMembersIds.isEmpty()) {
            for (CaseTeamMember member : [SELECT Id, ParentId, MemberId FROM CaseTeamMember WHERE ParentId IN :caseToDeleteMembersIds]) {
                String keyString = member.ParentId + '' + member.MemberId;
                if (newCaseTeamMembers.containsKey(keyString)) {
                    newCaseTeamMembers.remove(keyString);
                } else {
                    membersForDelete.add(member);
                }
            }
        }
        if (!newCaseTeamMembers.values().isEmpty()) {
            insert newCaseTeamMembers.values();
        }
        if (!membersForDelete.isEmpty()) {
            delete membersForDelete;
        }
    }

    public static Map<String, CaseTeamMember> getNewCaseMembersForCase(List<Case> newCaseList) {
        Map<String, CaseTeamMember> newCaseTeamMembers = new Map<String, CaseTeamMember>();
        Map<Id, List<Id>> recruitmentTeamToCaseMap = new Map<Id, List<Id>>();
        for (Case newRecord : newCaseList) {
            List<Id> caseIds;
            if (recruitmentTeamToCaseMap.containsKey(newRecord.Recruitment_Team__c)) {
                caseIds = recruitmentTeamToCaseMap.get(newRecord.Recruitment_Team__c);
            } else {
                caseIds = new List<Id>();
            }
            caseIds.add(newRecord.Id);
            recruitmentTeamToCaseMap.put(newRecord.Recruitment_Team__c, caseIds);
        }
        if (!recruitmentTeamToCaseMap.keySet().isEmpty()) {
            for (Recruitment_Team__c recruitmentTeam : [SELECT Id, (SELECT Id, User__c FROM Recruitment_Team_Members__r WHERE User__r.IsActive = true) FROM Recruitment_Team__c WHERE Id IN :recruitmentTeamToCaseMap.keySet()]) {
                for (Recruitment_Team_Member__c teamMember : recruitmentTeam.Recruitment_Team_Members__r) {
                    if (teamMember.User__c != null) {
                        for (Id jobApplicationId : recruitmentTeamToCaseMap.get(recruitmentTeam.Id)) {
                            if (!newCaseTeamMembers.containsKey(jobApplicationId + '' + teamMember.User__c)) {
                                newCaseTeamMembers.put(jobApplicationId + '' + teamMember.User__c, new CaseTeamMember(MemberId = teamMember.User__c, ParentId = jobApplicationId, TeamRoleId = recruiterRole));
                            }
                        }
                    }
                }
            }
        }
        return newCaseTeamMembers;
    }
    public static void getRecruitmentTeamForJobOffer(Map<Id, Case> oldCases) {
        Set<Id> jobOfferIds = new Set<Id>();
        for (Case newRecord : jobApplicationCases) {
            if (String.isNotBlank(newRecord.Job_Offer__c)
                    && (oldCases == null
                    || BTN_UTIL_SObject.hasSObjectFieldChanged(oldCases.get(newRecord.Id), newRecord, Case.Job_Offer__c))) {
                jobOfferIds.add(newRecord.Job_Offer__c);
            }
        }
        for (Job_Offer__c jobOffer : [SELECT Id, Recruitment_Team__c FROM Job_Offer__c WHERE Id IN :jobOfferIds]) {
            if (String.isNotBlank(jobOffer.Recruitment_Team__c)) {
                jobOfferRecruitmentTeamMap.put(jobOffer.Id, jobOffer.Recruitment_Team__c);
            }
        }
    }
    public static void getDeliveredJobApplicationCandidates(Map<Id, Case> newCases, Map<Id, Case> oldCases) {
        Set<Id> jobAppIds = new Set<Id>();
        for (Case newRecord : jobApplicationCases) {
            if (newRecord.Status.equals(BTN_ConstantRepo.CASE_STATUS_DELIVERED)
                    && (oldCases == null
                    || BTN_UTIL_SObject.hasSObjectFieldChanged(oldCases.get(newRecord.Id), newRecord, Case.Status))) {
                jobAppIds.add(newRecord.Id);
            }
        }
        for (Case jobApp : [SELECT Id, Recruitment_Team__c, (SELECT Id FROM Candidates_from_HR__r) FROM Case WHERE Id IN :jobAppIds]) {
            if (jobApp.Candidates_from_HR__r.size() == 0) {
                Case errorCase = newCases.get(jobApp.Id);
                errorCase.addError(System.Label.JobApplicationDeliveredErrorMessage);
            }
        }
    }

    public static BTN_CV__c findCandidateBaseOnContactId(Id contactId) {
        List<BTN_CV__c> candidates = (List<BTN_CV__c>) new BTN_DAO_Candidate().addResourceRequestFields().findSObjectsBy(new List<BTN_DAO.SearchCondition>{
                new BTN_DAO.SearchCondition('Status__c', 'IN', new Set<String>{
                        BTN_ConstantRepo.CASE_STATUS_ACCEPTED, BTN_ConstantRepo.STATUS_ONBOARDING, BTN_ConstantRepo.STATUS_CONTRACT_SIGNED
                }),
                new BTN_DAO.SearchCondition('Contact__c', '=', contactId)
        });
        if (!candidates.isEmpty()) {
            return candidates[0];
        } else {
            return null;
        }
    }

    public static void updateJobApplicationAndCandidateStatus(List<Case> newCases, Map<Id, Case> oldCaseMap) {
        Map<Id, Case> casesForUpdate = new Map<Id, Case>();
        List<BTN_CV__c> cidsForUpdate = new List<BTN_CV__c>();
        Set<Id> jobAppIdsOnboarding = new Set<Id>();
        Set<Id> jobAppIdsContractSigned = new Set<Id>();
        Set<Id> jobAppIdsRejected = new Set<Id>();
        Set<Id> jobAppIdsNotInterested = new Set<Id>();
        Set<Id> jobAppIdsOfferExpired = new Set<Id>();
        Set<Id> onboardingToAccept = new Set<Id>();
        for (Case newCaseRecord : newCases) {
            if ((oldCaseMap == null || newCaseRecord.Status != oldCaseMap.get(newCaseRecord.Id).Status)) {
                if (!isInternalOnboardingCase(newCaseRecord)) {
                    if (newCaseRecord.Status.equals(BTN_ConstantRepo.CASE_STATUS_NOT_INTERESTED) || newCaseRecord.Status.equals(BTN_ConstantRepo.CASE_STATUS_RESIGNED)) {
                        jobAppIdsNotInterested.add(newCaseRecord.Id);
                    } else if (newCaseRecord.Status.equals(BTN_ConstantRepo.CASE_STATUS_OFFER_EXPIRED)) {
                        jobAppIdsOfferExpired.add(newCaseRecord.Id);
                    } else if (newCaseRecord.Status.equals(BTN_ConstantRepo.STATUS_CONTRACT_SIGNED)) {
                        onboardingToAccept.add(newCaseRecord.Id);
                    }
                } else if (String.isNotBlank(newCaseRecord.ParentId)) {
                    if (newCaseRecord.Status.equals(BTN_ConstantRepo.CASE_STATUS_APPROVED)) {
                        jobAppIdsContractSigned.add(newCaseRecord.ParentId);
                    } else if (newCaseRecord.Status.equals(BTN_ConstantRepo.CASE_STATUS_OPEN)) {
                        jobAppIdsOnboarding.add(newCaseRecord.ParentId);
                    } else if (newCaseRecord.Status.equals(BTN_ConstantRepo.CASE_STATUS_REJECTED)) {
                        jobAppIdsRejected.add(newCaseRecord.ParentId);
                    }
                }
            }
        }
        if (!(jobAppIdsContractSigned.isEmpty() 
                && jobAppIdsOnboarding.isEmpty() 
                && jobAppIdsRejected.isEmpty() 
                && jobAppIdsNotInterested.isEmpty()
                && jobAppIdsOfferExpired.isEmpty()
                && onboardingToAccept.isEmpty())) {
            for (Case caseRecord : [
                    SELECT Id, IsClosed,Status,ParentId, (SELECT Id,Status__c FROM Candidates_from_HR__r)
                    FROM Case
                    WHERE Id IN :jobAppIdsContractSigned
                    OR Id IN :jobAppIdsOnboarding
                    OR Id IN :jobAppIdsRejected
                    OR Id IN :jobAppIdsNotInterested
                    OR Id IN :jobAppIdsOfferExpired
                    OR ParentId IN :onboardingToAccept
            ]) {
                if (jobAppIdsContractSigned.contains(caseRecord.Id)) {
                    if (!casesForUpdate.containsKey(caseRecord.Id) && !caseRecord.IsClosed) {
                        casesForUpdate.put(caseRecord.Id, new Case(Id = caseRecord.Id, Status = BTN_ConstantRepo.STATUS_CONTRACT_SIGNED));
                    }
                    for (BTN_CV__c cid : caseRecord.Candidates_from_HR__r) {
                        if (candidateStatusCanBeChanged(BTN_ConstantRepo.STATUS_CONTRACT_SIGNED, cid.Status__c)) {
                            cid.Status__c = BTN_ConstantRepo.STATUS_CONTRACT_SIGNED;
                            cidsForUpdate.add(cid);
                        }
                    }
                } else if (jobAppIdsOnboarding.contains(caseRecord.Id)
                        && !caseRecord.IsClosed
                        && caseRecord.Status != BTN_ConstantRepo.STATUS_CONTRACT_SIGNED) {
                    if (!casesForUpdate.containsKey(caseRecord.Id)) {
                        casesForUpdate.put(caseRecord.Id, new Case(Id = caseRecord.Id, Status = BTN_ConstantRepo.STATUS_ONBOARDING));
                    }
                    for (BTN_CV__c cid : caseRecord.Candidates_from_HR__r) {
                        if (candidateStatusCanBeChanged(BTN_ConstantRepo.STATUS_ONBOARDING, cid.Status__c)) {
                            cid.Status__c = BTN_ConstantRepo.STATUS_ONBOARDING;
                            cidsForUpdate.add(cid);
                        }
                    }
                } else if ((jobAppIdsRejected.contains(caseRecord.Id) && !caseRecord.IsClosed)
                        || jobAppIdsNotInterested.contains(caseRecord.Id)
                        ) {
                    if (!casesForUpdate.containsKey(caseRecord.Id) && !jobAppIdsNotInterested.contains(caseRecord.Id)) {
                        casesForUpdate.put(caseRecord.Id, new Case(
                                Id = caseRecord.Id,
                                Status = BTN_ConstantRepo.CASE_STATUS_RESIGNED,
                                Reject_Reason__c = BTN_ConstantRepo.CASE_REJECT_REASON_OTHER
                        ));
                    }
                    for (BTN_CV__c cid : caseRecord.Candidates_from_HR__r) {
                        if (candidateStatusCanBeChanged(BTN_ConstantRepo.CANDIDATE_STATUS_RESIGNED, cid.Status__c)) {
                            cid.Status__c = BTN_ConstantRepo.CANDIDATE_STATUS_RESIGNED;
                            cidsForUpdate.add(cid);
                        }
                    }
                } else if (jobAppIdsOfferExpired.contains(caseRecord.Id)) {
                    for (BTN_CV__c cid : caseRecord.Candidates_from_HR__r) {
                        if (candidateStatusCanBeChanged(BTN_ConstantRepo.CANDIDATE_STATUS_OFFER_EXPIRED, cid.Status__c)) {
                            cid.Status__c = BTN_ConstantRepo.CANDIDATE_STATUS_OFFER_EXPIRED;
                            cidsForUpdate.add(cid);
                        }
                    }
                } else if (onboardingToAccept.contains(caseRecord.ParentId) && !caseRecord.IsClosed && !casesForUpdate.containsKey(caseRecord.Id)) {
                    casesForUpdate.put(caseRecord.Id, new Case(Id = caseRecord.Id, Status = BTN_ConstantRepo.CASE_STATUS_APPROVED));
                }
            }
        }
        if (!cidsForUpdate.isEmpty()) {
            update cidsForUpdate;
        }
        if (!casesForUpdate.isEmpty()) {
            update casesForUpdate.values();
        }
    }

    public static void updateHROwnerOnCandidateToSales(List<Case> newCases, Map<Id, Case> oldCaseMap) {

        Set<Id> caseIds = new Set<Id>();

        for (Case newCase : newCases) {
            if (BTN_UTIL_SObject.hasSObjectFieldChanged(oldCaseMap.get(newCase.Id), newCase, Case.OwnerId)) {
                caseIds.add(newCase.Id);
            }
        }

        List<BTN_CV__c> candidatesFromHRList = [
                SELECT Id, Job_Application__r.OwnerId, (SELECT Id, isOpen__c, HR_Owner__c FROM Sales_Candidates__r WHERE isOpen__c = TRUE)
                FROM BTN_CV__c
                WHERE Job_Application__c = :caseIds
        ];

        List<Sales_Candidate__c> candidateToSalesUpdateList = new List<Sales_Candidate__c>();

        for (BTN_CV__c candidate : candidatesFromHRList) {
            for (Sales_Candidate__c candidateToSales : candidate.Sales_Candidates__r) {
                candidateToSales.HR_Owner__c = candidate.Job_Application__r.OwnerId;
                candidateToSalesUpdateList.add(candidateToSales);
            }
        }
        if (!candidateToSalesUpdateList.isEmpty()) {
            update candidateToSalesUpdateList;
        }
    }

    public static void getRecruitmentTeamForUpdate(Case newCase, Case oldCase) {
        if (newCase.RecordTypeId.equals(JOB_APPLICATION_ID) && String.isNotBlank(newCase.Recruitment_Team__c)
                && (oldCase == null
                || ((newCase.Status.equals(BTN_ConstantRepo.CASE_STATUS_OPEN) || newCase.Status.equals(BTN_ConstantRepo.CASE_STATUS_RECOMMENDED))
                && BTN_UTIL_SObject.hasSObjectFieldChanged(oldCase, newCase, Case.Status)))) {
            recruitmentTeamIdsForUpdate.add(newCase.Recruitment_Team__c);
        }
    }

    public static void setCurrentRecruitmentAcceptanceCheckbox(Case newCase) {
        newCase.Current_Recruitment_Acceptance__c = newCase.Current_Recruitment_Acceptance_Datetime__c != null ? true : false;
    }

    private static Boolean isInternalOnboardingCase(Case newCase) {
        Id internalOnboardingRecordTypeId = BTN_RecordTypeUtils.getRecordTypeCaseInternalOnBoarding().Id;
        Id grantAccessRecordTypeId = BTN_RecordTypeUtils.getRecordTypeCaseGrantAccess().Id;
        return (newCase.RecordTypeId == internalOnboardingRecordTypeId ||
                newCase.RecordTypeId == grantAccessRecordTypeId);
    }

    public static List<Case> getJobApplicationCases(List<Case> cases) {
        jobApplicationCases = new List<Case>();
        Set<Id> contactIds = new Set<Id>();
        for (Case newRecord : cases) {
            if (newRecord.RecordTypeId.equals(BTN_RecordTypeUtils.getRecordTypeIdByDeveloperName(Case.getSObjectType(), BTN_RecordTypeUtils.CASE_JOB_APPLICATION_RECORDTYPE))) {
                jobApplicationCases.add(newRecord);
            }
        }
        return jobApplicationCases;
    }

    public static Id getSkipCaseAssignmentRuleId() {
        try {
            Id skipRuleId = [SELECT Id FROM AssignmentRule WHERE SobjectType = :Case.getSObjectType().getDescribe().getName() AND Name = :CASE_ASSIGNMENT_RULE_SKIP_NAME LIMIT 1].Id;
            return skipRuleId;
        } catch (Exception e) {
            System.debug(e.getStackTraceString());
            return null;
        }
    }
    private static Integer calculateCandidateStatusPlaceInOrder(String status) {
        if (status.equals(BTN_ConstantRepo.CANDIDATE_STATUS_DRAFT)) {
            return 0;
        } else if (status.equals(BTN_ConstantRepo.CANDIDATE_STATUS_DELIVERED)) {
            return 1;
        } else if (status.equals(BTN_ConstantRepo.CANDIDATE_STATUS_ACCEPTED)) {
            return 2;
        } else if (status.equals(BTN_ConstantRepo.STATUS_ONBOARDING)) {
            return 3;
        } else {
            return 4;
        }
    }
    private static Boolean candidateStatusCanBeChanged(String newStatus, String oldStatus) {
        return calculateCandidateStatusPlaceInOrder(newStatus) > calculateCandidateStatusPlaceInOrder(oldStatus);
    }
    public static Case getLastOnboardingOrGrantAccessCaseForContact(Id contactId) {
        List<Case> cases = [
                SELECT Id
                FROM Case
                WHERE ContactId = :contactId
                AND (RecordType.DeveloperName = :BTN_RecordTypeUtils.CASE_INTERNAL_ONBOARDING_RECORDTYPE
                OR RecordType.DeveloperName = :BTN_RecordTypeUtils.CASE_GRANT_ACCESS_RECORDTYPE)
                AND Status = :BTN_ConstantRepo.CASE_STATUS_OPEN
                ORDER BY CreatedDate DESC
                LIMIT 1
        ];
        if (!cases.isEmpty()) {
            return cases[0];
        } else {
            return null;
        }
    }
}