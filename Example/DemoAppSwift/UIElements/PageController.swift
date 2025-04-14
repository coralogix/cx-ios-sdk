//
//  PageController.swift
//  DemoAppSwift
//
//  Created by Coralogix Dev Team on 28/07/2024.
//

import UIKit

class PageController: UIViewController, UIScrollViewDelegate {

    var scrollView: UIScrollView!
    var pageControl: UIPageControl!

    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupScrollView()
        setupPageControl()
        setupTabBar()
    }

    func setupScrollView() {
        scrollView = UIScrollView(frame: self.view.bounds)
        scrollView.delegate = self
#if os(iOS)
        scrollView.isPagingEnabled = true
#endif
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.contentSize = CGSize(width: self.view.bounds.width * 3, height: self.view.bounds.height)
        
        for i in 0..<3 {
            let page = UIView(frame: CGRect(x: CGFloat(i) * self.view.bounds.width, y: 0, width: self.view.bounds.width, height: self.view.bounds.height))
            page.backgroundColor = [UIColor.red, UIColor.green, UIColor.blue][i]
            scrollView.addSubview(page)
        }
        
        self.view.addSubview(scrollView)
    }

    func setupPageControl() {
        pageControl = UIPageControl(frame: CGRect(x: 0, y: self.view.bounds.height - 150, width: self.view.bounds.width, height: 50))
        pageControl.numberOfPages = 3
        pageControl.currentPage = 0
        pageControl.pageIndicatorTintColor = UIColor.lightGray
        pageControl.currentPageIndicatorTintColor = UIColor.black
        pageControl.addTarget(self, action: #selector(pageControlChanged(_:)), for: .valueChanged)
        
        self.view.addSubview(pageControl)
    }

    @objc func pageControlChanged(_ sender: UIPageControl) {
        let page: Int = sender.currentPage
        var frame: CGRect = self.scrollView.frame
        frame.origin.x = frame.size.width * CGFloat(page)
        frame.origin.y = 0
        self.scrollView.scrollRectToVisible(frame, animated: true)
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        let pageNumber = round(scrollView.contentOffset.x / scrollView.frame.size.width)
        pageControl.currentPage = Int(pageNumber)
    }

    func setupTabBar() {
        let tabBar = UITabBar()
        tabBar.delegate = self
        tabBar.items = [
            UITabBarItem(title: "Home", image: UIImage(systemName: "house"), tag: 0),
            UITabBarItem(title: "Search", image: UIImage(systemName: "magnifyingglass"), tag: 1),
            UITabBarItem(title: "Profile", image: UIImage(systemName: "person"), tag: 2)
        ]
        tabBar.selectedItem = tabBar.items?[0]
        tabBar.translatesAutoresizingMaskIntoConstraints = false

        self.view.addSubview(tabBar)

        NSLayoutConstraint.activate([
               tabBar.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
               tabBar.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
               tabBar.bottomAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.bottomAnchor)
           ])
    }
}

extension PageController: UITabBarDelegate {
    func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
        switch item.tag {
        case 0:
            print("Home tab selected")
        case 1:
            print("Search tab selected")
        case 2:
            print("Profile tab selected")
        default:
            break
        }
    }
}

