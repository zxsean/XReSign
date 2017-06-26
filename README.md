# XReSign 
XReSign - developer tool to sign or resign iDevice app (.ipa) files with a digital certificate from Apple for development or distribution.

## How to use
XReSign allows you to sign or resign unencrypted ipa-files with certificate for which you hold the corresponding private key. 

### GUI application

### Shell command
In addition to GUI application, you can find, inside Scripts folder, xresign.sh script to run resign task from the command line.

### Usage:
```
$ ./xresign.sh -s path -c certificate [-p path] [-b identifier]
```
## Acknowledgments
Inspired by such great tool as iReSign and other command line scripts to resign the ipa files. Unfortunately a lot of them not supported today. So this is an attempt to support resign the latest app bundle components both through the GUI application and through the command line script.
