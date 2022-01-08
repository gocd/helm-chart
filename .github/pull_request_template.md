<!--
 Thanks for contributing!

 Please check the following for your pull request to be reviewed and merged.

 - Describe what you are trying to achieve
 - Let us know what you have tested
 - Let us know about any possibly breaking changes or things you are not sure of
 -->

**Description**

<!-- What are you trying to achieve with this change? What problem does it solve for users? -->

**Relevant issues**

<!-- Link any issues it closes/fixes using #) -->
- fixes #

**Possible challenges**

<!-- Is this a breaking change? Are there things you're not sure of? -->

**Additional information**

<!-- Anything else we should know? -->

**Checklist**
<!-- 
 [Place an '[X]' (no spaces) in all applicable fields. Please remove unrelated fields.]
 GoCD uses quasi-[semver](http://semver.org/)
 - Bump the major version if this is a breaking change to the chart that won't work with people's existing values.yaml or will add/remove resources in ways that potentially alter or degrade behaviour for their GoCD server/agent.
 - Generally we ony bump minor version for new GoCD versions
 - Bump the patch version for fixes or enhancements to the chart itself
-->
- [ ] Chart version bumped in `Chart.yaml`
- [ ] Any new variables have documentation and examples in `values.yaml`, even if commented out
- [ ] Any new variables added to the `README.md`
- [ ] Squash into a single commit (or explain why you'd prefer not to), except...
- [ ] ...additional commit added for `CHANGELOG.md` entry
- [ ] Helm lint + tests passing? <!--(you may need to wait for a maintainer to approve running your workflow)-->
