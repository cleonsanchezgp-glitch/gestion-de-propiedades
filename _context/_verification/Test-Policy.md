# Aelium - Organizational Test Policy

> Local project copy provisioned from the Qualitas default Organizational Test Policy. This document is the organizational testing policy for Aelium as applied to this property management project.

---

## Document Control

| Field | Value |
| --- | --- |
| Document ID | QA-POL-001 |
| Title | Aelium Organizational Test Policy |
| Version | 1.0 |
| Status | Draft - for review |
| Owner | Aelium Quality Engineering |
| Approver | Aelium Quality Governance |
| Effective date | 2026-09-10 |
| Review cadence | Annual, or sooner if Aelium's risk profile or regulatory context changes materially |
| Conformance | ISO/IEC/IEEE 29119-3:2021 Section 9 |
| Source | Aelium Organizational Test Policy, QA-POL-001 v1.0; user-designated reference: CRM/_context/_verification/Test-Policy.md |
| Copied on | 2026-10-02 |

---

## 1. Introduction

This policy defines the highest-level testing principles that apply to software products and automation services built or operated by Aelium. It states what must hold true for testing across the organization; detailed test levels, techniques, tools, entry criteria, exit criteria, and evidence handling are defined in the Organizational Test Strategy and project-level Test Management Plans.

**Applies to:** testing performed for Aelium products, internal tools, customer-facing automation services, integrations, data handling, and supporting platforms.

**Does not apply to:** specific tool configuration, implementation tasks, or project-specific release plans.

---

## 2. Test Policy Statement

Aelium ships changes only when there is evidence, proportionate to risk, that they meet their intended purpose without compromising the integrity, security, privacy, or reliability of the product and its data. Testing is planned from the same moment as the requirement and remains traceable through delivery, release, and operational learning.

---

## 3. Objectives of Testing

1. Provide evidence-based confidence that each change is fit for its intended business purpose before it reaches users.
2. Make quality, readiness, and residual risk visible at decision points.
3. Verify products against the ISO/IEC 25010:2023 quality characteristics that matter for the change, including functional suitability, performance efficiency, compatibility, interaction capability, reliability, security, maintainability, flexibility, and safety.
4. Protect the product quality baseline as products evolve.
5. Feed defects, incidents, and support signals back into future testing and requirements work.

---

## 4. Test Process

Aelium structures testing across three layers:

- **Organizational layer:** this Test Policy, the Organizational Test Strategy, and periodic test process improvement.
- **Management layer:** project or release-specific test planning, monitoring, control, and completion reporting.
- **Dynamic layer:** test design, test environment setup, test execution, incident reporting, retesting, regression testing, and evidence capture.

Each project applies these layers in proportion to product risk, data sensitivity, customer impact, and operational criticality.

---

## 5. Test Organization Structure

Testing is embedded in delivery by default: the person or team that builds a change is responsible for testing it and producing evidence. Independent review is required for changes that affect authentication, authorization, customer data, financial records, irreversible operations, security posture, or production-critical integrations.

As Aelium grows, this structure should be revisited before adding heavier governance mechanisms. The goal is accountable testing with enough independence for the risk involved.

---

## 6. Tester Training

Anyone performing testing for Aelium is expected to understand the relevant product domain, the project requirements, the applicable test levels, the ISO/IEC 25010 quality characteristics, and the handling requirements for personal or customer data. For small projects this may be self-directed and reviewed during onboarding; for higher-risk projects competency expectations must be documented in the Test Management Plan.

---

## 7. Tester Ethics

Testing results must be reported accurately regardless of delivery pressure. Known risks, failed checks, missing evidence, or unverified assumptions must not be hidden. Any real, production-like, or customer data encountered during testing must be treated with the same confidentiality and protection obligations as operational data.

---

## 8. Standards

This policy and downstream testing artefacts are aligned with:

- **ISO/IEC/IEEE 29119-2:2021** - test process structure.
- **ISO/IEC/IEEE 29119-3:2021** - test documentation, including Test Policy, Test Strategy, and Test Management Plan.
- **ISO/IEC 25010:2023** - software product quality characteristics.
- **ISO/IEC 12207:2017** - software life-cycle process context.

---

## 9. Other Relevant Policies

Testing must respect applicable Aelium policies for data protection, information security, access control, customer confidentiality, incident handling, and retention. Where a referenced policy does not yet exist formally, the relevant obligation must be made explicit in the project Test Management Plan rather than assumed.

---

## 10. Measuring the Value of Testing

Aelium measures the value of testing through evidence that testing reduces business and operational risk: prevented defects, escaped defects, time from defect introduction to detection, regression health, critical path coverage, and incident learning. These signals are reviewed at least quarterly for active products and after material production incidents.

---

## 11. Test Asset Archiving and Reuse

Test cases, test data definitions, automation scripts, execution logs, incident reports, and completion evidence must be retained long enough to support traceability, audit, maintenance, and future regression use. Reusable assets should live alongside the code or documented authority they verify, so the relationship between a change and its evidence can be reconstructed.

---

## 12. Test Process Improvement

Testing practice is improved through retrospective findings, escaped defects, incident analysis, user feedback, and periodic review of the Test Strategy and project-level Test Management Plans. Material changes to this policy are recorded in the Change Log.

---

## Provisioning Note

CRM was designated by the user on 2026-10-02 as the reference for this project. Its source documents are local copies derived from Qualitas defaults. Their Draft - for review status and original change history are preserved; this provisioning does not claim organizational approval or establish a new canonical source.

## Related Documents

- Organizational Test Strategy - constrained by this policy.
- Project Test Management Plans - constrained by this policy and the strategy.
- Qualitas default Organizational Test Policy - source default.

---

## Change Log

| Date | Version | Change | Author |
| --- | --- | --- | --- |
| 2026-09-10 | 1.0 | Initial Aelium policy provisioned from the Qualitas default policy | Lex |
