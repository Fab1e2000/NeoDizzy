//
//  _LNPopupTransitionAnimatorOpen.mm
//  LNPopupController
//
//  Created by Léo Natan on 2025-03-24.
//  Copyright © 2015-2025 Léo Natan. All rights reserved.
//

#import "_LNPopupTransitionAnimator.h"
#import "LNPopupBar+Private.h"
#import <LNPopupController/UIViewController+LNPopupSupport.h>
#import <objc/runtime.h>
#import "LNPopupContentView+Private.h"
#import "LNPopupControllerImpl.h"
#import <LNPopupController/LNPopupExternalTransitionSource.h>

static const void* _LNPopupOpenCloseTransitionViewKey = &_LNPopupOpenCloseTransitionViewKey;

@interface _LNPopupTransitionAnimator ()
- (void)_captureExternalGeometry;
- (CGRect)_externalMiniatureFrameForWrapperBounds:(CGRect)bounds;
- (void)_positionExternalContent;
@end

@implementation _LNPopupTransitionAnimator
{
	CGFloat _alphaBefore;
	LNPopupExternalTransitionSource* _externalSource;
	UIView* _externalContentView;
	UIView* _externalContainerView;
	UIView* _externalArtworkView;
	CGFloat _externalArtworkCornerRadiusBeforeAnimation;
	BOOL _hasCapturedExternalGeometry;
	CGRect _externalContainerFrame;
	CGRect _externalMiniatureContentFrame;
	CGRect _externalArtworkFrameInWindow;
	CGFloat _externalContainerCornerRadius;
	CGFloat _externalArtworkCornerRadius;
}

- (instancetype)initWithTransitionView:(_LNPopupTransitionView *)transitionView userView:(UIView *)view popupBar:(LNPopupBar *)popupBar popupContentView:(LNPopupContentView *)popupContentView effectiveInteractionStyle:(LNPopupInteractionStyle)interactionStyle allowContentTransition:(BOOL)allowContentTransition
{
	self = [super init];
	
	if(self)
	{
		_externalSource = popupBar.externalTransitionSource;
		_externalContentView = _externalSource.contentView;
		_externalContainerView = _externalSource.containerView ?: _externalContentView;
		_externalArtworkView = _externalSource.artworkView;
		BOOL hasExternalArtwork = _externalArtworkView.window != nil &&
			_externalArtworkView.bounds.size.width > 0 && _externalArtworkView.bounds.size.height > 0;
		if((_externalSource != nil && !hasExternalArtwork) ||
		   (_externalSource == nil && (popupBar.customBarViewController != nil || popupBar.imageView.isHidden)))
		{
			transitionView = nil;
			view = nil;
		}
		
		_transitionView = transitionView;
		_view = view;
		_popupBar = popupBar;
		_popupContentView = popupContentView;
		
		if(@available(iOS 26.0, *))
		{
			BOOL hasContentSource = _externalSource == nil || (_externalContentView.window != nil &&
				_externalContentView.bounds.size.width > 0 && _externalContentView.bounds.size.height > 0);
			_wantsContentTransition = allowContentTransition && hasContentSource && LNPopupEnvironmentHasGlass() && popupContentView.allowsContentTransition;
			
			if(_wantsContentTransition)
			{
				_contentViewTransitionView = [_LNPopupTransitionView transitionViewWithSourceView:popupContentView.contentView];
				_contentViewTransitionView.matchesAlpha = NO;
				_contentViewTransitionView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleBottomMargin;
				if(_externalSource != nil)
				{
					// Clip a fixed viewport; never resize the live full-screen portal
					// to the accessory width while its source remains full-screen.
					_contentViewTransitionView.autoresizingMask = UIViewAutoresizingNone;
				}
				
				_contentTransitionEffectView = [UIVisualEffectView new];
				_contentTransitionEffectView.frame = popupContentView.frame;
				[_contentTransitionEffectView.contentView addSubview:_contentViewTransitionView];
				_contentViewTransitionView.frame = self.popupContentView.currentPopupContentViewController.view.bounds;
				_contentTransitionEffectView.clipsToBounds = YES;
				_contentTransitionEffectView.layer.cornerCurve = kCACornerCurveCircular;
				
				// The system miniature keeps its labels and controls in place.
				// Only its artwork participates in the shared-element flight;
				// do not carry a second copy of the text along the closing card.
				if(_externalSource == nil)
				{
					_popupBarTransitionView = [_LNPopupTransitionView transitionViewWithSourceView:self.barContentView];
				}
				_popupBarTransitionView.matchesAlpha = NO;
				_popupBarTransitionView.allowsEffects = YES;
				_popupBarTransitionView.matchesPosition = NO;
				_popupBarTransitionView.frame = _externalSource != nil
					? (CGRect){CGPointZero, self.barContentView.bounds.size} : popupBar.contentView.frame;
				_popupBarTransitionView.autoresizingMask = _externalSource != nil ? UIViewAutoresizingNone : UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleBottomMargin;
				
				_contentTransitionWrapperView = [[UIView alloc] initWithFrame:popupContentView.frame];
				_contentTransitionEffectView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
				[_contentTransitionWrapperView addSubview:_contentTransitionEffectView];
				_contentTransitionEffectView.frame = _contentTransitionWrapperView.bounds;
				if(_externalSource != nil)
				{
					_accessoryTransitionEffectView = [UIVisualEffectView new];
					_accessoryTransitionEffectView.frame = _contentTransitionWrapperView.bounds;
					_accessoryTransitionEffectView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
					_accessoryTransitionEffectView.clipsToBounds = YES;
					_accessoryTransitionEffectView.layer.cornerCurve = kCACornerCurveCircular;
					[_contentTransitionWrapperView insertSubview:_accessoryTransitionEffectView belowSubview:_contentTransitionEffectView];
					_contentTransitionEffectView.overrideUserInterfaceStyle = popupContentView.traitCollection.userInterfaceStyle;
					_accessoryTransitionEffectView.overrideUserInterfaceStyle = self.barContentView.traitCollection.userInterfaceStyle;
					_contentTransitionEffectView.accessibilityIdentifier = @"player.transition.fullscreen";
					_accessoryTransitionEffectView.accessibilityIdentifier = @"player.transition.accessory";
					_contentViewTransitionView.accessibilityIdentifier = @"player.transition.content";
				}
				if(_popupBarTransitionView != nil)
				{
					[_contentTransitionWrapperView addSubview:_popupBarTransitionView];
				}
				
				self.popupContentView.transitionView = _contentTransitionWrapperView;
			}
		}
	}
	
	return self;
}

- (void)animateWithAnimator:(UIViewPropertyAnimator *)animator otherAnimations:(void (^)(void))otherAnimations
{
	//LNPopupUI support
	static SEL transitionWillBegin = NSSelectorFromString(@"_transitionWillBeginToState:");
	static SEL transitionDidEnd = NSSelectorFromString(@"_transitionDidEnd");
	
	[UIView performWithoutAnimation:^{
		[self.popupContentView layoutIfNeeded];
		[self _captureExternalGeometry];
		if(self.transitionView == nil && self.view != nil)
		{
			_transitionView = [[_LNPopupTransitionView alloc] initWithSourceView:self.view];
		}
		if(_externalSource != nil)
		{
			// These surfaces only render the transition. Let the real content's
			// pan recognizer receive touches while opening or settling back.
			_transitionView.userInteractionEnabled = NO;
			_contentTransitionWrapperView.userInteractionEnabled = NO;
		}
		
		if(_wantsContentTransition)
		{
			_transitionView.matchesAlpha = NO;
			_transitionView.alpha = self.view.alpha;
			_alphaBefore = self.view.alpha;
			self.view.alpha = 0.0;
			
			_popupBarEffect = _externalSource.backgroundEffect ?: self.popupBar.contentView.effect;
			if(_externalSource != nil)
			{
				// The system owns the real accessory's glass. Only the independent
				// LN transition surface receives an effect; never alter that shell.
			}
			else if(@available(iOS 26.0, *))
			{
				//We don't really want another glass here, but to have vibrancy in the labels and buttons, we need a visual effect view with a "clear" effect that still provides a vibrancy environment. So we strip a glass effect from all of its elements.
				self.popupBar.contentView.effectOverride = _LNPopupGlassWrapperEffect.vibrancyOnlyEffect;
			} else {
				abort();
			}
		}
		
		_popupBarImageAlphaBeforeAnimation = self.barArtworkView.alpha;
		
		if(_transitionView != nil)
		{
			self.barArtworkView.alpha = 0.0;

			if(_externalSource != nil)
			{
				// Keep the original live-view handoff for the accessory as well as
				// the full player. This is not an image snapshot approximation.
				_LNPopupTransitionView* artworkPortal = [_LNPopupTransitionView transitionViewWithSourceView:self.barArtworkView];
				artworkPortal.matchesAlpha = NO;
				artworkPortal.matchesPosition = NO;
				artworkPortal.matchesTransform = NO;
				artworkPortal.scalesSourceToBounds = YES;
				// The portal's animated clipping owns the corner treatment. Keeping
				// the miniature's original mask would scale that radius twice.
				_externalArtworkCornerRadiusBeforeAnimation = self.barArtworkView.layer.cornerRadius;
				self.barArtworkView.layer.cornerRadius = 0.0;
				_crossfadeView = artworkPortal;
			}
			else
			{
				UIImage* image;
				if(self.popupBar.swiftuiImageController != nil)
				{
					id contents = self.popupBar.swiftuiImageController.view.subviews.firstObject.layer.contents;
					if(contents != nil && CFGetTypeID((__bridge CFTypeRef)contents) == CGImageGetTypeID())
					{
						image = [[UIImage alloc] initWithCGImage:(__bridge CGImageRef)contents];
					}
					else
					{
						image = [[[UIGraphicsImageRenderer alloc] initWithSize:self.popupBar.imageView.bounds.size] imageWithActions:^(UIGraphicsImageRendererContext * _Nonnull rendererContext) {
							[self.popupBar.imageView drawViewHierarchyInRect:self.popupBar.imageView.bounds afterScreenUpdates:NO];
						}];
					}
				}
				else
				{
					image = self.popupBar.imageView.image;
				}
				_crossfadeView = [[LNPopupImageView alloc] initWithImage:image];
				_crossfadeView.contentMode = self.popupBar.imageView.contentMode;
			}
			_crossfadeView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
			_crossfadeView.frame = _transitionView.bounds;
			[_transitionView addSubview:_crossfadeView];
			
			_transitionView.frame = self.sourceFrame;
			_transitionView.alpha = self.sourceImageAlpha;
		}
		
		if(_wantsContentTransition)
		{
			self.popupContentView.effectView.alpha = 0.0;
			// The external path configures its two independent materials below.
			// Do not create an accessory glass here only to replace it immediately.
			if(_externalSource == nil)
			{
				_contentTransitionEffectView.effect = self.sourceContentTransitionEffect;
			}
			_contentTransitionWrapperView.frame = self.sourceContentFrame;
			if(_externalSource != nil)
			{
				_popupBarTransitionView.frame = [self _externalMiniatureFrameForWrapperBounds:_contentTransitionWrapperView.bounds];
				[self _positionExternalContent];
			}
			_contentTransitionEffectView.corners = self.sourceContentCornerRadius;
			_contentViewTransitionView.alpha = self.sourceContentAlpha;
			if(_externalSource != nil)
			{
				BOOL opening = self.targetState == LNPopupPresentationStateOpen;
				_contentTransitionEffectView.effect = opening ? nil : self.popupContentView._currentEffect;
				_accessoryTransitionEffectView.effect = opening ? _popupBarEffect : nil;
				_accessoryTransitionEffectView.corners = self.sourceContentCornerRadius;
			}
			else { _contentTransitionEffectView.effect = self.targetContentTransitionEffect; }
		}
		
		[self beforeAnyAnimation];
		
		if(_transitionView != nil)
		{
			objc_setAssociatedObject(self.transitionView.sourceLayer, _LNPopupOpenCloseTransitionViewKey, _transitionView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		}
		
		if(_wantsContentTransition)
		{
			[self.popupContentView.superview addSubview:_contentTransitionWrapperView];
		}
		if(_transitionView != nil)
		{
			[self.popupContentView.window addSubview:_transitionView];
		}
		[self performBeforeAdditionalAnimations];
	}];
	
	[animator addAnimations:otherAnimations];
	
	[animator addAnimations:^{
		if(_wantsContentTransition)
		{
			_contentTransitionWrapperView.frame = self.targetContentFrame;
			if(_externalSource != nil)
			{
				_popupBarTransitionView.frame = [self _externalMiniatureFrameForWrapperBounds:_contentTransitionWrapperView.bounds];
				[self _positionExternalContent];
				_accessoryTransitionEffectView.corners = self.targetContentCornerRadius;
			}
			_contentTransitionEffectView.corners = self.targetContentCornerRadius;
		}
		
		_transitionView.alpha = self.targetImageAlpha;
		
		[self performAdditionalAnimations];
		
		if([self.view respondsToSelector:transitionWillBegin])
		{
			//LNPopupUI support
			NSInvocation* invocation = [NSInvocation invocationWithMethodSignature:[self.view methodSignatureForSelector:transitionWillBegin]];
			invocation.target = self.view;
			LNPopupPresentationState targetState = self.targetState;
			invocation.selector = transitionWillBegin;
			[invocation setArgument:&targetState atIndex:2];
			[invocation invoke];
		}
	}];
	
	[animator addAnimations:^{
		[self performAdditionalDelayed015Animations];
	} delayFactor:0.15];
	
	[animator addAnimations:^{
		[UIView animateKeyframesWithDuration:0.0 delay:0.0 options:0 animations:^{
			[UIView addKeyframeWithRelativeStartTime:0.15 relativeDuration:0.4 animations:^{
				[self performAdditional04Delayed015Animations];
			}];
		} completion:nil];
	}];
	
	[animator addAnimations:^{
		[self performAdditionalDelayed05Animations];
	} delayFactor:0.5];
	
	[animator addAnimations:^{
		[UIView animateKeyframesWithDuration:0.0 delay:0.0 options:0 animations:^{
			[UIView addKeyframeWithRelativeStartTime:0.0 relativeDuration:0.75 animations:^{
				[self performAdditional075Animations];
			}];
		} completion:nil];
	} delayFactor:0.0];
	
	[animator addAnimations:^{
		[UIView animateKeyframesWithDuration:0.0 delay:0.0 options:0 animations:^{
			[UIView addKeyframeWithRelativeStartTime:0.0 relativeDuration:0.1 animations:^{
				[self performAdditional01Animations];
			}];
		} completion:nil];
	} delayFactor:0.0];
	
	[animator addAnimations:^{
		[UIView animateKeyframesWithDuration:0.0 delay:0.0 options:0 animations:^{
			[UIView addKeyframeWithRelativeStartTime:0.15 relativeDuration:0.75 animations:^{
				[self performAdditional075Delayed015Animations];
			}];
		} completion:nil];
	} delayFactor:0.0];
	
	[animator addAnimations:^{
		[UIView animateKeyframesWithDuration:0.0 delay:0.0 options:0 animations:^{
			[UIView addKeyframeWithRelativeStartTime:0.55 relativeDuration:0.35 animations:^{
				[self performAdditional025Delayed060Animations];
			}];
		} completion:nil];
	} delayFactor:0.0];
	
	[animator addCompletion:^(UIViewAnimatingPosition finalPosition) {
		if([self.view respondsToSelector:transitionDidEnd])
		{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
			[self.view performSelector:transitionDidEnd];
#pragma clang diagnostic pop
		}
		
		[self completeTransition];
	}];
}

- (UIView*)barContentView
{
	return _externalSource != nil ? _externalContentView : self.popupBar.contentView;
}

- (void)_positionExternalContent
{
	CGSize size = self.popupContentView.currentPopupContentViewController.view.bounds.size;
	_contentViewTransitionView.frame = CGRectMake(
		(_contentTransitionWrapperView.bounds.size.width - size.width) * 0.5, 0, size.width, size.height);
}

- (void)_captureExternalGeometry
{
	if(_externalSource == nil) { return; }
	[_externalContentView layoutIfNeeded];
	UIView* container = _externalSource.containerView;
	if(container.window == nil || container.window != _externalContentView.window || CGRectIsEmpty(container.bounds))
	{
		container = _externalContentView;
	}
	_externalContainerView = container;
	_externalContainerFrame = [self.popupContentView.superview convertRect:container.bounds fromView:container];
	CGRect contentFrame = [container convertRect:_externalContentView.bounds fromView:_externalContentView];
	contentFrame.origin.x -= container.bounds.origin.x;
	contentFrame.origin.y -= container.bounds.origin.y;
	_externalMiniatureContentFrame = contentFrame;
	_externalArtworkFrameInWindow = [self.popupContentView.window convertRect:_externalArtworkView.bounds fromView:_externalArtworkView];
	_externalContainerCornerRadius = _externalSource.cornerRadius > 0 ? _externalSource.cornerRadius : container.bounds.size.height * 0.5;
	_externalArtworkCornerRadius = _externalSource.artworkCornerRadius;
	_hasCapturedExternalGeometry = YES;
}

- (CGRect)_externalMiniatureFrameForWrapperBounds:(CGRect)bounds
{
	// Preserve the app content's offset inside the public accessory container.
	// Explicit endpoints avoid flexible margins drifting when those offsets differ.
	CGRect frame = _externalMiniatureContentFrame;
	frame.origin.x += bounds.origin.x + (bounds.size.width - _externalContainerFrame.size.width) * 0.5;
	frame.origin.y += bounds.origin.y;
	return frame;
}

- (UIView*)barArtworkView
{
	return _externalSource != nil ? _externalArtworkView : self.popupBar.imageView;
}

- (CGRect)barArtworkFrameInWindow
{
	if(_hasCapturedExternalGeometry) { return _externalArtworkFrameInWindow; }
	UIView* artwork = self.barArtworkView;
	return [self.popupContentView.window convertRect:artwork.bounds fromView:artwork];
}

- (CGRect)barContentFrame
{
	if(_hasCapturedExternalGeometry) { return _externalContainerFrame; }
	UIView* content = _externalSource != nil ? _externalContainerView : self.barContentView;
	return [self.popupContentView.superview convertRect:content.bounds fromView:content];
}

- (CGFloat)barArtworkCornerRadius
{
	if(_hasCapturedExternalGeometry) { return _externalArtworkCornerRadius; }
	return _externalSource != nil ? _externalSource.artworkCornerRadius : self.popupBar.imageView.cornerRadius;
}

- (NSShadow*)barArtworkShadow
{
	if(_externalSource == nil) { return self.popupBar.imageView.shadow; }
	NSShadow* shadow = [NSShadow new];
	shadow.shadowOffset = self.barArtworkView.layer.shadowOffset;
	shadow.shadowBlurRadius = self.barArtworkView.layer.shadowRadius;
	CGColorRef color = self.barArtworkView.layer.shadowColor;
	shadow.shadowColor = color != nil
		? [[UIColor colorWithCGColor:color] colorWithAlphaComponent:self.barArtworkView.layer.shadowOpacity]
		: UIColor.clearColor;
	return shadow;
}

- (LNPopupViewCorners)barContentCorners
{
	if(_externalSource == nil) { return self.popupBar.contentView.effectView.corners; }
	CGFloat radius = _hasCapturedExternalGeometry ? _externalContainerCornerRadius : (_externalSource.cornerRadius > 0 ? _externalSource.cornerRadius : _externalContainerView.bounds.size.height * 0.5);
	CGSize corner = CGSizeMake(radius, radius);
	return (LNPopupViewCorners){corner, corner, corner, corner};
}

- (CGRect)sourceFrame
{
	return CGRectZero;
}

- (CGRect)targetFrame
{
	return CGRectZero;
}

- (CGAffineTransform)transform
{
	return CGAffineTransformIdentity;
}

- (CGFloat)scaledBarImageViewCornerRadius
{
	return 0.0;
}

- (NSShadow *)scaledBarImageViewShadow
{
	return nil;
}

- (LNPopupPresentationState)targetState
{
	return (LNPopupPresentationState)-1;
}

- (UIVisualEffect *)sourceContentTransitionEffect
{
	return nil;
}

- (UIVisualEffect *)targetContentTransitionEffect
{
	return nil;
}

- (CGRect)sourceContentFrame
{
	return CGRectZero;
}

- (CGRect)targetContentFrame
{
	return CGRectZero;
}

- (LNPopupViewCorners)sourceContentCornerRadius
{
	return {0};
}

- (LNPopupViewCorners)targetContentCornerRadius
{
	return {0};
}

- (CGFloat)sourceContentAlpha
{
	return 1.0;
}

- (CGFloat)targetContentAlpha
{
	return 1.0;
}

- (void)beforeAnyAnimation {}
- (void)performBeforeAdditionalAnimations {}
- (void)performAdditionalAnimations {}
- (void)performAdditionalDelayed015Animations {}
- (void)performAdditionalDelayed05Animations {}
- (void)performAdditional01Animations {}
- (void)performAdditional075Animations {}
- (void)performAdditional04Delayed015Animations {}
- (void)performAdditional075Delayed015Animations {}
- (void)performAdditional025Delayed060Animations {}
- (void)performAdditionalCompletion {}

- (void)completeTransition
{
	[UIView performWithoutAnimation:^{
		if(_wantsContentTransition)
		{
			self.view.alpha = _alphaBefore;
			self.popupContentView.effectView.alpha = 1.0;
			if(_externalSource == nil) { self.popupBar.contentView.effectOverride = nil; }
			[_contentTransitionWrapperView removeFromSuperview];
			self.popupContentView.transitionView = nil;
		}
		UIView* transitionView = objc_getAssociatedObject(self.transitionView.sourceLayer, _LNPopupOpenCloseTransitionViewKey);
		[transitionView removeFromSuperview];
		objc_setAssociatedObject(self.transitionView.sourceLayer, _LNPopupOpenCloseTransitionViewKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		self.barArtworkView.alpha = _popupBarImageAlphaBeforeAnimation;
		if(_externalSource != nil && _transitionView != nil)
		{
			self.barArtworkView.layer.cornerRadius = _externalArtworkCornerRadiusBeforeAnimation;
		}
		[self performAdditionalCompletion];
	}];
}

@end
