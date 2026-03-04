# How to contribute

Thank you for your interest in the Ansible for OpenShift Virtualization Migration! \
Please make sure you have submitted the [Onboarding form](https://forms.gle/jVgu1jS4vNxjn6me7) to have access to all related resources.

## Important links
[Ansible for OpenShift Virtualization Migration Overview](https://docs.google.com/document/d/1pX3uc3x1TYLkOSGMRkT6e_LQC921VVNwcmM8S8YF1io)
\
Slack channel [#forum-virt-migration-factory](https://redhat.enterprise.slack.com/archives/C06U4TQHJSF)
\
Jira project [MFG](https://issues.redhat.com/projects/MFG/)
\
[BitWarden collection](https://vault.bitwarden.com/#/vault?organizationId=cd864c42-0667-4521-afb0-aae600ef844c&collectionId=f6c0e1c5-2e7c-41ab-90fc-b21a00758b21)
\
[Feature/Use case](https://docs.google.com/forms/d/e/1FAIpQLSfKQzd1eQomLCkj3yrfTUFNaon4gfP-TwqWtEp0U6mhk0_nVA/viewform) request form
\
[Documentation](https://github.com/redhat-cop/openshift-virtualization-migration/documentation) repository
\
[Collections](https://github.com/redhat-cop/openshift_virtualization_migration) repository
\
[Execution Environments](https://github.com/redhat-cop/openshift_virtualization_migration_ees) repository

# Environment setup and tools
The expectation for development is that it will be done using VScode. If you use a different IDE you will have to ensure that you have a process for validating the code using ansible-lint prior to merging.
* Python virtual environment
  * python3 -m venv .venv
  * source .venv/bin/activate
  * pip3 install ansible-core==2.15 ansible-lint
* Ansible deps
  * ansible-core == 2.15
  * ansible-lint
* Python deps
  * Python >= 3.9 
* VScode and plugins
  * Some of these configurations should be inherited automatically with the inclusion of the .vscode folder in the repository. These top level settings should be limited to minimum necessary plugins and settings. User preferences should be stored outside the code base.
  * Plugins
    * ms-python.python
    * redhat.ansible
    * Ms-python.black-formatter
* Git Config & Setup
  * git config --global user.email "you@email.com"
  * git config --global user.name "Your Name"
* Developer Workspace
  * When working with a repository that has a devfile.yaml, you can launch the workspace and modify code directly from your web browser

## Contribute using Red Hat Developer Sandbox

NOTE: You will need to create a GitHub personal access token and add that to your Developer Sandbox profile.

To configure your developer sandbox perform the following steps:
1. Navigate to [Red Hat Developer Sandbox](https://developers.redhat.com/developer-sandbox) and click the red button labeled, 'Start your sandbox for free'
2. Once started this will take you to the Red Hat Hybrid Console screen that has a box for Red Hat Dev Spaces, click the 'Launch' button in that box
3. In the top right, click your username and select 'User Preferences'
4. Inside of the User Preferences screen, select the top navigation bar button for, 'Personal Access Tokens'
5. Click the, 'Add Token' option in the top right
6. Pick a unique name such as 'github-token' in the Token Name field
7. Select **GitHub** for the Provider Name
8. Under GitHub Provider Endpoint enter 'https://github.com'
9. Paste a [GitHub Personal Access Token](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens) into the Token field.
10. Click the link below to launch your IDE hosted in the Developer Sandbox on the project:

[![Contribute](https://www.eclipse.org/che/contribute.svg)](https://workspaces.openshift.com/f?url=https://github.com/redhat-cop/openshift_virtualization_migration.git)

# Forking / Branching / Merging

## Creating a fork
1. Create a fork inside your GitHub account: 
   1. Go to the repository you want to contribute to.
   2. Click the **Fork** button in the top right corner.
   3. Select your GitHub account as the destination.
   4. Clone your new fork locally.
2. Create a branch inside your forked repository with a proper name.
3. Make your code changes and push to your branch.
4. Make sure you have the necessary access to the repository. If you are not part of the required GitHub teams, please message asking to be added in the [#forum-virt-migration-factory](https://redhat.enterprise.slack.com/archives/C06U4TQHJSF) Slack channel.
5. Create a **Pull Request (PR)** to the main repository (it can be a draft).
6. Pull Request titles should follow the commit message standards (outlined below).
7. GitHub Actions will run the pipeline using the main repository's infrastructure.
8. When ready, mark the Pull Request as "Ready for review"!

## Releases and tags
* While we strive to have the main branch fully functional as-is, we are limited in automated testing due to the requirements of the test infrastructure. As such, manual testing is required to validate the state of the collection. This single branch development strategy may change in the future, but to minimize the contribution complexity and changes to workflows already established it will stay this way for now.
* [Semantic Release](https://python-semantic-release.readthedocs.io/en/latest) is used for releasing and tagging. It is configured in the repository using the `pyproject.toml`.

## Code Standards
  * Ansible lint show no issues
  * Variable naming
  * Follow [Good Practices for Ansible](https://redhat-cop.github.io/automation-good-practices/) guidelines
    * [Variables are properly named](https://ansible.readthedocs.io/projects/lint/rules/var-naming/) and [leverage imlicit collection variables in role defaults](https://redhat-cop.github.io/automation-good-practices/#_create_implicit_collection_variables_and_reference_them_in_your_roles_defaults_variables)
    * ["Magic Values" not stored in code but rather in vars/main.yml](https://redhat-cop.github.io/automation-good-practices/#_vars_vs_defaults)
    * [All arguments accepted from outside the role given default value in defaults/main.yml](https://redhat-cop.github.io/automation-good-practices/#_vars_vs_defaults)
    * [Prefix task names in sub-tasks files of roles](https://redhat-cop.github.io/automation-good-practices/#_prefix_task_names_in_sub_tasks_files_of_roles)
    * [Debug statements include appropriate verbosity parameter](https://redhat-cop.github.io/automation-good-practices/#_use_the_verbosity_parameter_with_debug_statements)
    * Create roles as a rule, single playbooks should only contain a few simple tasks
    * Use `ansible.builtin.import_role` or `ansible.builtin.include_role` to enable the use of `tasks_from:`
  * Do NOT commit any passwords, tokens, secrets or any other sensitive information to any repositories. The process to purge these is a lot of work and can result in data breach. It is best to save any secrets files outside any local repositories, vault them, and just in case add them to .gitignore.

## Documentation

  * Documentation generation tool hints are included in defaults/main.yml for each variable (title, required and description) [as seen in this example](https://github.com/docsible/thermo-core/blob/main/defaults/main.yml). These hints are processed by Docsible for automatic Collection and Role README generation.
  ```yaml
  # title: Minimum temperature required for energy generation (in °K)
  # required: True
  # description: The minimum core temperature required to initiate the energy synthesis process.
  min_temperature_threshold: 4000

  # title: Target pressure for optimal energy generation (in Pa)
  # required: True
  # description: Optimal pressure setting for ThermoCore to maximize energy output under safe conditions.
  optimal_pressure_threshold: 4500
  ```

  * Collection fragment added to changelogs/fragments/< Jira Task >.yml [documentation here](https://ansible.readthedocs.io/projects/antsibull-changelog/changelogs/)
    * Example changelog fragment: [changelogs/fragments/MFG-282.yml](https://github.com/redhat-cop/openshift_virtualization_migration/blob/main/changelogs/fragments/MFG-282.yml)
  ```yaml
  ---
  minor_changes:
    - Add argument_specs to migration_targets role

  bugfixes:
    - Variable migration_target_speial_sauce spelling fixed to migration_target_special_sauce
  ...
  ```

## Testing and Reliability
  * Role(s) work in [Check Mode](https://redhat-cop.github.io/automation-good-practices/#_check_mode)
  * [Roles include argument validation in meta/argument_specs.yml](https://redhat-cop.github.io/automation-good-practices/#_argument_validation)
  * Automation is [idempotant](https://redhat-cop.github.io/automation-good-practices/#_idempotency)

## Rules and policies

### Changes to the main branch
  * No direct pushes to the main branch are permitted. All changes should originate through a merge request.
  * Merges should not be approved prior to pipeline completion
  * The pipeline is a data point to be considered prior to approving a merge, but should not be the sole deciding factor. Pipeline testing is very limited in coverage due to the constraints around testing infrastructure.
  * Code quality findings should be considered prior to approval. Merging code with new findings is not strictly prohibited but is discouraged to minimize the accumulation of technical debt over time.
  * Merges should be reviewed by and approved by at least one other person with Developer and/or Maintainer permissions.
  * Clicking the ‘Merge’ button can be done by the submitter if the merge request has been reviewed and approved as outlined above.

### Pipeline failures
  * The pipelines can and do fail for reasons other than the code submitted. If the pipeline fails and it is not clear why it did, or how to resolve the issue, notify the forum-virt-migration-factory channel with a link to the failed pipeline.
  * Pipeline not running in my forked project
    * Forks of the project will include the GitLab CI configuration from the main repository. So it will attempt and fail to run in forks outside the collection group. These can be safely ignored as the pipeline will still run once a merge request has been submitted back to the main repository.
    * When you create a merge request (it can be a draft) to the main repository a pipeline will be created. This pipeline will be available for inspection and details in the Main Repository not in your fork.
    * If that pipeline shows as “Stuck” then you may be missing the necessary permissions on the main repository. Only those users with ‘Developer’ and ‘Maintainer’ level permissions are able to run a pipeline against the main branch.
  * Code quality findings
    * The pipeline runs ansible-lint against the entire code base to identify fixed and new findings using the most strict standard.
    * Ansible-lint set to maximum enforcement can be very particular and identify functional code as a problem. The contributor should strive to minimize the number of findings by applying best practices (style, naming and functionality) where possible. In the case of a false finding, it is preferred to disable specific findings using the [inline “noqa” feature of ansible-lint](https://ansible.readthedocs.io/projects/lint/usage/#muting-warnings-to-avoid-false-positives).
    * Findings already in the code base should not be displayed as part of the code quality findings, so anything identified in the report is the responsibility of the contributor to address.

### Commit message standards
* Commit messages should start with one of the options below, followed by the [Migration Factory project](https://issues.redhat.com/projects/MFG) Jira ticket ID when available and a short description of the change. See the structure and example below:

```
<type>: [JIRA ID] <short summary>
    │        |         │
    │        |         └─⫸ Summary in present tense. Not capitalized. No period at the end.
    |        |
    |        └─⫸ Jira ticket ID from Red Hat Jira Migration Factory project
    │
    └─⫸ Commit Type: feat | fix | perf | build | chore | ci | docs | style | refactor | test

Example: 
Fix: MFG-205 Add argument_specs to migration_targets role
```

* Often there are times when multiple commits are needed to test different ways of doing something, and in this case the prefix ‘test:’ can be used. This is done to exclude these commits from changelog consideration. The assumption here is that the intent of the change has or will be captured in another commit using the standard prefixes.

### Testing
* Ensure your code passes lint locally to prevent needless pipeline runs only to catch simple linting errors
* For new code, ensure detailed instructions are included in the MR on how to test it and any potential impacts to existing code
* Verify pipeline success and add it to your MR for others to view success

### Merge title and description
* Merge request titles and commit messages should start with one of these three options, ‘Fix:’, ‘Feature:’, or ‘BREAKING CHANGE:’

## Code of conduct
* Everyone contributing to this effort is volunteering time between all their other commitments. Be respectful and patient.

## Documentation Guidelines
[TBD]

## Troubleshooting
[TDB]

## FAQ
How to get help
* Slack channel [#forum-virt-migration-factory](https://redhat.enterprise.slack.com/archives/C06U4TQHJSF)


