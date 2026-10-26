//
//  _LNPopupTransitionCloseAnimator.m
//  LNPopupController
//
//  Created by Léo Natan on 2025-03-24.
//  Copyright © 2015-2025 Léo Natan. All rights reserved.
//

#import "_LNPopupTransitionCloseAnimator.h"
#import "UIViewController+LNPopupSupportPrivate.h"

@implementation _LNPopupTransitionCloseAnimator
{
	BOOL _wasGlass;
}

- (instancetype)initWithTransitionView:(_LNPopupTransitionView *)transitionView userView:(UIView *)view popupBar:(LNPopupBar *)popupBar popupContentView:(LNPopupContentView *)popupContentView currentContentController:(UIViewController *)currentContentController containerController:(UIViewController *)containerController
{
	BOOL isAutomatic = NO;
	LNPopupInteractionStyle resolvedStyle = _LNPopupResolveInteractionStyleFromInteractionStyle(containerController.popupInteractionStyle, containerController.popupPresentationState, &isAutomatic);
	self = [super initWithTransitionView:transitionView userView:view popupBar:popupBar popupContentView:popupContentView effectiveInteractionStyle:isAutomatic ? LNPopupInteractionStyleAutomatic : resolvedStyle allowContentTransition:YES];
	
	if(self)
	{
		self.currentContentController = currentContentController;
		self.containerController = containerController;
	}
	
	return self;
}

- (CGRect)sourceFrame
{
	return [self.popupContentView.window.layer convertRect:self.transitionView.sourceLayer.bounds fromLayer:self.transitionView.sourceLayer];
}

- (CGRect)targetFrame
{
	return self.barArtworkFrameInWindow;
}

- (CGFloat)sourceImageAlpha
{
	return 1.0;
}

- (CGFloat)targetImageAlpha
{
	return self.popupBarImageAlphaBeforeAnimation;
}

- (CGFloat)scaledBarImageViewCornerRadius
{
	return MAX(self.barArtworkCornerRadius * self.sourceFrame.size.width / MAX(self.barArtworkView.bounds.size.width, 1.0), self.barArtworkCornerRadius * self.sourceFrame.size.height / MAX(self.barArtworkView.bounds.size.height, 1.0));
}

- (NSShadow *)scaledBarImageViewShadow
{
	NSShadow* scaled = self.barArtworkShadow.copy;
	scaled.shadowBlurRadius = scaled.shadowBlurRadius * self.sourceFrame.size.width / MAX(self.barArtworkView.bounds.size.width, 1.0);
	return scaled;
}

- (LNPopupPresentationState)targetState
{
	return LNPopupPresentationStateBarPresented;
}

- (UIVisualEffect *)sourceContentTransitionEffect
{
	return self.popupContentView._currentEffect;
}

- (UIVisualEffect *)targetContentTransitionEffect
{
	return self.popupBarEffect;
}

- (CGRect)sourceContentFrame
{
	return [self.popupContentView.superview convertRect:self.popupContentView.bounds fromView:self.popupContentView];
}

- (CGRect)targetContentFrame
{
	return self.barContentFrame;
}

- (LNPopupViewCorners)sourceContentCornerRadius
{
	return [LNPopupContentView cornersForContentView:self.popupContentView];
}

- (LNPopupViewCorners)targetContentCornerRadius
{
	return self.barContentCorners;
}

- (CGFloat)sourceContentAlpha
{
	return 1.0;
}

- (CGFloat)targetContentAlpha
{
	return 0.0;
}

- (void)beforeAnyAnimation
{
	[super beforeAnyAnimation];
	
	self.crossfadeView.alpha = 0.0;
	self.crossfadeView.cornerRadius = self.transitionView.cornerRadius;
	
	self.popupBarTransitionView.alpha = 0.0;
}

- (void)performAdditionalAnimations
{
	[super performAdditionalAnimations];
	
	[self.transitionView setTargetFrameUpdatingTransform:self.targetFrame];
	self.crossfadeView.cornerRadius = self.barArtworkCornerRadius;
	
	if(self.popupContentView._currentEffect.ln_isGlass)
	{
		_wasGlass = YES;
	}
}

- (void)performAdditionalDelayed015Animations
{
	[super performAdditionalDelayed015Animations];
	
	self.popupBarTransitionView.alpha = 1.0;
	self.contentViewTransitionView.alpha = 0.0;
	if(self.accessoryTransitionEffectView != nil)
	{
		// Each material retains its own traits. Animate the effects rather than
		// changing the full player's style before its first closing frame.
		self.contentTransitionEffectView.effect = nil;
		self.accessoryTransitionEffectView.effect = self.popupBarEffect;
	}
}

- (void)performAdditional04Delayed015Animations
{
	[super performAdditional04Delayed015Animations];
	
	self.crossfadeView.alpha = 1.0;
	
	if(self.wantsContentTransition == NO)
	{
		if(self.containerController._ln_shouldPopupContentAnyFadeForTransition)
		{
			if(self.containerController._ln_shouldPopupContentViewFadeForTransition)
			{
				if(_wasGlass)
				{
					self.currentContentController.view.alpha = 0.0;
					//An effect view with glass effect has its layer contained in a _UIMultiLayer
					self.popupContentView.effectView.layer.superlayer.opacity = 0.0;
				}
				else
				{
					self.popupContentView.alpha = 0.0;
				}
			}
			else
			{
				self.currentContentController.view.alpha = 0.0;
			}
		}
	}
}

- (void)performAdditional025Delayed060Animations
{
	[super performAdditional025Delayed060Animations];

	if(self.popupBar.externalTransitionSource != nil && self.wantsContentTransition)
	{
		// The system accessory's glass remains visible beneath this temporary
		// surface. Finish its fade before landing to avoid stacking two materials.
		// The miniature content portal is a sibling; artwork is in the window.
		self.accessoryTransitionEffectView.effect = nil;
	}
}

- (void)performAdditionalCompletion
{
	[super performAdditionalCompletion];
	
	if(self.wantsContentTransition == NO)
	{
		self.popupContentView.alpha = 1.0;
		self.currentContentController.view.alpha = 1.0;
		if(_wasGlass)
		{
			self.popupContentView.effectView.layer.superlayer.opacity = 1.0;
		}
	}
}

@end
