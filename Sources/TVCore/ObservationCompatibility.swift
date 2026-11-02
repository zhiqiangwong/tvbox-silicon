@_exported import Perception
import SwiftUI

#if os(iOS)
public typealias AppBindable<Value: AnyObject & Perceptible> = Perception.Bindable<Value>
#else
public typealias AppBindable<Value: AnyObject & Observable> = SwiftUI.Bindable<Value>
#endif
