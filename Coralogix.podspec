Pod::Spec.new do |spec|

  spec.name         = "Coralogix"
  spec.version      = "1.2.3"
  spec.summary      = "Coralogix OpenTelemetry pod for iOS."

  spec.description  = <<-DESC
  The Coralogix RUM agent for iOS provides a Swift package that captures:
  - HTTP requests, using URLSession instrumentation
  - Unhandled exceptions (NSException, NSError, Error)
  - Custom Log ()
  - Crashes - using PLCrashReporter
  - Page navigation (Swift use swizzeling / SwiftUI use modifier)
  DESC

  spec.swift_version    = '5.9'
  spec.cocoapods_version = '>= 1.10'

  spec.platform     = :ios, '13.0'  # Update the deployment target here

  spec.homepage     = "https://github.com/coralogix/cx-ios-sdk.git"
  spec.license      = { :type => 'MIT', :file => 'LICENSE' }
  spec.source       = { :git => "https://github.com/coralogix/cx-ios-sdk.git", :tag => "#{spec.version}" }
  spec.author             = { "Coralogix" => "www.coralogix.com" }
  spec.ios.deployment_target = "13.0"

  spec.source_files  = 'Coralogix/Sources/**/*.swift'
  spec.exclude_files = 'Coralogix/Sources/Exclude'

  spec.static_framework = true
  spec.dependency 'PLCrashReporter', '~> 1.12'
  spec.dependency 'CoralogixInternal', '1.2.3'

  spec.test_spec 'Tests' do |test|
    test.source_files = 'Tests/CoralogixRumTests/**/*.swift'
  end
end

