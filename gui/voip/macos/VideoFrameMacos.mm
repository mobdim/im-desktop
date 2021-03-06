#include "stdafx.h"
#import "VideoFrameMacos.h"
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <IOKit/pwr_mgt/IOPMLib.h>
#include "render/VOIPRenderViewClasses.h"
#include "../../utils/utils.h"
#include "platform_specific/macos/x64/iTunes.h"
#include "styles/ThemeParameters.h"
#include "voip/CommonUI.h"

@interface WindowRect : NSObject
{
}

@property NSRect rect;

@end

@implementation WindowRect

-(instancetype)init
{
    self = [super init];
    if (!!self)
    {
        NSRect rc;
        rc.origin.x = 0.0f;
        rc.origin.y = 0.0f;
        rc.size.width  = 0.0f;
        rc.size.height = 0.0f;
        self.rect = rc;
    }
    return self;
}

@end

@interface WindowListApplierData : NSObject
{
}

@property (strong, nonatomic) NSMutableArray* outputArray;
@property int order;

@end

@implementation WindowListApplierData

-(instancetype)initWindowListData:(NSMutableArray *)array
 {
    self = [super init];
    if (!!self)
    {
        self.outputArray = array;
        self.order = 0;
    }
    return self;
}

-(void)dealloc
{
    if (!!self && !!self.outputArray)
    {
        for (id item in self.outputArray)
        {
            [item release];
        }
    }
    [super dealloc];
}

@end

@interface FullScreenDelegate : NSObject <NSWindowDelegate>
{
    platform_macos::FullScreenNotificaton* _notification;
    // Save prev delegate
    NSObject <NSWindowDelegate>* _oldDelegate;
}
@end

@implementation FullScreenDelegate

-(id)init: (platform_macos::FullScreenNotificaton*) notification
     withOldDelegate:(NSObject <NSWindowDelegate>*) oldDelegate
{
    if (![super init])
        return nil;
    _notification = notification;
    _oldDelegate  = oldDelegate;
    [self registerSpaceNotification];
    return self;
}

-(void)dealloc
{
    [self unregisterSpaceNotification];
    [super dealloc];
}

-(void)windowWillEnterFullScreen:(NSNotification *)notification
{
    if (_notification)
        _notification->fullscreenAnimationStart();
}

-(void)windowDidEnterFullScreen:(NSNotification *)notification
{
    if (_notification)
        _notification->fullscreenAnimationFinish();
}

-(void)windowWillExitFullScreen:(NSNotification *)notification
{
    if (_notification)
        _notification->fullscreenAnimationStart();
}

-(void)windowDidExitFullScreen:(NSNotification *)notification
{
    if (_notification)
        _notification->fullscreenAnimationFinish();
}

-(void)activeSpaceDidChange:(NSNotification *)notification
{
    if (_notification)
        _notification->activeSpaceDidChange();
}

-(void)registerSpaceNotification
{
    NSNotificationCenter *notificationCenter = [[NSWorkspace sharedWorkspace] notificationCenter];
    if (notificationCenter)
    {
        [notificationCenter addObserver:self
           selector:@selector(activeSpaceDidChange:)
               name:NSWorkspaceActiveSpaceDidChangeNotification
             object:[NSWorkspace sharedWorkspace]];
    }
}

-(void)unregisterSpaceNotification
{
    NSNotificationCenter *notificationCenter = [[NSWorkspace sharedWorkspace] notificationCenter];
    if (notificationCenter)
        [notificationCenter removeObserver:self];
}

-(BOOL)windowShouldClose:(id)sender
{
    if (_oldDelegate)
        return [_oldDelegate windowShouldClose: sender];
    return YES;
}

-(NSObject<NSWindowDelegate>*)getDelegate
{
    return _oldDelegate;
}

@end

NSString *kAppNameKey      = @"applicationName"; // Application Name & PID
NSString *kWindowOriginKey = @"windowOrigin";    // Window Origin as a string
NSString *kWindowSizeKey   = @"windowSize";      // Window Size as a string
NSString *kWindowRectKey   = @"windowRect";      // The overall front-to-back ordering of the windows as returned by the window server
NSString *kWindowIDKey     = @"windowId";

inline uint32_t ChangeBits(uint32_t currentBits, uint32_t flagsToChange, BOOL setFlags)
{
    if (setFlags)
        return currentBits | flagsToChange;
    else
        return currentBits & ~flagsToChange;
}

void WindowListApplierFunction(const void *inputDictionary, void *context)
{
    assert(!!inputDictionary && !!context);
    if (!inputDictionary || !context)
        return;

    NSDictionary* entry         = (__bridge NSDictionary*)inputDictionary;
    WindowListApplierData* data = (__bridge WindowListApplierData*)context;

    int sharingState = [entry[(id)kCGWindowSharingState] intValue];
    if (sharingState != kCGWindowSharingNone)
    {
        NSMutableDictionary *outputEntry = [NSMutableDictionary dictionary];
        assert(!!outputEntry);
        if (!outputEntry)
            return;

        NSString* applicationName = entry[(id)kCGWindowOwnerName];
        if(applicationName != NULL)
        {
            if ([applicationName compare:@"dock" options:NSCaseInsensitiveSearch] == NSOrderedSame)
                return;
#ifdef _DEBUG
            NSString *nameAndPID = [NSString stringWithFormat:@"%@ (%@)", applicationName, entry[(id)kCGWindowOwnerPID]];
            outputEntry[kAppNameKey] = nameAndPID;
#endif
        } else
            return;

        CGRect bounds;
        CGRectMakeWithDictionaryRepresentation((CFDictionaryRef)entry[(id)kCGWindowBounds], &bounds);
#ifdef _DEBUG
        NSString *originString = [NSString stringWithFormat:@"%.0f/%.0f", bounds.origin.x, bounds.origin.y];
        outputEntry[kWindowOriginKey] = originString;
        NSString *sizeString = [NSString stringWithFormat:@"%.0f*%.0f", bounds.size.width, bounds.size.height];
        outputEntry[kWindowSizeKey] = sizeString;
#endif
        outputEntry[kWindowIDKey] = entry[(id)kCGWindowNumber];

        WindowRect* wr = [[WindowRect alloc] init];
        wr.rect = bounds;
        outputEntry[kWindowRectKey] = wr;

        [data.outputArray addObject:outputEntry];
    }
}

void platform_macos::fadeIn(QWidget* wnd)
{
    assert(!!wnd);
    if (!wnd)
        return;

    NSView* view = (NSView*)wnd->winId();
    assert(view);

    NSWindow* window = [view window];
    assert(window);

    if ([[window animator] alphaValue] < 0.01f)
        [[window animator] setAlphaValue:1.0f];
}

void platform_macos::fadeOut(QWidget* wnd)
{
    assert(!!wnd);
    if (!wnd)
        return;

    NSView* view = (NSView*)wnd->winId();
    assert(view);

    NSWindow* window = [view window];
    assert(window);

    if ([[window animator] alphaValue] > 0.9f)
        [[window animator] setAlphaValue:0.0f];
}

void platform_macos::setPanelAttachedAsChild(bool attach, QWidget* parent, QWidget* child)
{
    NSView* parentView = (NSView*)parent->winId();
    assert(parentView);
    if (!parentView)
        return;

    NSWindow* parentWindow = [parentView window];
    assert(parentWindow);

    NSView* childView = (NSView*)child->winId();
    assert(childView);
    if (!childView)
        return;

    NSWindow* childWindow = [childView window];
    assert(childWindow);
    if (!childWindow)
        return;

    if (attach)
        [parentWindow addChildWindow:childWindow ordered:NSWindowAbove];
    else
        [parentWindow removeChildWindow:childWindow];
}

void platform_macos::setWindowPosition(QWidget& widget, const QRect& widgetRect)
{
    NSView* view = (NSView*)widget.winId();
    assert(view);

    NSWindow* window = [view window];
    assert(window);

    /*
    const int widgetH = widget.height();
    if (top)
        rect.origin.y = rect.origin.y + rect.size.height - widgetH;
    rect.size.height = widgetH;
    */

    NSRect rect;
    rect.size.width  = widgetRect.width();
    rect.size.height = widgetRect.height();
    rect.origin.x    = widgetRect.left();
    rect.origin.y    = widgetRect.top();

    [window setFrame:rect display:YES];
}

QRect platform_macos::getWidgetRect(const QWidget& widget)
{
    NSRect rect;
    {
        // get parent window rect
        NSView* view = (NSView*)widget.winId();
        assert(view);
        if (!view)
            return QRect();

        NSWindow* window = [view window];
        assert(window);
        if (!window)
            return QRect();

        rect = [window frame];
    }
    return QRect(rect.origin.x, rect.origin.y, rect.size.width, rect.size.height);
}

int platform_macos::getWidgetHeaderHeight(const QWidget& widget)
{
    int res = 0;
    // get parent window rect
    NSView* view = (NSView*)widget.winId();
    assert(view);
    if (!view)
        return 0;

    NSWindow* window = [view window];
    assert(window);
    if (!window)
        return 0;

    CGFloat contentHeight = [window contentRectForFrameRect: window.frame].size.height;
    res = int(window.frame.size.height - contentHeight);
    return res;
}

/*
QRect platform_macos::getWindowRect(const QWidget& parent)
{
    NSRect rect;
    NSView* view = (NSView*)parent.winId();
    assert(view);
    if (!view)
        return parent.geometry();

    NSWindow* window = [view window];
    assert(window);
    if (!window)
        return parent.geometry();

    rect = [window frame];

    // TODO: implement for multi screens.
    NSScreen *screen = [window screen];
    if (screen)
    {
        NSRect screenRect = [screen frame];
        return QRect(rect.origin.x, screenRect.size.height - (rect.origin.y + rect.size.height), rect.size.width, rect.size.height);
    } else
    {
        return QRect(rect.origin.x, rect.origin.y, rect.size.width, rect.size.height);
    }
}
*/

void setAspectRatioForWindow(QWidget& wnd, float w, float h) {
    NSView* view = (NSView*)wnd.winId();
    assert(view);
    if (view)
    {
        NSWindow* window = [view window];
        assert(window);
        if (window)
        {
            if (w > 0.0f)
                [window setContentAspectRatio: NSMakeSize(w, h)];
            else
                [window setResizeIncrements: NSMakeSize(1.0, 1.0)];
        }
    }
}

void platform_macos::setAspectRatioForWindow(QWidget& wnd, float aspectRatio)
{
    setAspectRatioForWindow(wnd, 10.0f * aspectRatio, 10.0f);
}

void platform_macos::unsetAspectRatioForWindow(QWidget& wnd)
{
    setAspectRatioForWindow(wnd, 0.0f, 0.0f);
}

bool platform_macos::windowIsOverlapped(QWidget* frame, const std::vector<QWidget*>& _exclude) {
    assert(!!frame);
    if (!frame)
        return false;

    NSView* view = (NSView*)frame->winId();
    assert(!!view);
    if (!view)
        return false;

    NSWindow* window = [view window];
    assert(!!window);
    if (!window)
        return false;

    QRect screenGeometry = QDesktopWidget().availableGeometry(frame);

    const CGWindowID windowID = (CGWindowID)[window windowNumber];
    CGWindowListOption listOptions = kCGWindowListOptionOnScreenAboveWindow;
    listOptions = ChangeBits(listOptions, kCGWindowListExcludeDesktopElements, YES);

    CFArrayRef windowList = CGWindowListCopyWindowInfo(listOptions, windowID);
    NSMutableArray * prunedWindowList = [NSMutableArray array];
    WindowListApplierData* windowListData = [[WindowListApplierData alloc] initWindowListData:prunedWindowList];

    CFArrayApplyFunction(windowList, CFRangeMake(0, CFArrayGetCount(windowList)), &WindowListApplierFunction, (__bridge void *)(windowListData));

    // Flip y coord.
    const QRect frameRect([window frame].origin.x, screenGeometry.height() - int([window frame].origin.y + [window frame].size.height), [window frame].size.width, [window frame].size.height);
    const int originalSquare = frameRect.width() * frameRect.height();

    // Fill array with exclude window id.
    QList<CGWindowID> excludeWindowID;
    for (auto widget : _exclude)
    {
        if (widget)
        {
            NSView* view = (NSView*)widget->winId();
            if (view)
            {
                NSWindow* window = [view window];
                if (window)
                    excludeWindowID.push_back((CGWindowID)[window windowNumber]);
            }
        }
    }

    QRegion selfRegion(frameRect);
    for (NSMutableDictionary* params in windowListData.outputArray)
    {
        // Skip if it is excluded window.
        CGWindowID winId = [params[kWindowIDKey] unsignedIntValue];
        if (excludeWindowID.indexOf(winId) != -1)
        {
            continue;
        }
        WindowRect* wr = params[kWindowRectKey];
        QRect rc(wr.rect.origin.x, wr.rect.origin.y, wr.rect.size.width, wr.rect.size.height);
        QRegion wrRegion(rc);
        selfRegion -= wrRegion;
    }

    int remainsSquare = 0;
    const auto remainsRects = selfRegion.rects();
    for (unsigned ix = 0; ix < remainsRects.count(); ++ix)
    {
        const QRect& rc = remainsRects.at(ix);
        remainsSquare += rc.width() * rc.height();
    }

    [windowListData release];
    CFRelease(windowList);

    return remainsSquare < originalSquare*0.6f;
}

bool platform_macos::pauseiTunes()
{
    bool res = false;
    iTunesApplication* iTunes = [SBApplication applicationWithBundleIdentifier:@"com.apple.iTunes"];
    if ([iTunes isRunning])
    {
        // pause iTunes if it is currently playing.
        if (iTunesEPlSPlaying == [iTunes playerState])
        {
            [iTunes playpause];
            res = true;
        }
    }
    return res;
}

void platform_macos::playiTunes()
{
    iTunesApplication* iTunes = [SBApplication applicationWithBundleIdentifier:@"com.apple.iTunes"];
    if ([iTunes isRunning])
    {
        // play iTunes if it was paused.
        if (iTunesEPlSPaused == [iTunes playerState])
        {
            [iTunes playpause];
        }
    }
}

void platform_macos::moveAboveParentWindow(QWidget& parent, QWidget& child)
{
    NSView* parentView = (NSView*)parent.winId();
    assert(parentView);

    NSWindow* window = [parentView window];
    assert(window);

    NSView* childView = (NSView*)child.winId();
    assert(childView);
    if (!childView)
        return;

    NSWindow* childWnd = [childView window];
    assert(childWnd);
    if (!childWnd)
        return;

    [childWnd orderWindow: NSWindowAbove relativeTo: [window windowNumber]];
}

int platform_macos::doubleClickInterval()
{
    return [NSEvent doubleClickInterval] * 1000;
}

NSWindow* getNSWindow(QWidget& parentWindow)
{
    NSWindow* res = nil;
    NSView* view = (NSView*)parentWindow.winId();
    assert(view);
    if (view)
        res = [view window];
    return res;
}

platform_macos::FullScreenNotificaton::FullScreenNotificaton (QWidget& parentWindow) : _delegate(nil), _parentWindow(parentWindow)
{
    NSWindow* window = getNSWindow(_parentWindow);
    assert(!!window);
    if (window)
    {
        FullScreenDelegate* delegate = [[FullScreenDelegate alloc] init: this withOldDelegate: [window delegate]];
        [window setDelegate: delegate];
        _delegate = delegate;
        //[delegate retain];
    }
}

platform_macos::FullScreenNotificaton::~FullScreenNotificaton ()
{
    NSWindow* window = getNSWindow(_parentWindow);
    if (window)
    {
        if (_delegate)
        {
            // return old delegate back.
            [window setDelegate: [(FullScreenDelegate*)_delegate getDelegate]];
        } else
        {
            [window setDelegate: nil];
        }
    }
    if (_delegate != nil)
        [(FullScreenDelegate*)_delegate release];
}



namespace platform_macos {

class GraphicsPanelMacosImpl : public platform_specific::GraphicsPanel {
    std::vector<QPointer<Ui::BaseVideoPanel>> _panels;
    NSView* _renderView;

    virtual void moveEvent(QMoveEvent*) override;
    virtual void resizeEvent(QResizeEvent*) override;
    virtual void showEvent(QShowEvent*) override;
    virtual void hideEvent(QHideEvent*) override;
    virtual void mousePressEvent(QMouseEvent * event) override;
    virtual void mouseReleaseEvent(QMouseEvent * event) override;
    virtual void mouseMoveEvent(QMouseEvent* _e) override;
    virtual bool eventFilter(QObject *obj, QEvent *event) override;

    virtual void createdTalk(bool is_vcs) override;
    virtual void startedTalk() override;
    virtual void exitTalk() override;

    void _setPanelsAttached(bool attach);
    void _mouseMoveEvent(QMouseEvent* _e);

public:
    GraphicsPanelMacosImpl(QWidget* parent, std::vector<QPointer<Ui::BaseVideoPanel>>& panels, bool primaryVideo, bool titleBar);
    virtual ~GraphicsPanelMacosImpl();

    virtual WId frameId() const override;

    void addPanels(std::vector<QPointer<Ui::BaseVideoPanel> >& panels) override;
    void fullscreenModeChanged(bool fullscreen) override;
    void clearPanels() override;

    void fullscreenAnimationStart() override;
    void fullscreenAnimationFinish() override;
    void windowWillDeminiaturize() override;
    void windowDidDeminiaturize()  override;

    QPoint mouseMovePoint;
    bool primaryVideo_;
    bool disableMouseEvents_;
};

GraphicsPanelMacosImpl::GraphicsPanelMacosImpl(QWidget* parent, std::vector<QPointer<Ui::BaseVideoPanel>>& panels, bool primaryVideo, bool titleBar)
    : platform_specific::GraphicsPanel(parent)
    , _panels(panels)
    , primaryVideo_ (primaryVideo)
    , disableMouseEvents_(true)
{

    //primaryVideo_ = false;

    setAttribute(Qt::WA_ShowWithoutActivating);
    setAttribute(Qt::WA_X11DoNotAcceptFocus);
    setAttribute(Qt::WA_UpdatesDisabled);

    //NSView* window = (NSView*)parent->winId();
    //[[window window] setStyleMask:NSTitledWindowMask];

    /*Class viewClass = NSClassFromString(@"VOIPRenderViewOGL");
    assert(viewClass);

    if (viewClass)*/
    {

        NSView* parentView = (NSView*)(parent ? parent->winId() : winId());
        assert(parentView);

        NSWindow* window = [parentView window];
        assert(window);

        if (!titleBar)
        {
            [[window standardWindowButton:NSWindowCloseButton] setHidden:YES];
            [[window standardWindowButton:NSWindowMiniaturizeButton] setHidden:YES];
            [[window standardWindowButton:NSWindowZoomButton] setHidden:YES];

            if (QSysInfo().macVersion() >= QSysInfo::MV_10_10)
            {
                [window setValue:@(YES) forKey:@"titlebarAppearsTransparent"];
                [window setValue:@(1) forKey:@"titleVisibility"];
                //        window.titlebarAppearsTransparent = YES;
                //        window.titleVisibility = NSWindowTitleHidden;
                window.styleMask |= (1 << 15);//NSFullSizeContentViewWindowMask;
            }
        }

        //window.movable = NO;
        window.movableByWindowBackground  = NO;
        const auto color = Styling::getParameters().getColor(Styling::StyleVariable::APP_PRIMARY);

        window.backgroundColor = [NSColor
                colorWithCalibratedRed: color.redF()
                green: color.greenF()
                blue: color.blueF()
                alpha: color.alphaF()];

        /*if([VOIPMTLRenderView isSupported]) {
            _renderView = [[VOIPMTLRenderView alloc] initWithFrame:parentView.frame];
        } else*/ {
            _renderView = [[VOIPRenderViewOGL alloc] initWithFrame:parentView.frame];
        }
        assert(_renderView);

        window.contentView.autoresizesSubviews = YES;
        parentView.autoresizesSubviews = YES;
        [parentView addSubview:_renderView];
    }
}

GraphicsPanelMacosImpl::~GraphicsPanelMacosImpl() {
    [_renderView release];
}

WId GraphicsPanelMacosImpl::frameId() const {
    return (WId)_renderView;
}

void GraphicsPanelMacosImpl::fullscreenModeChanged(bool fullscreen) {
    NSView* parentView = (NSView*)winId();
    assert(parentView);
    if (!parentView) { return; }

    NSWindow* window = [parentView window];
    assert(window);
    if (!window) { return; }

    /*
    if (fullscreen) {
        [[window standardWindowButton:NSWindowCloseButton] setHidden:NO];
    } else {
        [[window standardWindowButton:NSWindowCloseButton] setHidden:YES];
    }
    */
}

void GraphicsPanelMacosImpl::moveEvent(QMoveEvent* e)
{
    platform_specific::GraphicsPanel::moveEvent(e);
}

void GraphicsPanelMacosImpl::resizeEvent(QResizeEvent* e)
{
    platform_specific::GraphicsPanel::resizeEvent(e);

    const QRect windowRc = rect();
    NSRect frame;
    frame.origin.x    = windowRc.left();
    frame.origin.y    = windowRc.top();
    frame.size.width  = windowRc.width();
    frame.size.height = windowRc.height();

   // _renderView.frame = frame;
}

void GraphicsPanelMacosImpl::_setPanelsAttached(bool attach)
{
    if (!parent())
        return;
    for (unsigned ix = 0; ix < _panels.size(); ix++) {
        assert(_panels[ix]);
        if (!_panels[ix]) { continue; }
        setPanelAttachedAsChild(attach, parentWidget(), _panels[ix].data());
    }
}

void GraphicsPanelMacosImpl::showEvent(QShowEvent* e)
{
    platform_specific::GraphicsPanel::showEvent(e);
    [_renderView setHidden:NO];
    _setPanelsAttached(true);

    if (primaryVideo_)
    {
        // To catch mouse move event. under Mac.
        QCoreApplication::instance()->installEventFilter(this);
    }
}

void GraphicsPanelMacosImpl::hideEvent(QHideEvent* e)
{
    platform_specific::GraphicsPanel::hideEvent(e);
    [_renderView setHidden:YES];
    _setPanelsAttached(false);

    if (primaryVideo_)
        QCoreApplication::instance()->removeEventFilter(this);
}

void GraphicsPanelMacosImpl::mousePressEvent(QMouseEvent * event)
{
    if (!disableMouseEvents_ && primaryVideo_ && event->button() == Qt::LeftButton)
    {
        NSEventType evtType = (event->button() == Qt::LeftButton ? NSLeftMouseDown : NSRightMouseDown);
        NSPoint where;
        where.x = event->pos().x();
        // Cocoa coords is inversted.
        where.y = height() - event->pos().y();

        NSEvent *mouseEvent = [NSEvent mouseEventWithType:evtType
                                                 location:where
                                            modifierFlags:0
                                                timestamp:0
                                             windowNumber:0
                                                  context:0
                                              eventNumber:0
                                               clickCount:1
                                                 pressure:0];
        NSView* htView = [_renderView hitTest:where];
        [htView mouseDown:mouseEvent];
    }
    // To pass event to parent widget.
    event->ignore();
}

void GraphicsPanelMacosImpl::mouseReleaseEvent(QMouseEvent * event)
{
    if (!disableMouseEvents_ && primaryVideo_ && event->button() == Qt::LeftButton)
    {
        NSEventType evtType = (event->button() == Qt::LeftButton ? NSLeftMouseUp : NSRightMouseUp);
        NSPoint where;
        where.x = event->pos().x();
        where.y = height() - event->pos().y();

        NSEvent *mouseEvent = [NSEvent mouseEventWithType:evtType
                                                 location:where
                                            modifierFlags:0
                                                timestamp:0
                                             windowNumber:0
                                                  context:0
                                              eventNumber:0
                                               clickCount:1
                                                 pressure:0];
        NSView* htView = [_renderView hitTest:where];
        [htView mouseUp:mouseEvent];
    }
    event->ignore();
}

void GraphicsPanelMacosImpl::mouseMoveEvent(QMouseEvent* _e)
{
    _mouseMoveEvent (_e);
    _e->ignore();
}

void GraphicsPanelMacosImpl::_mouseMoveEvent(QMouseEvent* _e)
{
    QPoint localPos = mapFromGlobal(QCursor::pos());
    if (!disableMouseEvents_ && primaryVideo_ && mouseMovePoint != localPos)
    {
        mouseMovePoint = localPos;
        NSEventType evtType = NSMouseMoved;
        NSPoint where;
        where.x = _e->pos().x();
        where.y = height() - _e->pos().y();

        if (where.x >= 0 && where.x < width() && where.y >= 0 && where.y < height())
        {
            int nClickCount = (_e->buttons() == Qt::LeftButton) ? 1 : 0;
            NSEvent *mouseEvent = [NSEvent mouseEventWithType:evtType
                                                     location:where
                                                modifierFlags:0
                                                    timestamp:0
                                                 windowNumber:0
                                                      context:0
                                                  eventNumber:0
                                                   clickCount: nClickCount
                                                     pressure:0];
            NSView* htView = [_renderView hitTest:where];
            if (nClickCount == 0)
                [htView mouseMoved:mouseEvent];
            else
                [htView mouseDragged:mouseEvent];
        }
    }
}

void GraphicsPanelMacosImpl::addPanels(std::vector<QPointer<Ui::BaseVideoPanel>>& panels)
{
    _panels = panels;
    _setPanelsAttached(true);
}

void GraphicsPanelMacosImpl::fullscreenAnimationStart()
{
    // Commented, because on 10.13 with this line we have problem with top most video panels.
    //_setPanelsAttached(false);
    moveAboveParentWindow(*(QWidget*)parent(), *this);

    if ([_renderView respondsToSelector:@selector(startFullScreenAnimation)]) {
        [_renderView startFullScreenAnimation];
    }
}

void GraphicsPanelMacosImpl::fullscreenAnimationFinish()
{
    // Commented, because on 10.13 with this line we have problem with top most video panels.
    //_setPanelsAttached(true);

    if ([_renderView respondsToSelector:@selector(finishFullScreenAnimation)]) {
        [_renderView finishFullScreenAnimation];
    }
}

void GraphicsPanelMacosImpl::windowWillDeminiaturize()
{
    // Stop render while deminiaturize animation is running. Fix artifacts.
    if ([_renderView respondsToSelector:@selector(finishFullScreenAnimation)]) {
        [_renderView startFullScreenAnimation];
    }
}

void GraphicsPanelMacosImpl::windowDidDeminiaturize()
{
    // Start render on deminiatureze finished.
    if ([_renderView respondsToSelector:@selector(finishFullScreenAnimation)]) {
        [_renderView finishFullScreenAnimation];
    }
}

void GraphicsPanelMacosImpl::clearPanels()
{
    _setPanelsAttached(false);
    _panels.clear();
}

bool GraphicsPanelMacosImpl::eventFilter(QObject *obj, QEvent *event)
{
    if (event->type() == QEvent::MouseMove)
    {
        QMouseEvent *mouseEvent = static_cast<QMouseEvent*>(event);
        if (mouseEvent->buttons() == Qt::NoButton)
        {
            _mouseMoveEvent(mouseEvent);
        }
    }
    return false;
}

void GraphicsPanelMacosImpl::createdTalk(bool is_vcs)
{
    disableMouseEvents_ = false;
}

void GraphicsPanelMacosImpl::startedTalk()
{
    disableMouseEvents_ = false;
}

void GraphicsPanelMacosImpl::exitTalk()
{
    disableMouseEvents_ = true;
}

}

platform_specific::GraphicsPanel* platform_macos::GraphicsPanelMacos::create(QWidget* parent, std::vector<QPointer<Ui::BaseVideoPanel>>& panels, bool primaryVideo, bool titleBar) {

    IOPMAssertionID assertionID = 0;
    if (CGDisplayIsAsleep(CGMainDisplayID()))
    {
        CFStringRef reasonForActivity = CFSTR("ICQ Call is active");
        IOReturn success = IOPMAssertionDeclareUserActivity(reasonForActivity, kIOPMUserActiveLocal, &assertionID);
        // Give 1s to monitor to turn on.
        QThread::msleep(1000);
    }
    platform_specific::GraphicsPanel* res = new platform_macos::GraphicsPanelMacosImpl(parent, panels, primaryVideo, titleBar);
    if (assertionID)
    {
        IOPMAssertionRelease((IOPMAssertionID)assertionID);
    }
    return res;
}
