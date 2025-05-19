## Start Contributing

1. Create a fork of the repo for yourself.
1. Search for the issue if raised before or open a new one, and make sure it will be accepted.
1. Make your development on your fork and open a pull request.
1. Please use conventional commits, as it looks like we probably will be using changelog generators to parse commits to say what's changing on newer versions.
1. Check workflow results for the tests on your PR and make sure it's all succeed, otherwise please fix the problems.
1. Wait for the review and approval

## How to locally develop

1. It is non-trivial to have `kcov` installed since we use it to perform coverage tests. Please refer to the [kcov installation manual](https://github.com/SimonKagstrom/kcov/blob/master/INSTALL.md)
1. Clone the project to your local.
1. Make sure you have zig installed as the same version with what is defined in [build.zig.zon](build.zig.zon) file of the project's master branch as `minimum_zig_version`.

Testing `Tase` might be tricky since it's a cron-based scheduled daemon service. Here's some information:

1. Write unit tests for each unit your are changing if possible. If there's already a unit test for that part, make sure it covers your new addition.
   - `zig build test` for unit testing.
   - `zig build cover` for coverage test.
   - Check coverage test results in `zig-out/cover/test/index.html`
1. If you changing a part that is not possible to unit test, might be a daemon action triggered via cron etc. Then maybe you can use E2E testing via containers located in: [app-test-container](app-test-container/start-test.sh)
   - This test requires a container engine like podman or docker to run. Make sure either one of two is installed.
   - If first time make sure you run it with `build` argument so that initial container images can be build like so: `app-test-container/start-test.sh build`
   - This container always run 10 seconds far from midnight `21-12-2012` so any cron will get triggered in 10 seconds after master server container is up.
1. There's also 1 more other script that starts both master and an agent on local machine directly, called `scripts/start-development.sh`.
   - This script starts a master server locally on default port `7423` and another agent on port `7424`. Master server is pointed to the config on root level called `app.yaml`, so this file should be configured to trigger the cron and cover the usage.
   - This is generally harder because all log dirs should be hand created and populated, then `app.yaml` should be adjusted accordingly. This also uses no `faketime` so, it relys on system time which means on every run, cron expression should be updated to match.
