# Traits

Choose which Web API groups and runtime features swift-slack compiles.

## Overview

swift-slack uses Swift package traits to make parts of the package optional. Each Web API method group is a trait, so you can compile only the operations your app calls and reduce build times.

By default, every trait except `HummingbirdHTTPAdapter` is enabled. When you list traits explicitly, only the traits you list (and the traits they imply) are enabled:

```swift
.package(
    url: "https://github.com/ainame/swift-slack.git",
    from: "2026.10.2",
    traits: ["WebAPI_Chat", "WebAPI_Views"]
)
```

To keep the defaults and add an optional trait, include `.defaults`:

```swift
.package(
    url: "https://github.com/ainame/swift-slack.git",
    from: "2026.10.2",
    traits: [.defaults, "HummingbirdHTTPAdapter"]
)
```

## Web API Traits

Each trait enables the operations for one group of Slack Web API methods:

| Trait | Slack methods |
| --- | --- |
| `WebAPI_Admin` | `admin.*` |
| `WebAPI_Agents` | `agents.*` |
| `WebAPI_Api` | `api.test` |
| `WebAPI_Apps` | `apps.*` |
| `WebAPI_Assistant` | `assistant.threads.*` |
| `WebAPI_Auth` | `auth.*` |
| `WebAPI_Blocks` | `blocks.*` |
| `WebAPI_Bookmarks` | `bookmarks.*` |
| `WebAPI_Bots` | `bots.*` |
| `WebAPI_Calls` | `calls.*` |
| `WebAPI_Canvases` | `canvases.*` |
| `WebAPI_Chat` | `chat.*` |
| `WebAPI_Conversations` | `conversations.*` |
| `WebAPI_DND` | `dnd.*` |
| `WebAPI_Emoji` | `emoji.*` |
| `WebAPI_Entity` | `entity.*` |
| `WebAPI_Files` | `files.*` |
| `WebAPI_Functions` | `functions.*` |
| `WebAPI_Lists` | `slackLists.*` |
| `WebAPI_Migration` | `migration.*` |
| `WebAPI_OAuth` | `oauth.*` |
| `WebAPI_OpenID` | `openid.connect.*` |
| `WebAPI_Pins` | `pins.*` |
| `WebAPI_Reactions` | `reactions.*` |
| `WebAPI_Reminders` | `reminders.*` |
| `WebAPI_Search` | `search.*` |
| `WebAPI_Stars` | `stars.*` |
| `WebAPI_Team` | `team.*` |
| `WebAPI_Tooling` | `tooling.*` |
| `WebAPI_Usergroups` | `usergroups.*` |
| `WebAPI_Users` | `users.*` |
| `WebAPI_Views` | `views.*` |
| `WebAPI_Workflows` | `workflows.*` |

A method is generated only when java-slack-sdk has a recorded response for it, so a group may not include every method Slack documents.

## Feature Traits

- `SocketMode`: Enables Socket Mode in `SlackApp` and `SlackKit`. It also enables `WebAPI_Apps`, which Socket Mode uses to open connections.
- `Events`: Enables Events API payload types and `Router.onEvent(_:handler:)` in `SlackApp` and `SlackKit`.
- `HummingbirdHTTPAdapter`: Enables `HummingbirdAdapter` for serving HTTP apps with Hummingbird. It is not enabled by default.

## Common Configurations

### Web API client

A script that posts messages needs only the chat methods:

```swift
.package(url: "https://github.com/ainame/swift-slack.git", from: "2026.10.2", traits: [
    "WebAPI_Chat",
])
```

### Socket Mode app

An interactive app that receives events, posts messages, and opens modals:

```swift
.package(url: "https://github.com/ainame/swift-slack.git", from: "2026.10.2", traits: [
    "SocketMode",
    "Events",
    "WebAPI_Chat",
    "WebAPI_Views",
])
```

### HTTP app

An app that receives signed HTTP requests through Hummingbird:

```swift
.package(url: "https://github.com/ainame/swift-slack.git", from: "2026.10.2", traits: [
    "HummingbirdHTTPAdapter",
    "Events",
    "WebAPI_Chat",
    "WebAPI_Views",
])
```
