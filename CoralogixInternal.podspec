 #
#  Be sure to run `pod spec lint Coralogix.podspec' to ensure this is a
#  valid spec and to remove all comments including this before submitting the spec.
#
#  To learn more about Podspec attributes see https://guides.cocoapods.org/syntax/podspec.html
#  To see working Podspecs in the CocoaPods repo see https://github.com/CocoaPods/Specs/
#

Pod::Spec.new do |spec|

  spec.name         = "CoralogixInternal"
  spec.version      = "1.0.20"
  spec.summary      = "Coralogix Internal Package. This module is not for public use."

  spec.description  = <<-DESC
  Coralogix internal files
  DESC

  spec.swift_version    = '5.9'
  spec.cocoapods_version = '>= 1.10'

  spec.platform     = :ios, '13.0'  # Update the deployment target here

  spec.homepage     = "https://github.com/coralogix/cx-ios-sdk.git"
  spec.license      = { :type => 'MIT', :file => 'LICENSE' }
  spec.source       = { :git => "https://github.com/coralogix/cx-ios-sdk.git", :tag => "#{spec.version}" }
  spec.author             = { "Coralogix" => "www.coralogix.com" }
  spec.ios.deployment_target = "13.0"

  spec.source_files  = 'coralogixinternal/Sources/**/*.swift}'
  spec.exclude_files = 'coralogixinternal/Sources/Exclude'
end


