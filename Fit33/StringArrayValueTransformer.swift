import Foundation

@objc(StringArrayValueTransformer)
class StringArrayValueTransformer: NSSecureUnarchiveFromDataTransformer {
    
    // The name of the transformer - must match Core Data model
    static let name = NSValueTransformerName(rawValue: "StringArrayValueTransformer")
    
    // Register the transformer when the app launches
    override class func transformedValueClass() -> AnyClass {
        return NSArray.self
    }
    
    override class func allowsReverseTransformation() -> Bool {
        return true
    }
    
    // Specify which classes are allowed to be decoded (security requirement)
    override class var allowedTopLevelClasses: [AnyClass] {
        return [NSArray.self, NSString.self]
    }
    
    // Register the transformer
    static func register() {
        let transformer = StringArrayValueTransformer()
        ValueTransformer.setValueTransformer(transformer, forName: name)
    }
}

