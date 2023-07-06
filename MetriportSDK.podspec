Pod::Spec.new do |s|
  s.name             = 'MetriportSDK'
  s.version          = '1.0.16'
  s.summary          = 'A Swift Library for Metriport API and Apple Health integrations.'

  s.homepage         = 'https://github.com/metriport/metriport-ios-sdk'
  s.license          = { :type => 'MIT', :file => 'LICENSE.md' }
  s.author           = { 'Metriport' => 'contact@metriport.com' }
  s.source           = { :git => 'https://github.com/metriport/metriport-ios-sdk.git', :tag => s.version.to_s }

  s.ios.deployment_target = '13.0'
  s.swift_version = '5.0'

  s.source_files = 'Sources/MetriportSDK/**/*'
end
