# platform-sre-code-test

## Overview

Hello, candidate!

We have prepared a task to showcase your ability to design and implement a build and
deployment process/platform for an application.

The scenario:

A new junior developer has handed off a "production ready" python web service. It is up to you ensure the web service is properly
built, deployed, and secured in production.

The rules:

1. The web service should be containerized.
2. Assume the BigQuery dataset referenced by `app.py` is an internal dataset that will need to be authenticated against.
3. The app will need to support multiple instances for different query parameters (different `WORD` values).
4. A local development and mock-production deployment and environment should be supplied (everything running locally is acceptable).
5. Minimal human intervention should be required for deploying through to each environment.
6. Thorough documentation should be supplied.
7. Use your Git commits as a working journal to show your iterations and reasoning.

Beside the below rules, you are free to invent requirements to showcase your style or tooling to suit your fancy.

We want to see the extent of your build and deployment platform design, its usability by others, and the infrastructure and security
pieces put in place. There are no tricks here: we're not planning to judge on tooling choice, speed, project organization, extra
features, or any other secret requirement; but we'd love to see any of those and hear your motivations.

We respect your time. No more than 4–6 hours should be spent on this exercise unless you genuinely want to explore further. We are
not evaluating how many hours you put in, only your approach.

Feel free to reach out via email for clarifications or questions to [platform.engineer.hiring@unizin.org](mailto:platform.engineer.hiring@unizin.org).

Good luck!

## Instructions

1. Clone this repository and start a branch. You do not need to fork it to your own account.
2. Satisfy "the rules" from above.
3. Submit a GitLab merge request (same as what GitHub calls a pull request) at least 24 hours before your interview.
