package com.zuhoocms.auth.impersonation;

public interface ImpersonationService {

    ImpersonationResponse startImpersonation(Long companyId, ImpersonateRequest request);

    void endImpersonation(EndImpersonationRequest request);
}
