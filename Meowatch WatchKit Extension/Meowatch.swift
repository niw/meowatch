//
//  Meowatch.swift
//  Meowatch
//
//  Created by Yoshimasa Niwa on 5/8/15.
//  Copyright (c) 2015 Yoshimasa Niwa. All rights reserved.
//

import Accounts
import ImageIO
import Twitter
import UIKit
import WatchKit

extension UIImage {
    class func animatedImageWithData(data: NSData) -> UIImage? {
        let source = CGImageSourceCreateWithData(data, nil)
        let count = CGImageSourceGetCount(source);

        if count <= 1 {
            return UIImage(data: data)
        } else {
            var images: [UIImage] = []
            var duration = 0.0

            for index in 0..<count {
                let cgImage = CGImageSourceCreateImageAtIndex(source, index, nil)
                let frameProperties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as NSDictionary
                if let gifProperties = frameProperties[kCGImagePropertyGIFDictionary as NSString] as? NSDictionary {
                    if let unclampedDelayTime = gifProperties[kCGImagePropertyGIFUnclampedDelayTime as NSString] as? NSNumber {
                        duration += unclampedDelayTime.doubleValue
                    } else if let delayTime = gifProperties[kCGImagePropertyGIFDelayTime as NSString] as? NSNumber {
                        duration += delayTime.doubleValue
                    }
                }

                if let image = UIImage(CGImage: cgImage, scale: WKInterfaceDevice.currentDevice().screenScale, orientation: UIImageOrientation.Up) {
                    images.append(image)
                }
            }
            return UIImage.animatedImageWithImages(images, duration: duration);
        }
    }

    func optimizedAnimatedImage(fitSize: CGSize, maxFrame: Int) -> UIImage? {
        if let images = self.images as? [UIImage] {
            if CGSizeEqualToSize(self.size, fitSize) || CGSizeEqualToSize(fitSize, CGSizeZero) {
                return self;
            }

            let widthFactor = fitSize.width / self.size.width
            let heightFactor = fitSize.height / self.size.height
            let scaleFactor = min(widthFactor, heightFactor)

            let scaledSize = CGSizeMake(self.size.width * scaleFactor, self.size.height * scaleFactor)

            let increment: Int
            if (maxFrame > 0) {
                increment = images.count / maxFrame
            } else {
                increment = 0
            }

            var scaledImages: [UIImage] = []

            UIGraphicsBeginImageContextWithOptions(scaledSize, false, WKInterfaceDevice.currentDevice().screenScale)
            for var index = 0; index < images.count; index += increment {
                let image = images[index]
                image.drawInRect(CGRectMake(0.0, 0.0, scaledSize.width, scaledSize.height))
                let newImage = UIGraphicsGetImageFromCurrentImageContext()
                let data = UIImageJPEGRepresentation(newImage, 0.5)
                let jpegImage = UIImage(data: data)!
                scaledImages.append(jpegImage)
            }
            UIGraphicsEndImageContext();

            return UIImage.animatedImageWithImages(scaledImages, duration:self.duration);
        } else {
            return self;
        }
    }
}

struct ArchivedAnimatedImage {
    let data: NSData
    let count: Int
    let duration: NSTimeInterval

    init(image: UIImage) {
        self.data = NSKeyedArchiver.archivedDataWithRootObject(image)
        if let count = image.images?.count {
            self.count = count
        } else {
            self.count = 1
        }
        self.duration = image.duration
    }
}

struct AnimatedImageFetchResult {
    let originalData: NSData
    let archivedAniamtedImage: ArchivedAnimatedImage

    // Bluetooth 4.0 LE's data rate is, by measureing in stable environment,
    // about 420 Kbps and could be worser.
    private let bytesPerSeconds = 840 * 1024 / 8;

    func estimatedLoadingTime() -> Double {
        return Double(self.archivedAniamtedImage.data.length) / Double(self.bytesPerSeconds);
    }

    func formattedLodingSize() -> String {
        let kiloBytes = self.archivedAniamtedImage.data.length / 1024;
        let formatter = NSNumberFormatter()
        formatter.numberStyle = NSNumberFormatterStyle.DecimalStyle
        if let formattedString = formatter.stringFromNumber(NSNumber(integer: kiloBytes)) {
            return formattedString
        } else {
            return "\(kiloBytes)"
        }
    }
}

func fetchAnimatedImage(completion: (AnimatedImageFetchResult?) -> Void) {
    // FIXME: Find a feasible way to get cats from the internet.
    let theCatApiEndpoint = "http://thecatapi.com/api/images/get?format=src&type=gif"

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), {
        if let url = NSURL(string: theCatApiEndpoint),
            data = NSData(contentsOfURL: url),
            image = UIImage.animatedImageWithData(data)?.optimizedAnimatedImage(CGSizeMake(120.0, 120.0), maxFrame: 6) {
            let archivedAnimatedImage = ArchivedAnimatedImage(image: image)
            let fetchResult = AnimatedImageFetchResult(originalData: data, archivedAniamtedImage: archivedAnimatedImage)
            dispatch_async(dispatch_get_main_queue(), {
                completion(fetchResult)
            })
        } else {
            dispatch_async(dispatch_get_main_queue(), {
                completion(nil)
            })
        }
    })
}

struct ProgressBarHelper {
    private let numberOfFrames = 40
    private let cachedImageName = "ProgressBar"

    weak var progressBarImage: WKInterfaceImage? {
        didSet {
            self.progressBarImage?.setImageNamed(self.cachedImageName)
            self.progressBarImage?.stopAnimating()
        }
    }

    init() {
        if let image = progressBarAnimatedImage(self.numberOfFrames) {
            WKInterfaceDevice.currentDevice().addCachedImage(image, name: self.cachedImageName)
        }
    }

    // See https://developer.apple.com/watch/human-interface-guidelines/specifications/
    private let progressBarColor = UIColor(red: 255.0/255.0, green: 230.0/255.0, blue: 32.0/255.0, alpha: 1.0)

    private func progressBarImageAtProgress(progress: Double) -> UIImage? {
        let progress = min(1.0, max(0.0, progress))
        let barSize = CGSizeMake(WKInterfaceDevice.currentDevice().screenBounds.width - 12.0, 2.0)

        UIGraphicsBeginImageContextWithOptions(barSize, false, WKInterfaceDevice.currentDevice().screenScale)
        let context = UIGraphicsGetCurrentContext()
        self.progressBarColor.setFill()
        UIBezierPath(roundedRect: CGRectMake(0.0, 0.0, ceil(barSize.width * CGFloat(progress)), barSize.height), cornerRadius: 1.0).fill()
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext();

        return image
    }

    private func progressBarAnimatedImage(numberOfFrames: Int) -> UIImage? {
        var images: [UIImage] = []
        for index in 0..<numberOfFrames {
            if let image = progressBarImageAtProgress(Double(index) / Double(numberOfFrames - 1)) {
                images.append(image)
            } else {
                return nil
            }
        }
        return UIImage.animatedImageWithImages(images, duration: 10.0)
    }

    func reset() {
        self.progressBarImage?.startAnimatingWithImagesInRange(NSMakeRange(0, 1), duration: 0.0, repeatCount: 1)
    }

    func startInDuration(duration: NSTimeInterval) {
        self.progressBarImage?.startAnimatingWithImagesInRange(NSMakeRange(0, self.numberOfFrames), duration: duration, repeatCount: 1)
    }
}

class RequestTag {
}

struct SocialAccount {
    let type: String

    private func serviceType() -> String? {
        switch self.type {
        case ACAccountTypeIdentifierTwitter:
            return SLServiceTypeTwitter
        case ACAccountTypeIdentifierFacebook:
            return SLServiceTypeFacebook
        case ACAccountTypeIdentifierSinaWeibo:
            return SLServiceTypeSinaWeibo
        case ACAccountTypeIdentifierTencentWeibo:
            return SLServiceTypeTencentWeibo
        default:
            return nil
        }
    }

    func check(completion: ([ACAccount]?) -> Void) {
        if let serviceType = self.serviceType() {
            if SLComposeViewController.isAvailableForServiceType(SLServiceTypeTwitter) {
                let accountStore = ACAccountStore();
                if let accountType = accountStore.accountTypeWithAccountTypeIdentifier(self.type),
                    accounts = accountStore.accountsWithAccountType(accountType) as? [ACAccount]
                {
                    if (accounts.count == 0) {
                        // Not Authorized.
                        completion(nil)
                    } else {
                        // Authorized.
                        completion(accounts)
                    }
                } else {
                    completion([])
                }
            } else {
                // No accounts.
                completion([])
            }
        }
    }

    func request(completion: ([ACAccount]?) -> Void) {
        let accountStore = ACAccountStore();
        if let accountType = accountStore.accountTypeWithAccountTypeIdentifier(ACAccountTypeIdentifierTwitter) {
            accountStore.requestAccessToAccountsWithType(accountType, options: nil, completion: { (granted, error) in
                if granted {
                    if let accounts = accountStore.accountsWithAccountType(accountType) as? [ACAccount] {
                        completion(accounts)
                    } else {
                        completion([])
                    }
                } else {
                    completion(nil)
                }
            })
        }
    }
}

class AnimatedImageFetchInterfaceController: WKInterfaceController {
    @IBOutlet weak var loadingGroup: WKInterfaceGroup?
    @IBOutlet weak var loadingLabel: WKInterfaceLabel?
    @IBOutlet weak var contentImage: WKInterfaceImage?

    private var progressBarHelper = ProgressBarHelper()
    @IBOutlet weak var progressBarImage: WKInterfaceImage? {
        get {
            return self.progressBarHelper.progressBarImage
        }
        set {
            self.progressBarHelper.progressBarImage = newValue
        }
    }

    private var currenrRequestTag: RequestTag?
    private var lastFetchResult: AnimatedImageFetchResult?

    func fetch() {
        self.loadingGroup?.setHidden(false)
        self.contentImage?.setHidden(true)

        self.progressBarHelper.reset()
        self.loadingLabel?.setText("Loading...")
        self.clearAllMenuItems()

        let requestTag = RequestTag()
        self.currenrRequestTag = requestTag

        fetchAnimatedImage { [weak self] fetchResultOpt in
            if let strongSelf = self {
                if let currentRequstTag = strongSelf.currenrRequestTag, fetchResult = fetchResultOpt {
                    if currentRequstTag === requestTag {
                        strongSelf.loadingLabel?.setText("\(fetchResult.formattedLodingSize()) KB in \(Int(fetchResult.estimatedLoadingTime())) s")
                        strongSelf.progressBarHelper.startInDuration(fetchResult.estimatedLoadingTime())

                        dispatch_async(dispatch_get_main_queue(), { [weak self] in
                            if let strongSelf = self, currentRequstTag = strongSelf.currenrRequestTag {
                                if (currentRequstTag === requestTag) {
                                    strongSelf.lastFetchResult = fetchResult;

                                    strongSelf.loadingGroup?.setHidden(true)
                                    strongSelf.contentImage?.setHidden(false)

                                    strongSelf.contentImage?.setImageData(fetchResult.archivedAniamtedImage.data)
                                    strongSelf.contentImage?.startAnimatingWithImagesInRange(NSMakeRange(0, fetchResult.archivedAniamtedImage.count), duration: fetchResult.archivedAniamtedImage.duration, repeatCount: 0)

                                    strongSelf.addMenuItemWithItemIcon(WKMenuItemIcon.Share, title: "Share", action: "didTapShare:");
                                }
                            }
                        })
                    }
                } else {
                    strongSelf.loadingLabel?.setText("Failed.")
                }
            }
        }
    }

    private func requestTwitterAccount(completion: (ACAccount) -> Void) {
        // FIXME: support account selection
        let socialAccount = SocialAccount(type: ACAccountTypeIdentifierTwitter)
        socialAccount.check { (accountsOpt) -> Void in
            if let accounts = accountsOpt {
                if let account = accounts.first {
                    completion(account)
                } else {
                    self.presentControllerWithName("ModalAlert", context: ModalAlertInterfaceController.Context(text: "No Twitter accounts."))
                }
            } else {
                self.presentControllerWithName("ModalAlert", context: ModalAlertInterfaceController.Context(text: "Meowatch needs access to your Twitter accounts. Tap Authorize to request access on the iPhone screen.", buttonTitle: "Authorize", didTapButton: { [weak self] in
                    self?.dismissController()
                    socialAccount.request({ (accounts) -> Void in
                        if let account = accounts?.first {
                            completion(account)
                        }
                    })
                }))
            }
        }
    }

    private func share() {
        let uploadWithMediaAPIEndpoint = "https://upload.twitter.com/1/statuses/update_with_media.json"
        let status = "🐱 #Meowatch"

        if let lastFetchResult = self.lastFetchResult {
            requestTwitterAccount({ (account) in
                let url = NSURL(string: uploadWithMediaAPIEndpoint)
                let parameters = ["status": status]
                let request = SLRequest(forServiceType: SLServiceTypeTwitter, requestMethod: SLRequestMethod.POST, URL: url, parameters: parameters)
                request.account = account
                request.addMultipartData(lastFetchResult.originalData, withName: "media", type: "image/gif", filename: "cat.gif")
                request.performRequestWithHandler({ (data, response, error) in
                })
            })
        }
    }

    @IBAction func didTapShare(sender: AnyObject) {
        share();
    }
}

class MainInterfaceController: AnimatedImageFetchInterfaceController {
    override func awakeWithContext(context: AnyObject?) {
        super.awakeWithContext(context)
        fetch()
    }

    @IBAction func shuffle() {
        fetch();
    }
}

class ModalAlertInterfaceController: WKInterfaceController {
    class Context {
        let attributedText: NSAttributedString?
        let text: String?
        let buttonTitle: String?
        let didTapButton: (() -> Void)?

        init(text: String) {
            self.attributedText = nil
            self.text = text
            self.buttonTitle = nil
            self.didTapButton = nil
        }

        init(text: String, buttonTitle: String, didTapButton: () -> Void) {
            self.attributedText = nil
            self.text = text
            self.buttonTitle = buttonTitle
            self.didTapButton = didTapButton
        }

        init(attributedText: NSAttributedString?, buttonTitle: String, didTapButton: () -> Void) {
            self.attributedText = attributedText
            self.text = nil
            self.buttonTitle = buttonTitle
            self.didTapButton = didTapButton
        }
    }

    @IBOutlet weak var label: WKInterfaceLabel?
    @IBOutlet weak var button: WKInterfaceButton?

    private var context: Context?

    override func awakeWithContext(context: AnyObject?) {
        super.awakeWithContext(context)

        if let modalAlertContext = context as? Context {
            self.context = modalAlertContext

            if let attributedText = modalAlertContext.attributedText {
                label?.setAttributedText(attributedText)
            } else if let text = modalAlertContext.text {
                label?.setText(text)
            }
            if let buttonTitle = modalAlertContext.buttonTitle {
                button?.setTitle(buttonTitle)
            } else {
                button?.setHidden(true)
            }
        }
    }

    @IBAction func didTapButton(sender: AnyObject?) {
        self.context?.didTapButton?()
    }
}
