# Neeva for iOS

This repository is a maintained fork of Neeva's open-source iOS browser codebase.

## This branch (main)

The inherited baseline targets Xcode 13.0, Swift 5.5, and iOS 14.0 and above. Modernization work should be scoped and validated incrementally because this browser fork has diverged substantially from upstream Firefox for iOS.

## Building the code

1. Install Xcode developer tools from Apple.
1. Install Carthage, Node, and a Python 3 virtual environment tool for localization scripts:
   ```shell
   brew update
   brew install carthage
   brew install node
   pip3 install virtualenv
   ```
1. Clone this repository:
   ```shell
   git clone https://github.com/outlaw-dame/forked-neeva-ios.git
   ```
1. Pull in the project dependencies:
   ```shell
   cd forked-neeva-ios
   ./bootstrap.sh
   ```
1. Open `Client.xcodeproj` in Xcode.
1. Build the `Client` scheme in Xcode.

## Building User Scripts

User Scripts (JavaScript injected into the `WKWebView`) are compiled, concatenated and minified using [webpack](https://webpack.js.org/). User Scripts to be aggregated are placed in the following directories:

```
/Client
|-- /Frontend
    |-- /UserContent
        |-- /UserScripts
            |-- /AllFrames
            |   |-- /AtDocumentEnd
            |   |-- /AtDocumentStart
            |-- /MainFrame
                |-- /AtDocumentEnd
                |-- /AtDocumentStart
```

This reduces the total possible number of User Scripts down to four. The compiled output from concatenating and minifying the User Scripts placed in these folders resides in `/Client/Assets` and are named accordingly:

- `AllFramesAtDocumentEnd.js`
- `AllFramesAtDocumentStart.js`
- `MainFrameAtDocumentEnd.js`
- `MainFrameAtDocumentStart.js`

To simplify the build process, these compiled files are checked in to this repository. When adding or editing User Scripts, these files can be recompiled with `webpack` manually. This requires Node.js to be installed and all required `npm` packages can be installed by running `npm install` in the root directory of the project. User Scripts can be compiled by running the following command in the root directory of the project:

```
npm run build
```

## Periphery

Periphery scans the project (currently just the `Client` code) for unused variables, constants, functions, structs, and classes.
To use Periphery, first install it using [Homebrew](https://brew.sh):

```sh
brew tap peripheryapp/periphery && brew install periphery
```

Then switch to the Periphery target in Xcode and build (⌘B). You will get a large number of warnings as a result. Note that many of the warnings are either false positives or are due to parameters passed in iOS's standard delegate pattern.

## History of the codebase

The Neeva browser stands on the shoulders of the excellent [Firefox for iOS](https://github.com/mozilla-mobile/firefox-ios) browser.
Neeva forked Firefox for iOS on Feb 18, 2021 at `c23bd56293da4e2913e1d512ee559e784dd21e48`, and the project later diverged substantially enough that upstream Firefox changes were not continuously merged.

Thank you to Mozilla for providing such a fantastic foundation for this project and many others.
