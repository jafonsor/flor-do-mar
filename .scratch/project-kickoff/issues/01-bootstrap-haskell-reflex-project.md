# Bootstrap Haskell Reflex Project

Status: ready-for-agent

## Summary

Create the initial Haskell project skeleton for Flor do Mar, including a Reflex browser client entry point and a shared combat library.

## Background

Flor do Mar uses Haskell for all first-party code. The browser client targets Reflex / reflex-dom. Combat simulation should be testable outside the browser.

## Scope

- Add the initial build configuration.
- Create a browser client package or app for Reflex / reflex-dom.
- Create a shared combat module or package that does not depend on browser APIs.
- Add a minimal test target for combat code.
- Document how to build and run the local client.

## Acceptance Criteria

- The project has a reproducible Haskell build entry point.
- A minimal Reflex browser page can be started locally.
- A combat module can be imported by the browser client.
- Combat tests can run without opening a browser.
- The README or equivalent local notes explain the build and run commands.

## Notes

Defer rich UI, WebGL rendering, and combat rules to later issues. This issue is about getting the skeleton upright.
