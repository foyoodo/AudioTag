<div align="center">
  <img src="AudioTag/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon_512x512@2x.png" width="150" height="150" alt="AudioTag logo">
  <h1>AudioTag</h1>
  <p>Audio metadata editor for macOS powered by TagLib<br /></p>

[![AGPL v3](https://shields.io/badge/License-AGPL%20v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0.en.html)

</div>

![Screenshot](assets/preview.png)

## Features

- Native user interface built with [SwiftUI](https://developer.apple.com/xcode/swiftui/).

## Requirements

- macOS 14.0 (or newer)
- Xcode 16.0 (or newer)

## Building

### Get the Code

```bash
git clone https://github.com/foyoodo/AudioTag.git
```

### Install [Tuist](https://github.com/tuist/tuist)

#### [Mise](https://github.com/jdx/mise) (Recommended)

Install Mise (Optional)

```bash
brew install mise
```

Open the project folder in your terminal, then

```bash
mise install
```

#### Homebrew

```bash
brew install tuist@x.xx.x # version in .mise.toml
```

### Generate .xcworkspace file

```bas
tuist install
tuist generate --no-binary-cache
```

### Build and Run

<kbd>⌘ Command</kbd> + <kbd>R</kbd>

## License

AudioTag and its components is shared on [AGPL v3](https://www.gnu.org/licenses/agpl-3.0.en.html) license.
