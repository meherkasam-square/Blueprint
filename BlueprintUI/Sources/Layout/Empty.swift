//
//  Empty.swift
//  BlueprintUI
//
//  Created by Kyle Van Essen on 6/4/20.
//

import UIKit


///
/// An empty `Element` which has no size and draws no content.
///
public struct Empty : Element {
    
    public init() {}
    
    public var content: ElementContent {
        ElementContent { _ in
            .zero
        }
    }
    
    public func backingViewDescription(bounds: CGRect, subtreeExtent: CGRect?) -> ViewDescription? {
        nil
    }
}
