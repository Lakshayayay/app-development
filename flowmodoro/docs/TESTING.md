# Testing

The unit tests cover timer mathematics and statistics without a network or a real clock dependency. The production timer accepts explicit `Date` values on its transition methods, making sleep/wake reconstruction testable. UI tests should exercise:

- launch → create/select task → start → pause → resume → stop;
- Flowmodora stop → calculated break → start break;
- Pomodoro work → break → next work;
- history/statistics windows from the menu-bar popover.

Failure-oriented manual checks should include denied notification permission, failed login-item registration, unavailable network, process relaunch with a running snapshot, and a countdown target that passed while the popover was closed.
