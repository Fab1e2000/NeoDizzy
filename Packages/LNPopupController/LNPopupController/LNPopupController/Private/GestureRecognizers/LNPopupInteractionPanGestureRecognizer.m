//
//  LNPopupInteractionPanGestureRecognizer.m
//  LNPopupController
//
//  Created by Léo Natan on 2017-07-15.
//  Copyright © 2015-2025 Léo Natan. All rights reserved.
//

#import "LNPopupInteractionPanGestureRecognizer.h"
#import "LNForwardingDelegate.h"
#import "UIViewController+LNPopupSupportPrivate.h"
#import "LNPopupControllerImpl.h"
#import "UIView+LNPopupSupportPrivate.h"
#import <UIKit/UIGestureRecognizerSubclass.h>

// Explicit app/library contract. Never infer a SwiftUI recognizer's purpose
// from its private class name.
static NSString* const LNPopupExternalDismissPanName = @"LNPopupExternalDismissPan";
static NSString* const LNPopupExternalTrackSwipeName = @"NeoDizzy.NowPlayingTrackSwipe";

static BOOL LNPopupExternalCanCoordinateWithGesture(UIGestureRecognizer* gesture)
{
	if([gesture.name isEqualToString:LNPopupExternalTrackSwipeName]) { return YES; }
	return [gesture.view isKindOfClass:UIScrollView.class] &&
		gesture == ((UIScrollView*)gesture.view).panGestureRecognizer;
}

@interface UIViewController ()

- (CGRect)_ln_interactionLimitRect;

@end

@interface LNPopupInteractionPanGestureRecognizerDelegate : LNForwardingDelegate <UIGestureRecognizerDelegate>
@end

@implementation LNPopupInteractionPanGestureRecognizerDelegate
{
	__weak LNPopupController* _popupController;
}

- (instancetype)initWithPopupController:(LNPopupController*)popupController
{
	self = [super init];
	
	if(self)
	{
		_popupController = popupController;
	}
	
	return self;
}

- (BOOL)gestureRecognizer:(LNPopupInteractionPanGestureRecognizer *)gestureRecognizer shouldReceiveEvent:(UIEvent *)event API_AVAILABLE(ios(13.4))
{
	if([self.forwardedDelegate respondsToSelector:_cmd])
	{
		return [self.forwardedDelegate gestureRecognizer:gestureRecognizer shouldReceiveEvent:event];
	}
	
	BOOL rv = YES;
	
	if(event.type == UIEventTypeTouches)
	{
		UITouch* touch = event.allTouches.anyObject;
		if(touch.type == UITouchTypeIndirectPointer && gestureRecognizer.allowsIndirectPointerInteraction == NO
#if !TARGET_OS_MACCATALYST
		   && [touch.view isDescendantOfView:_popupController.popupBar] == NO
#endif
		   )
		{
			return NO;
		}
	}
	
	return rv;
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer
{
	LNPopupInteractionStyle resolvedStyle = _LNPopupResolveInteractionStyleFromInteractionStyle(_popupController.containerController.popupInteractionStyle, _popupController.popupControllerPublicState, NULL);
	
	BOOL rv = resolvedStyle != LNPopupInteractionStyleNone;
	LNPopupExternalTransitionSource* source = _popupController.popupBar.externalTransitionSource;
	if(source != nil)
	{
		// The external host explicitly chooses its draggable regions. Do not
		// infer eligibility from SwiftUI private classes or nested scroll views.
		return rv && (source.interactionShouldBegin == nil || source.interactionShouldBegin((UIPanGestureRecognizer*)gestureRecognizer));
	}
	
	if(rv && gestureRecognizer.view == _popupController.currentContentController.view && [_popupController.currentContentController respondsToSelector:@selector(_ln_interactionLimitRect)])
	{
		CGRect limit = [_popupController.currentContentController _ln_interactionLimitRect];
		CGPoint interactionPoint = [gestureRecognizer locationInView:gestureRecognizer.view];
		
		if(CGRectContainsPoint(limit, interactionPoint) == NO)
		{
			return NO;
		}
	}
	
	if(rv && [self.forwardedDelegate respondsToSelector:_cmd])
	{
		return [self.forwardedDelegate gestureRecognizerShouldBegin:gestureRecognizer];
	}
	
	return rv;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer
{
	if(_popupController.popupBar.externalTransitionSource != nil)
	{
		BOOL coordinates = LNPopupExternalCanCoordinateWithGesture(otherGestureRecognizer);
		if(coordinates)
		{
			[(LNPopupInteractionPanGestureRecognizer*)gestureRecognizer _recordExternalCoordinatedGesture:otherGestureRecognizer];
		}
		return coordinates;
	}
	if([NSStringFromClass(otherGestureRecognizer.view.class) containsString:@"DropShadow"])
	{
		otherGestureRecognizer.state = UIGestureRecognizerStateFailed;
		return YES;
	}
	
	if([NSStringFromClass(otherGestureRecognizer.class) containsString:@"Reveal"])
	{
		return NO;
	}
	
	if([NSStringFromClass(otherGestureRecognizer.view.class) containsString:@"SwiftUI"])
	{
		return YES;
	}
	
	//View hierarchy might add more and more views with gesture recognizers. Let's try to "import" them for our system.
	[_popupController _fixupGestureRecognizer:otherGestureRecognizer];
	
	if([otherGestureRecognizer.view isKindOfClass:UIScrollView.class] && [(UIScrollView*)otherGestureRecognizer.view _ln_hasVerticalContent] == NO && [(UIScrollView*)otherGestureRecognizer.view _ln_hasHorizontalContent] == NO)
	{
		return YES;
	}
	
	if(_popupController.popupControllerInternalState != LNPopupPresentationStateOpen)
	{
		if([self.forwardedDelegate respondsToSelector:_cmd])
		{
			return [self.forwardedDelegate gestureRecognizer:gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:otherGestureRecognizer];
		}
		
		return YES;
	}
	
	return NO;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldBeRequiredToFailByGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer
{
	if(_popupController.popupBar.externalTransitionSource != nil) { return NO; }
	//This is to disable gesture recognizers in the superview while dragging the popup bar. This is mostly to fix issues when the bar is part of a scroll view scene, such as `UITableViewController` / `UITableView`.
	if([_popupController.popupBar.superview.gestureRecognizers containsObject:otherGestureRecognizer])
	{
		return YES;
	}
	
	if([otherGestureRecognizer.view isKindOfClass:[UIScrollView class]])
	{
		if(@available(iOS 26.0, *))
		{
			return NO;
		}
		
		if(otherGestureRecognizer.view == gestureRecognizer.view)
		{
			return NO;
		}
		else
		{
			return [(UIScrollView*)otherGestureRecognizer.view _ln_hasVerticalContent] == YES;
		}
	}
	
	if([self.forwardedDelegate respondsToSelector:_cmd])
	{
		return [self.forwardedDelegate gestureRecognizer:gestureRecognizer shouldBeRequiredToFailByGestureRecognizer:otherGestureRecognizer];
	}
	
	return NO;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRequireFailureOfGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer
{
	if(_popupController.popupBar.externalTransitionSource != nil) { return NO; }
	if(_popupController.popupControllerInternalState != LNPopupPresentationStateOpen)
	{
		return NO;
	}
	
	if([self.forwardedDelegate respondsToSelector:_cmd])
	{
		return [self.forwardedDelegate gestureRecognizer:gestureRecognizer shouldRequireFailureOfGestureRecognizer:otherGestureRecognizer];
	}
	
	if([otherGestureRecognizer.name hasPrefix:@"undointeraction"])
	{
		return NO;
	}
	
	if([otherGestureRecognizer.view isKindOfClass:UIScrollView.class] && [(UIScrollView*)otherGestureRecognizer.view _ln_hasVerticalContent] == NO)
	{
		return NO;
	}

	if([NSStringFromClass(otherGestureRecognizer.view.class) containsString:@"SwiftUI"])
	{
		return YES;
	}
	
	return YES;
}

@end

@implementation LNPopupInteractionPanGestureRecognizer
{
	LNPopupInteractionPanGestureRecognizerDelegate* _actualDelegate;
	__weak LNPopupController* _popupController;
	__weak UIView* _initialTouchView;
	__weak UITouch* _intentTouch;
	CGPoint _initialTouchLocation;
	BOOL _externalVerticalIntentConfirmed;
	BOOL _resetTranslationOnVerticalCommit;
	NSHashTable<UIGestureRecognizer*>* _coordinatedGestures;
	NSHashTable<UIGestureRecognizer*>* _cancelledTrackSwipes;
}

- (instancetype)initWithTarget:(id)target action:(SEL)action popupController:(LNPopupController*)popupController
{
	self = [super initWithTarget:target action:action];
	
	if(self)
	{
		_popupController = popupController;
		_coordinatedGestures = NSHashTable.weakObjectsHashTable;
		_cancelledTrackSwipes = NSHashTable.weakObjectsHashTable;
		self.name = LNPopupExternalDismissPanName;
		_actualDelegate = [[LNPopupInteractionPanGestureRecognizerDelegate alloc] initWithPopupController:popupController];
		[super setDelegate:_actualDelegate];
	}
	
	return self;
}

- (UIView*)initialTouchView
{
	return _initialTouchView;
}

- (BOOL)externalVerticalIntentConfirmed
{
	return _popupController.popupBar.externalTransitionSource == nil || _externalVerticalIntentConfirmed;
}

- (void)touchesBegan:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event
{
	if(_intentTouch == nil)
	{
		UITouch* touch = touches.anyObject;
		_intentTouch = touch;
		_initialTouchView = touch.view;
		_initialTouchLocation = [touch locationInView:nil];
	}
	[super touchesBegan:touches withEvent:event];
}

- (void)touchesMoved:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event
{
	if(_popupController.popupBar.externalTransitionSource != nil && !_externalVerticalIntentConfirmed && _intentTouch != nil)
	{
		// Window coordinates stay fixed while the full player follows the hand.
		CGPoint location = [_intentTouch locationInView:nil];
		BOOL scrollsAreAtTop = YES;
		for(UIView* ancestor = _initialTouchView; ancestor != nil; ancestor = ancestor.superview)
		{
			if([ancestor isKindOfClass:UIScrollView.class])
			{
				UIScrollView* scrollView = (UIScrollView*)ancestor;
				if(scrollView.isScrollEnabled && scrollView.contentOffset.y > -scrollView.adjustedContentInset.top + 1.0)
				{
					scrollsAreAtTop = NO;
					break;
				}
			}
			if(ancestor == self.view) { break; }
		}
		if(!scrollsAreAtTop)
		{
			// A gesture that started at the top may first scroll upward. That
			// earlier travel must not become popup displacement on the way back.
			_initialTouchLocation = location;
			_resetTranslationOnVerticalCommit = YES;
		}
		else
		{
			CGFloat dx = location.x - _initialTouchLocation.x;
			CGFloat dy = location.y - _initialTouchLocation.y;
			_externalVerticalIntentConfirmed = dy >= 6.0 && dy >= fabs(dx) * 0.8;
			if(_externalVerticalIntentConfirmed && _resetTranslationOnVerticalCommit)
			{
				[self setTranslation:CGPointZero inView:self.view.window];
			}
		}
	}
	// Keep UIKit's pan tracking intact. LN's handler leaves the popup stationary
	// while intent is pending; this allows an initial sideways drift to turn down.
	[super touchesMoved:touches withEvent:event];
	if(_externalVerticalIntentConfirmed &&
	   (self.state == UIGestureRecognizerStateBegan || self.state == UIGestureRecognizerStateChanged))
	{
		[self _cancelExternalTrackSwipe];
	}
}

- (void)_recordExternalCoordinatedGesture:(UIGestureRecognizer*)gesture
{
	[_coordinatedGestures addObject:gesture];
}

- (void)_cancelExternalTrackSwipe
{
	// The initial hit-test ancestry also covers a recognizer that is still
	// possible and has not reached simultaneous-recognition arbitration yet.
	for(UIView* ancestor = _initialTouchView; ancestor != nil; ancestor = ancestor.superview)
	{
		for(UIGestureRecognizer* gesture in ancestor.gestureRecognizers)
		{
			if([gesture.name isEqualToString:LNPopupExternalTrackSwipeName])
			{
				[_coordinatedGestures addObject:gesture];
			}
		}
		if(ancestor == self.view) { break; }
	}
	for(UIGestureRecognizer* gesture in _coordinatedGestures.allObjects)
	{
		if([gesture.name isEqualToString:LNPopupExternalTrackSwipeName] && gesture.enabled &&
		   ![_cancelledTrackSwipes containsObject:gesture] &&
		   (gesture.state == UIGestureRecognizerStatePossible || gesture.state == UIGestureRecognizerStateBegan || gesture.state == UIGestureRecognizerStateChanged))
		{
			// Cancellation resets the title offset without committing a track.
			[_cancelledTrackSwipes addObject:gesture];
			gesture.enabled = NO;
			gesture.enabled = YES;
		}
	}
}

- (BOOL)canPreventGestureRecognizer:(UIGestureRecognizer*)gesture
{
	if(_popupController.popupBar.externalTransitionSource != nil && LNPopupExternalCanCoordinateWithGesture(gesture))
	{
		[self _recordExternalCoordinatedGesture:gesture];
		return NO;
	}
	return [super canPreventGestureRecognizer:gesture];
}

- (BOOL)canBePreventedByGestureRecognizer:(UIGestureRecognizer*)gesture
{
	if(_popupController.popupBar.externalTransitionSource != nil && LNPopupExternalCanCoordinateWithGesture(gesture))
	{
		[self _recordExternalCoordinatedGesture:gesture];
		return NO;
	}
	return [super canBePreventedByGestureRecognizer:gesture];
}

- (void)reset
{
	[super reset];
	_initialTouchView = nil;
	_intentTouch = nil;
	_externalVerticalIntentConfirmed = NO;
	_resetTranslationOnVerticalCommit = NO;
	[_coordinatedGestures removeAllObjects];
	[_cancelledTrackSwipes removeAllObjects];
}

- (id<UIGestureRecognizerDelegate>)delegate
{
	if([LNForwardingDelegate isCallerUIKit:NSThread.callStackReturnAddresses])
	{
		return _actualDelegate;
	}
	
	return _actualDelegate.forwardedDelegate;
}

- (void)setDelegate:(id<UIGestureRecognizerDelegate>)delegate
{
	_actualDelegate = [[LNPopupInteractionPanGestureRecognizerDelegate alloc] initWithPopupController:_popupController];
	_actualDelegate.forwardedDelegate = delegate;
	[super setDelegate:_actualDelegate];
}

@end
