//
//  _PhotoEditorController.swift
//  AnyImageKit
//
//  Created by 蒋惠 on 2019/10/23.
//  Copyright © 2019 AnyImageProject.org. All rights reserved.
//

import UIKit

protocol PhotoEditorControllerDelegate: class {
    
    func photoEditorDidCancel(_ editor: PhotoEditorController)
    func photoEditor(_ editor: PhotoEditorController, didFinishEditing photo: UIImage, isEdited: Bool)
}

final class PhotoEditorController: UIViewController {
    
    weak var delegate: PhotoEditorControllerDelegate?
    
    private lazy var contentView: PhotoEditorContentView = {
        let view = PhotoEditorContentView(frame: self.view.bounds, image: manager.image, config: manager.photoConfig)
        view.delegate = self
        view.canvas.brush.color = manager.photoConfig.penColors[manager.photoConfig.defaultPenIdx]
        return view
    }()
    private lazy var toolView: EditorToolView = {
        let view = EditorToolView(frame: self.view.bounds, config: manager.photoConfig)
        view.delegate = self
        view.penToolView.undoButton.isEnabled = contentView.canvasCanUndo()
        view.mosaicToolView.undoButton.isEnabled = contentView.mosaicCanUndo()
        return view
    }()
    private lazy var backButton: UIButton = {
        let view = UIButton(type: .custom)
        view.contentEdgeInsets = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        view.setImage(BundleHelper.image(named: "ReturnBackButton"), for: .normal)
        view.addTarget(self, action: #selector(backButtonTapped(_:)), for: .touchUpInside)
        return view
    }()
    private lazy var singleTap: UITapGestureRecognizer = {
        return UITapGestureRecognizer(target: self, action: #selector(onSingleTap(_:)))
    }()
    
    private let manager: EditorManager
    
    init(manager: EditorManager) {
        self.manager = manager
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
        navigationController?.navigationBar.isHidden = true
    }
    
    private func setupView() {
        view.addSubview(contentView)
        view.addSubview(toolView)
        view.addSubview(backButton)
        view.addGestureRecognizer(singleTap)
        
        backButton.snp.makeConstraints { (maker) in
            if #available(iOS 11.0, *) {
                maker.top.equalTo(view.safeAreaLayoutGuide).offset(10)
            } else {
                maker.top.equalToSuperview().offset(30)
            }
            maker.left.equalToSuperview().offset(10)
            maker.width.height.equalTo(50)
        }
    }
    
    override var prefersStatusBarHidden: Bool {
        return true
    }
}

// MARK: - Target
extension PhotoEditorController {
    
    /// 返回按钮触发
    @objc private func backButtonTapped(_ sender: UIButton) {
        delegate?.photoEditorDidCancel(self)
    }
    
    /// Tap手势触发，由于ToolView不能响应手势否则会干扰画板的手势，所以要手动完成ToolView的响应链
    @objc private func onSingleTap(_ tap: UITapGestureRecognizer) {
        let point = tap.location(in: toolView)
        let tapped = toolView.responseTouch(point)
        if !tapped && toolView.currentOption != .crop { // 未命中视图时，显示/隐藏所有视图
            let hidden = toolView.alpha == 1
            UIView.animate(withDuration: 0.25) {
                self.toolView.alpha = hidden ? 0 : 1
                self.backButton.alpha = hidden ? 0 : 1
            }
        }
    }
}

// MARK: - PhotoEditorContentViewDelegate
extension PhotoEditorController: PhotoEditorContentViewDelegate {
    
    /// 开始涂鸦
    func photoDidBeginPen() {
        UIView.animate(withDuration: 0.25) {
            self.toolView.alpha = 0
            self.backButton.alpha = 0
        }
    }
    
    /// 结束涂鸦
    func photoDidEndPen() {
        if let option = toolView.currentOption {
            switch option {
            case .pen:
                toolView.penToolView.undoButton.isEnabled = true
            case .mosaic:
                toolView.mosaicToolView.undoButton.isEnabled = true
            default:
                break
            }
        }
        UIView.animate(withDuration: 0.25) {
            self.toolView.alpha = 1
            self.backButton.alpha = 1
        }
    }
    
    /// 马赛克图层创建完成
    func mosaicDidCreated() {
        hideHUD()
        guard let option = toolView.currentOption else { return }
        if option == .mosaic {
            contentView.mosaic?.isUserInteractionEnabled = true
        }
    }
}

// MARK: - EditorToolViewDelegate
extension PhotoEditorController: EditorToolViewDelegate {
    
    /// 点击了功能按钮
    func toolView(_ toolView: EditorToolView, optionDidChange option: ImageEditorController.PhotoEditOption?) {
        contentView.canvas.isUserInteractionEnabled = false
        contentView.mosaic?.isUserInteractionEnabled = false
        contentView.scrollView.isScrollEnabled = option == nil
        guard let option = option else { return }
        switch option {
        case .pen:
            contentView.canvas.isUserInteractionEnabled = true
        case .text:
            break
        case .crop:
            backButton.isHidden = true
            contentView.scrollView.isScrollEnabled = true
            contentView.cropStart()
        case .mosaic:
            if contentView.mosaic == nil {
                showWaitHUD()
            }
            contentView.mosaic?.isUserInteractionEnabled = true
        }
    }
    
    /// 画笔切换颜色
    func toolView(_ toolView: EditorToolView, colorDidChange idx: Int) {
        contentView.canvas.brush.color = manager.photoConfig.penColors[idx]
    }
    
    /// 马赛克切换类型
    func toolView(_ toolView: EditorToolView, mosaicDidChange idx: Int) {
        contentView.setMosaicImage(idx)
    }
    
    /// 撤销 - 仅用于画笔和马赛克
    func toolViewUndoButtonTapped(_ toolView: EditorToolView) {
        guard let option = toolView.currentOption else { return }
        switch option {
        case .pen:
            contentView.canvasUndo()
            toolView.penToolView.undoButton.isEnabled = contentView.canvasCanUndo()
        case .mosaic:
            contentView.mosaicUndo()
            toolView.mosaicToolView.undoButton.isEnabled = contentView.mosaicCanUndo()
        default:
            break
        }
    }
    
    /// 取消裁剪
    func toolViewCropCancelButtonTapped(_ toolView: EditorToolView) {
        backButton.isHidden = false
        contentView.cropCancel()
    }
    
    /// 完成裁剪
    func toolViewCropDoneButtonTapped(_ toolView: EditorToolView) {
        backButton.isHidden = false
        contentView.cropDone()
    }
    
    /// 还原裁剪
    func toolViewCropResetButtonTapped(_ toolView: EditorToolView) {
        contentView.cropReset()
    }
    
    /// 最终完成按钮
    func toolViewDoneButtonTapped(_ toolView: EditorToolView) {
        guard let source = contentView.imageView.screenshot.cgImage else { return }
        let size = CGSize(width: source.width, height: source.height)
        let cropRect = contentView.cropRealRect
        
        // 获取原始imageFrame
        let tmpScale = contentView.scrollView.zoomScale
        let tmpOffset = contentView.scrollView.contentOffset
        contentView.scrollView.zoomScale = 1.0
        let imageFrame = contentView.imageView.frame
        contentView.scrollView.zoomScale = tmpScale
        contentView.scrollView.contentOffset = tmpOffset
        
        var rect: CGRect = .zero
        rect.origin.x = (cropRect.origin.x - imageFrame.origin.x) / imageFrame.width * size.width
        rect.origin.y = (cropRect.origin.y - imageFrame.origin.y) / imageFrame.height * size.height
        rect.size.width = size.width * cropRect.width / imageFrame.width
        rect.size.height = size.height * cropRect.height / imageFrame.height
        
        guard let cgImage = source.cropping(to: rect) else { return }
        let image = UIImage(cgImage: cgImage)
        saveEditPath()
        delegate?.photoEditor(self, didFinishEditing: image, isEdited: contentView.isEdited)
    }
}

extension PhotoEditorController {
    
    /// 存储编辑记录
    private func saveEditPath() {
        let config = manager.photoConfig
        if config.cacheIdentifier.isEmpty { return }
        contentView.setupLastCropDataIfNeeded()
        let cache = EditorImageCache(id: config.cacheIdentifier, cropData: contentView.lastCropData, penCacheList: contentView.penCache.diskCacheList, mosaicCacheList: contentView.mosaicCache.diskCacheList)
        cache.save()
    }
}
