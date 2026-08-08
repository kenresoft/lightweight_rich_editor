#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint lightweight_rich_editor.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'lightweight_rich_editor'
  s.version          = '0.1.1'
  s.summary          = 'A lightweight rich-text editor plugin.'
  s.description      = <<-DESC
A lightweight rich-text editor plugin for Flutter.
                       DESC
  s.homepage         = 'https://github.com/kenresoft/lightweight_rich_editor'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Kenresoft' => 'support@kenresoft.com' }
  s.source           = { :path => '.' }
  s.source_files = '../darwin/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '12.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
