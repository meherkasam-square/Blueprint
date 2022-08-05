import CoreGraphics
import os.log

/// A size cache that also holds subcaches.
protocol CacheTree: AnyObject {

    typealias SubcacheKey = Int

    /// The name of this cache
    var name: String { get }

    /// A reference to use for logging
    var signpostRef: AnyObject { get }

    /// The scale of the screen scale, used for rounding to account for loss of float precision.
    var screenScale: CGFloat { get }

    /// The sizes that are contained in this cache, keyed by size constraint.
    subscript(constraint: SizeConstraint) -> CGSize? { get set }

    /// Gets a subcache identified by the given key, or creates a new one.
    func subcache(key: SubcacheKey, name: @autoclosure () -> String) -> CacheTree
}

extension CacheTree {
    /// Convenience method to get a cached size, or compute and store one if it is not in the cache.
    func get(_ constraint: SizeConstraint, orStore calculation: (SizeConstraint) -> CGSize) -> CGSize {

        /// Due to various math upstream, we can end up with measurements like 210.0 getting
        /// turned into numbers like 209.99999997 due to loss of precision.
        ///
        /// Because we cache by exact values in this cache,
        /// let's round the key to the nearest screen-scale pixel to avoid a cache miss.
        ///
        /// ⚠️ Important! We **do not** want to round the constraint itself, just the key.
        /// Blueprint allows (and expects) unrounded values – they're rounded / snapped during the view layout pass.

        let key = constraint.roundToNearestPixel(with: screenScale)

        if let size = self[key] {
            return size
        } else {
            let size = calculation(constraint)

            /// 1) Cache the measured size for the given constraint.
            self[key] = size

            /// 2) Optimization: Cache the size itself as its own constraint.
            ///
            /// This avoids a cache miss later on when a layout
            /// lays out an item with this same size.
            self[SizeConstraint(size)] = size

            return size
        }
    }

    /// Gets a subcache for an element with siblings.
    func subcache(index: Int, of childCount: Int, element: Element) -> CacheTree {
        subcache(
            key: index,
            name: childCount == 1
                ? "\(name).\(type(of: element))"
                : "\(name)[\(index)].\(type(of: element))"
        )
    }

    /// Gets a subcache for an element with no siblings.
    func subcache(element: Element) -> CacheTree {
        subcache(index: 0, of: 1, element: element)
    }
}
