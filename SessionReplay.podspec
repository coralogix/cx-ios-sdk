Pod::Spec.new do |spec|

  spec.name         = "SessionReplay"
  spec.version      = "1.2.6"
  spec.summary      = "Coralogix Session-Replay pod for iOS."

  spec.description  = <<-DESC
  - The `SessionReplay` module provides functionality for recording user sessions,
    including capturing images or videos at specified intervals.
  - It also supports masking sensitive data like text, images, and faces during the recording process.
  DESC

  spec.swift_version    = '5.9'
  spec.cocoapods_version = '>= 1.10'

  spec.platform     = :ios, '13.0'  # Update the deployment target here

  spec.homepage     = "https://github.com/coralogix/cx-ios-sdk.git"
  spec.license      = { :type => 'MIT', :file => 'LICENSE' }
  spec.source       = { :git => "https://github.com/coralogix/cx-ios-sdk.git", :tag => "#{spec.version}" }
  spec.author             = { "Coralogix" => "www.coralogix.com" }
  spec.ios.deployment_target = "13.0"
  spec.static_framework = true

  spec.source_files  = 'SessionReplay/Sources/**/*.swift'
  spec.dependency 'CoralogixInternal', '1.2.6'
  
    spec.test_spec 'Tests' do |test|
        test.source_files = 'Tests/SessionReplayTests/**/*.swift'
        test.resources = 'Tests/SessionReplayTests/Resources/**/*'
    end
  end

