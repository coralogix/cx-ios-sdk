#
#  Be sure to run `pod spec lint Coralogix.podspec' to ensure this is a
#  valid spec and to remove all comments including this before submitting the spec.
#
#  To learn more about Podspec attributes see https://guides.cocoapods.org/syntax/podspec.html
#  To see working Podspecs in the CocoaPods repo see https://github.com/CocoaPods/Specs/
#

Pod::Spec.new do |spec|

  spec.name         = "Coralogix"
  spec.version      = "1.0.6"
  spec.summary      = "Coralogix OpenTelemetry pod for iOS."

  spec.description  = <<-DESC
  The Coralogix RUM agent for iOS provides a Swift package that captures:
  HTTP requests, using URLSession instrumentation
  Unhandled exceptions (NSException, NSError, Error)
  Custom Log ()
  Crashes - using PLCrashReporter
  Page navigation (Swift use swizzeling / SwiftUI use modifier)
  DESC

  spec.homepage     = "https://github.com/coralogix/cx-ios-sdk.git"
  spec.license      = { :type => 'MIT', :file => 'LICENSE' }
  spec.source       = { :git => "https://github.com/coralogix/cx-ios-sdk.git", :tag => "#{spec.version}" }
  spec.author             = { "Coralogix" => "www.coralogix.com" }
  spec.ios.deployment_target = "15.0"
  spec.source_files  = 'Sources/**/*.{swift,h}'
  spec.exclude_files = 'Sources/Exclude'
  spec.resources    = 'Sources/**/*.{xib,storyboard,xcassets,json,png,jpeg}'

end
