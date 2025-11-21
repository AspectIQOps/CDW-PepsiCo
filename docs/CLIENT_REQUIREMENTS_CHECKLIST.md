# Client Requirements for 100% SOW Compliance

**Quick Reference Checklist**

---

## ❌ BLOCKERS (Must Have for Production)

- [ ] **AppDynamics Licensing API Permissions**
  - Grant "License Admin" role to OAuth clients on all PROD controllers
  - Required on: pepsico-prod, pepsicoeu-prod (pepsi-prod has permission but API returns 500)

- [ ] **AppDynamics Licensing API v1 Availability**
  - Verify Licensing API v1 is enabled on PROD controllers
  - Contact AppDynamics support if API returns 500 errors
  - Confirm agent-based vs infrastructure-based licensing model

- [ ] **H-Code Tags (90%+ coverage)**
  - Tag applications in AppDynamics with h-code values
  - Tag format: `h-code`, `h_code`, or `hcode`
  - Target: >90% of applications tagged

- [ ] **ServiceNow Production Credentials**
  - OAuth Client ID & Secret with CMDB read permissions
  - PROD ServiceNow instance URL

---

## ℹ️  NOTES

**Priority:** All items above are BLOCKERS for 100% SOW compliance

**Timeline:** These must be provided before production go-live

**Support:** We provide test scripts and step-by-step guides for all requirements
