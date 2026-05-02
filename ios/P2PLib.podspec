Pod::Spec.new do |s|
  s.name             = 'P2PLib'
  s.version          = '0.1.0'
  s.summary          = 'libp2p native library for iOS'
  s.homepage         = 'https://github.com/blueman/p2p-node'
  s.license          = { :type => 'MIT' }
  s.author           = { 'blueman' => 'blueman@example.com' }
  s.source           = { :http => 'file:' + __dir__ }
  
  s.platform = :ios, '13.0'
  
  # Link the static library and header
  s.vendored_libraries = 'Frameworks/libp2p_ios.a'
  s.source_files = 'Frameworks/libp2p_ios.h'
  s.public_header_files = 'Frameworks/libp2p_ios.h'
  
  s.static_framework = true
  s.pod_target_xcconfig = {
    'OTHER_LDFLAGS' => '-force_load $(PODS_ROOT)/../Frameworks/libp2p_ios.a'
  }
end
