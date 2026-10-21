# Aelium - Organizational Test Strategy

> Local project copy provisioned from the Qualitas default Organizational Test Strategy. This strategy is derived from and constrained by the Aelium Organizational Test Policy.

---

## Document Control

| Field | Value |
| --- | --- |
| Document ID | QA-STR-001 |
| Title | Aelium Organizational Test Strategy |
| Version | 1.0 |
| Status | Draft - for review |
| Owner | Aelium Quality Engineering |
| Approver | Aelium Quality Governance |
| Effective date | 2026-09-10 |
| Review cadence | Annual, or sooner if the risk landscape or technology stack changes materially |
| Conformance | ISO/IEC/IEEE 29119-3:2021 Section 10 |
| Parent document | [Organizational Test Policy](Test-Policy.md) (QA-POL-001) |
| Source | Aelium Organizational Test Strategy, QA-STR-001 v1.0; user-designated reference: CRM/_context/_verification/Test-Strategy.md |
| Copied on | 2026-10-02 |

---

## 1. Introduction

Where the Test Policy states what must hold true, this strategy states how Aelium meets it. It defines default test levels, risk-based selection, documentation expectations, automation approach, environment expectations, incident handling, metrics, and regression practice. Project-specific decisions are documented in each Test Management Plan.

---

## 2. Project-Wide Organizational Test Strategy Statements

Every Aelium project starts from the following default test levels unless its Test Management Plan documents a justified deviation.

| Level | Purpose |
| --- | --- |
| Unit | Verify individual functions, modules, and components in isolation. |
| Integration | Verify interactions between frontend, backend, database, and external services. |
| System / End-to-end | Verify complete user and operational flows across the deployed system. |
| Acceptance | Confirm the change satisfies its intended business outcome. |

Functional correctness is always in scope. Non-functional testing is selected according to risk, with particular attention to security, reliability, performance, maintainability, compatibility, and interaction capability for customer and business data systems.

---

## 3. Generic Risk Management

Test effort is allocated in proportion to risk.

| Risk tier | Trigger examples | Minimum test depth |
| --- | --- | --- |
| Critical | Authentication, authorization, customer data, financial records, irreversible operations, production integrations | All levels, full relevant non-functional scope, mandatory independent review |
| High | Cross-module workflows, shared data model changes, high-use screens, broad API changes | Unit, integration, system coverage, targeted non-functional scope, regression update |
| Medium | Contained module feature, report, filter, or editable business flow | Unit, integration, focused system or acceptance coverage |
| Low | Copy, styling, isolated configuration, low-blast-radius change | Smoke and regression checks |

The risk tier drives test scope, evidence expectations, environments, entry criteria, and exit criteria.

---

## 4. Test Selection and Prioritization

Critical and High risk paths are tested before Medium and Low risk paths. A failed Critical or High risk check blocks progression until the failure is understood, accepted with documented mitigation, or fixed and retested.

---

## 5. Test Documentation and Reporting

Projects produce enough documentation for a reviewer to understand what was tested, what evidence exists, what failed, what risk remains, and what decision was made. Test reports must state conclusions directly rather than relying only on linked tickets or raw logs.

---

## 6. Test Automation and Tools

Aelium defines approved tool categories rather than fixed vendors: test management, CI execution, unit test framework, integration and API testing, UI testing, performance checks, security scanning, defect tracking, and evidence storage. Automated regression is expected for Critical and High risk paths.

---

## 7. Configuration Management of Test Work Products

Test cases, test data definitions, and automation scripts are versioned with the source they verify whenever practical. Test evidence is retained according to the Test Policy and linked from the project Test Management Plan or traceability artefacts.

---

## 8. Incident Management

Incidents found during testing are classified by type and severity, assigned to an owner, tracked to closure, and retested before being considered resolved. Critical incidents must preserve enough evidence to support root-cause analysis.

---

## 9. Test Subprocesses

| Subprocess | ISO/IEC 29119-2 clause | Aelium expectation |
| --- | --- | --- |
| Test design and implementation | Section 7.3 | Tests trace to requirements, risks, or acceptance criteria. |
| Test environment setup and maintenance | Section 7.4 | Environments are checked before execution starts. |
| Test execution | Section 7.5 | Raw results are captured before interpretation. |
| Test incident reporting | Section 7.6 | Incidents include impact, severity, evidence, and next action. |
| Test completion | Section 7.7 | Completion is declared with evidence and residual risk. |

---

## 10. Test Sub-Process-Specific Statements

- **Design:** every test case traces to a requirement, risk, or acceptance criterion.
- **Environment:** readiness is checked explicitly before execution.
- **Execution:** actual results are recorded, including failed and blocked checks.
- **Incident reporting:** each incident has severity, reproduction information, and an owner.
- **Completion:** a phase is not complete while open Critical incidents remain.

---

## 11. Entry and Exit Criteria

| Level | Entry (minimum) | Exit (minimum) |
| --- | --- | --- |
| Unit | Code ready for local verification; expected behavior understood | Unit checks pass or deviations are documented |
| Integration | Build available; dependent services and database schema available | No open Critical or High integration incidents |
| System / End-to-end | Integration exit met; representative data available | Priority flows pass; regression impact assessed |
| Acceptance | Acceptance scenarios agreed; known risks visible | Sign-off or rejection recorded with evidence |

---

## 12. Test Completion Criteria

Testing for a release or phase is complete when planned test levels meet exit criteria, no open Critical incidents remain, evidence is retained, and residual risk is stated clearly.

---

## 13. Degree of Independence

The delivery team tests its own work by default. Independent review is required for Critical risk changes and recommended for High risk changes involving customer data, financial data, security, or irreversible state changes.

---

## 14. Test Design Techniques

Aelium uses techniques selected by risk and feature shape, including equivalence partitioning, boundary value analysis, decision tables, state transition testing, scenario-based testing, API contract testing, and exploratory testing.

---

## 15. Test Environment

Project Test Management Plans define environments per test level. Critical paths require production-like configuration for relevant integration, security, and reliability validation. Test data must avoid unnecessary exposure of real personal or customer data.

---

## 16. Metrics to be Collected

- Coverage against risk-based scope.
- Requirement and acceptance-criteria coverage.
- Defect detection rate and escaped-defect rate.
- Pass, fail, blocked, and retest rates.
- Regression baseline health.

---

## 17. Retesting and Regression Testing

A defect fix is retested with the original failing case. Critical or High risk fixes also trigger regression coverage over the affected module and adjacent workflows before release.

---

## Provisioning Note

CRM was designated by the user on 2026-10-02 as the reference for this project. Its source documents are local copies derived from Qualitas defaults. Their Draft - for review status and original change history are preserved; this provisioning does not claim organizational approval or establish a new canonical source.

## Related Documents

- [Organizational Test Policy](Test-Policy.md) - parent.
- Project Test Management Plan - downstream.
- Qualitas default Organizational Test Strategy - source default.

---

## Change Log

| Date | Version | Change | Author |
| --- | --- | --- | --- |
| 2026-09-10 | 1.0 | Initial Aelium strategy provisioned from the Qualitas default strategy | Architectus |
