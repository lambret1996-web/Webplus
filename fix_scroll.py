with open("WebViewBrowser/ViewController.swift", "r") as f:
    content = f.read()

old = '''    private func scrollToFindIndex() {
        let js = """
        (function() {
            var all = document.querySelectorAll('.__browser_find_highlight__');
            all.forEach(function(el) { el.style.backgroundColor = '#ffeb3b'; });
            var target = document.querySelector('.__browser_find_highlight__[data-find-index="\\(currentFindIndex)"]');
            if (target) {
                target.style.backgroundColor = '#ff9800';
                target.scrollIntoView({behavior: 'smooth', block: 'center'});
            }
            return '\\(currentFindIndex+1)';
        })();
        """
        currentWebView.evaluateJavaScript(js) { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.findCountLabel?.text = "\\((self?.currentFindIndex ?? 0)+1)/\\(self?.totalFindCount ?? 0)"
            }
        }
    }'''

new = '''    private func scrollToFindIndex() {
        let idx = currentFindIndex
        let js = """
        (function() {
            var all = document.querySelectorAll('.__browser_find_highlight__');
            all.forEach(function(el) { el.style.backgroundColor = '#ffeb3b'; });
            var target = document.querySelector('.__browser_find_highlight__[data-find-index="\\(idx)"]');
            if (!target) return 'notfound';
            target.style.backgroundColor = '#ff9800';
            var rect = target.getBoundingClientRect();
            var scrollY = window.pageYOffset || document.documentElement.scrollTop;
            var targetY = scrollY + rect.top - window.innerHeight / 2 + rect.height / 2;
            window.scrollTo({top: Math.max(0, targetY), behavior: 'smooth'});
            return 'ok';
        })();
        """
        currentWebView.evaluateJavaScript(js) { [weak self] result, error in
            DispatchQueue.main.async {
                self?.findCountLabel?.text = "\\((self?.currentFindIndex ?? 0)+1)/\\(self?.totalFindCount ?? 0)"
            }
        }
    }'''

if old in content:
    content = content.replace(old, new, 1)
    with open("WebViewBrowser/ViewController.swift", "w") as f:
        f.write(content)
    print("滚动函数修复完成")
else:
    print("未找到旧代码，尝试查找...")
    import re
    match = re.search(r'private func scrollToFindIndex\(\).*?\n    \}', content, re.DOTALL)
    if match:
        print("找到函数，内容如下:")
        print(match.group(0)[:500])
    else:
        print("完全没找到")
