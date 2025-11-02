Pod::Spec.new do |spec|

  spec.name         = "CoralogixInternal"
  spec.version      = "1.3.2"
  spec.summary      = "Coralogix Internal Package. This module is not for public use."

  spec.description  = <<-DESC
   - Coralogix internal files
   - Coralogix Internal Package. This module is not for public use.
  DESC

  spec.swift_version    = '5.9'
  spec.cocoapods_version = '>= 1.10'

  spec.platform     = :ios, '13.0'  # Update the deployment target here

  spec.homepage     = "https://github.com/coralogix/cx-ios-sdk.git"
  spec.license      = { :type => 'MIT', :file => 'LICENSE' }
  spec.source       = { :git => "https://github.com/coralogix/cx-ios-sdk.git", :tag => "#{spec.version}" }
  spec.author             = { "Coralogix" => "www.coralogix.com" }
  spec.ios.deployment_target = "13.0"

  spec.source_files  = 'CoralogixInternal/Sources/**/*.swift'
  spec.static_framework = true
end


