//
//  LNPopupExternalTransitionSource.h
//  LNPopupController — NeoDizzy system-accessory integration
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Views owned by the app inside a system tab accessory. LN mirrors these views
/// during its existing transition; it never changes their layout or the tab bar.
NS_SWIFT_UI_ACTOR
@interface LNPopupExternalTransitionSource : NSObject

/// The actual rendered miniature content, not a transparent geometry marker.
@property (nonatomic, weak, nullable) UIView* contentView;
/// The actual accessory content container, used only for transition geometry.
/// LN never mirrors this view, changes its layout, or hides the system shell.
/// Nil falls back to contentView for geometry.
@property (nonatomic, weak, nullable) UIView* containerView;
/// The actual rendered artwork inside contentView.
@property (nonatomic, weak, nullable) UIView* artworkView;
/// A value of zero uses half the transition container height.
@property (nonatomic) CGFloat cornerRadius;
/// Defaults to 6 points.
@property (nonatomic) CGFloat artworkCornerRadius;
/// Nil retains the popup bar's configured material for the transition surface.
@property (nonatomic, copy, nullable) UIVisualEffect* backgroundEffect;
/// The app owns gesture regions; LN retains drag progress and settling behavior.
@property (nonatomic, copy, nullable) BOOL (^interactionShouldBegin)(UIPanGestureRecognizer* gesture);

@end

NS_ASSUME_NONNULL_END
