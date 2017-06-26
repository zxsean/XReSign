//
//  ViewController.swift
//  XReSign
//
//  Copyright © 2017 xndrs. All rights reserved.
//

import Cocoa


class ViewController: NSViewController {
    @IBOutlet weak var textFieldIpaPath: NSTextField!
    @IBOutlet weak var textFieldProvisioningPath: NSTextField!
    @IBOutlet weak var textFieldBundleId: NSTextField!
    @IBOutlet weak var comboBoxCertificates: NSComboBox!
    @IBOutlet weak var buttonChangeBundleId: NSButton!
    @IBOutlet weak var buttonResign: NSButton!
    @IBOutlet weak var progressIndicator: NSProgressIndicator!
    
    fileprivate var certificates:[String] = []
    fileprivate var tempDir: String?
    

    // MARK: - Main

    override func viewDidLoad() {
        super.viewDidLoad()
        self.loadCertificates()
    }

    override var representedObject: Any? {
        didSet {
        // Update the view, if already loaded.
        }
    }


    // MARK: - Certificates

    private func loadCertificates() {
        DispatchQueue.global().async {

            let task:Process = Process()
            let pipe:Pipe = Pipe()
            
            task.launchPath = "/usr/bin/security"
            task.arguments = ["find-identity", "-v", "-p", "codesigning"]
            task.standardOutput = pipe
            task.standardError = pipe
            
            let handle = pipe.fileHandleForReading
            task.launch()

            let data = handle.readDataToEndOfFile()
            self.parseCertificatesFrom(data: data)
        }
    }
    
    private func parseCertificatesFrom(data: Data) {
        let buffer = String(data: data, encoding: String.Encoding.utf8)!
        var names:[String] = []

        buffer.enumerateLines { (line, _) in
            // default output line format for security command:
            // 1) E00D4E3D3272ABB655CDE0C1CF53891210BAF4B8 "iPhone Developer: XXXXXXXXXX (YYYYYYYYYY)"
            let components = line.components(separatedBy: "\"")
            if components.count > 2 {
                let commonName = components[components.count - 2]
                names.append(commonName)
            }
        }
        
        names.sort(by: { $0 < $1 })
        DispatchQueue.main.sync {
            self.certificates.removeAll()
            self.certificates.append(contentsOf: names)
            self.comboBoxCertificates.reloadData()
        }
    }
    
    private func organizationUnitFromCertificate(by name: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassCertificate,
                                    kSecAttrLabel as String: name,
                                    kSecReturnRef as String: kCFBooleanTrue]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else {
            return nil
        }
        let certificate = item as! SecCertificate
        
        let keys = [kSecOIDX509V1SubjectName] as CFArray
        guard let subjectValue = SecCertificateCopyValues(certificate, keys, nil) else {
            return nil
        }

        if let subjectDict = subjectValue as? [String : Any] {
            let rootDict = subjectDict["\(kSecOIDX509V1SubjectName)"] as? [String : Any]
            if let values = rootDict?["value"] as? [Any] {
                for value in values {
                    if let dict = value as? [String : Any] {
        
                        if let label = dict["label"] as? String, let value = dict["value"] as? String {
                            if label.compare("\(kSecOIDOrganizationalUnitName)") == .orderedSame {
                                return value
                            }
                        }
                    }
                }
            }
        }
        return nil
    }
    
    private func teamIdentifierFromProvisioning(path provisioningPath: String) -> String? {
        guard let launchPath = Bundle.main.path(forResource: "entitlements", ofType: "sh") else {
            showAlertWith(title: nil, message: "Can not find entitlements script to run", style: .critical)
            return nil
        }
        
        guard let _  = tempDir else {
            showAlertWith(title: nil, message: "Internal error. No temporary directory for script.", style: .critical)
            return nil
        }

        let task:Process = Process()
        let pipe:Pipe = Pipe()

        task.launchPath = "/bin/sh"
        task.arguments = [launchPath, provisioningPath, tempDir!]
        task.standardOutput = pipe
        task.standardError = pipe

        let handle = pipe.fileHandleForReading
        task.launch()

        let data = handle.readDataToEndOfFile()
        let buffer = String(data: data, encoding: String.Encoding.utf8)!

        if let _ = buffer.range(of: "SUCCESS") {
            let path = "\(tempDir!)/entitlements.plist"
            if FileManager.default.fileExists(atPath: path) {
                if let plist = NSDictionary(contentsOfFile: path) {
                    if let teamIdentifier = plist["com.apple.developer.team-identifier"] as? String {
                        return teamIdentifier
                    }
                }
            }
        }
        return nil
    }

    private func signIpaWith(path ipaPath: String, developer: String, provisioning: String, bundle: String?) {
        guard let launchPath = Bundle.main.path(forResource: "xresign", ofType: "sh") else {
            showAlertWith(title: nil, message: "Can not find resign script to run", style: .critical)
            return
        }

        buttonResign.isEnabled = false
        progressIndicator.isHidden = false
        progressIndicator.startAnimation(nil)
        
        DispatchQueue.global().async {
            let task:Process = Process()
            let pipe:Pipe = Pipe()
            
            task.launchPath = "/bin/sh"
            task.arguments = [launchPath, "-s", ipaPath, "-c", developer, "-p", provisioning, "-b", bundle ?? ""]
            task.standardOutput = pipe
            task.standardError = pipe
            
            let handle = pipe.fileHandleForReading
            task.launch()
            
            let data = handle.readDataToEndOfFile()
            let buffer = String(data: data, encoding: String.Encoding.utf8)!
            print ("\(buffer)")
            
            var success = false
            if let _ = buffer.range(of: "XReSign FINISHED") {
                success = true
            }
            
            DispatchQueue.main.async {
                self.buttonResign.isEnabled = true
                self.progressIndicator.stopAnimation(nil)
                self.progressIndicator.isHidden = true
                
                if success {
                    self.showAlertWith(title: nil, message: "Re-sign finished", style: .informational)
                }
                else {
                    self.showAlertWith(title: nil, message: "Failed to re-sign the app", style: .critical)
                }
            }
        }
    }


    // MARK: - Actions

    @IBAction func actionBrowseIpa(_ sender: Any) {
        let openPanel = NSOpenPanel()
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.canCreateDirectories = false
        openPanel.canChooseFiles = true
        openPanel.allowedFileTypes = ["ipa", "IPA"]
        openPanel.begin { (result) -> Void in
            if result == NSFileHandlingPanelOKButton {
                self.textFieldIpaPath.stringValue = openPanel.url?.path ?? ""
            }
        }
    }
    
    @IBAction func actionBrowseProvisioning(_ sender: Any) {
        let openPanel = NSOpenPanel()
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.canCreateDirectories = false
        openPanel.canChooseFiles = true
        openPanel.allowedFileTypes = ["mobileprovision"]
        openPanel.begin { (result) -> Void in
            if result == NSFileHandlingPanelOKButton {
                self.textFieldProvisioningPath.stringValue = openPanel.url?.path ?? ""
            }
        }
    }
    
    @IBAction func actionChangeBundleId(_ sender: Any) {
        textFieldBundleId.isEnabled = buttonChangeBundleId.state == NSOnState
    }
    
    @IBAction func actionSign(_ sender: Any) {
        let ipaPath = textFieldIpaPath.stringValue
        let provisioningPath = textFieldProvisioningPath.stringValue
        let bundleId:String? = buttonChangeBundleId.state == NSOnState ? textFieldBundleId.stringValue : nil
        let index = comboBoxCertificates.indexOfSelectedItem
        let certificateName:String? = index >= 0 ? certificates[index] : nil
        
        if ipaPath.isEmpty {
            showAlertWith(title: nil, message: "IPA file not selected", style: .critical)
            return
        }
        
        guard let commonName = certificateName else {
            showAlertWith(title: nil, message: "Signing certificate not selected", style: .critical)
            return
        }
        
        tempDir = URL(fileURLWithPath: ipaPath).deletingLastPathComponent().path

        
        // if there is a path to provisioning profile, check right pair with signing certificate
        if !provisioningPath.isEmpty {
            guard let organizationUnit = organizationUnitFromCertificate(by: commonName) else {
                showAlertWith(title: nil,
                              message: "Can not retrieve organization unit value for certificate \(commonName)",
                              style: .critical)
                return
            }
            
            guard let teamIdentifier = teamIdentifierFromProvisioning(path: provisioningPath) else {
                showAlertWith(title: nil,
                              message: "Can not retrieve team identifier from provisioning profile",
                    style: .critical)
                return
            }

            if organizationUnit.compare(teamIdentifier) != .orderedSame {
                showAlertWith(title: nil,
                              message: "There is a problem!\n" +
                                        "Different team identifiers\n" +
                                        "Provisioing team identifier: \(teamIdentifier)\n" +
                                        "Certificate team identifier: \(organizationUnit)\n" +
                                        "Check it and select the right pair.",
                              style: .critical)
                return
            }
        }
        
        signIpaWith(path: ipaPath, developer: commonName, provisioning: provisioningPath, bundle: bundleId)
    }
    
    
    // MARK: - Alert
    
    private func showAlertWith(title: String?, message: String, style: NSAlertStyle) {
        let alert = NSAlert()
        alert.messageText = title ?? "XReSign"
        alert.informativeText = message
        alert.alertStyle = style
        alert.addButton(withTitle: "Close")
        alert.beginSheetModal(for: NSApp.keyWindow!, completionHandler: nil)
    }
}


// MARK: - NSComboBoxDelegate

extension ViewController: NSComboBoxDelegate {
}


// MARK: - NSComboBoxDataSource

extension ViewController: NSComboBoxDataSource {
    
    func numberOfItems(in comboBox: NSComboBox) -> Int {
        return certificates.count
    }
    
    func comboBox(_ comboBox: NSComboBox, objectValueForItemAt index: Int) -> Any? {
        return certificates[index]
    }
}
