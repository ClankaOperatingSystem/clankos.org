;;; assets-test.el --- Exercise archive image builds -*- lexical-binding: t; -*-

(load (expand-file-name "../publish.el" (file-name-directory load-file-name)) nil t)
(require 'ert)
(require 'cl-lib)

(defconst cos-test-uri
  "ipfs://bafybeibq2pwbwv2aakhpssihkcg3ejxver4agjhksismpcphpzn5ipxlf4/test.png")

(defmacro cos-test-with-assets (&rest body)
  "Run BODY with isolated build storage and a small generated test image."
  (declare (indent 0) (debug t))
  `(let* ((cos-root (make-temp-file (expand-file-name ".cache/test-" cos-root) t))
          (cos-content (expand-file-name "content/" cos-root))
          (cos-output (expand-file-name "site/" cos-root))
          (cos-assets-lock (make-hash-table :test 'equal))
          (cos-assets-rendered (make-hash-table :test 'equal))
          (process-environment (copy-sequence process-environment))
          (source (expand-file-name "source.png" cos-root)))
     (unwind-protect
         (progn
           (setenv "COS_ASSET_CACHE" nil)
           (setenv "IPFS_OFFLINE" nil)
           (should (= 0 (call-process "magick" nil nil nil "-size" "8x8" "xc:red" source)))
           (let ((entry (make-hash-table :test 'equal)))
             (puthash "sha256" (cos-assets-sha256 source) entry)
             (puthash cos-test-uri entry cos-assets-lock))
           ,@body)
       (delete-directory cos-root t))))

(ert-deftest cos-assets-rejects-unsafe-and-unlisted-addresses ()
  (cos-test-with-assets
    (dolist (uri '("ipfs://bad/../secret.png" "ipfs://bad/a.png?x=1"
                   "https://example.org/a.png" "ipfs://bad/a.svg"))
      (should-error (cos-assets-name uri)))
    (should-error (cos-assets-original
                   (replace-regexp-in-string "test.png" "other.png" cos-test-uri)))))

(ert-deftest cos-assets-verifies-download-and-reuses-offline-cache ()
  (cos-test-with-assets
    (let ((calls 0))
      (cl-letf (((symbol-function 'cos-assets-download)
                 (lambda (_uri output) (cl-incf calls) (copy-file source output t))))
        (let ((first (cos-assets-original cos-test-uri)))
          (setenv "IPFS_OFFLINE" "1")
          (should (equal first (cos-assets-original cos-test-uri)))
          (should (= calls 1))
          (should (equal (cos-assets-sha256 first) (cos-assets-sha256 source))))))))

(ert-deftest cos-assets-refuses-corrupt-download ()
  (cos-test-with-assets
    (cl-letf (((symbol-function 'cos-assets-download)
               (lambda (_uri output) (with-temp-file output (insert "wrong bytes")))))
      (should-error (cos-assets-original cos-test-uri))
      (should-not (directory-files (expand-file-name ".cache/ipfs/" cos-root)
                                   nil "^[^.].*")))))

(ert-deftest cos-assets-http-body-preserves-exact-image-bytes ()
  (cos-test-with-assets
    (cl-letf (((symbol-function 'url-retrieve-synchronously)
               (lambda (&rest _)
                 (let ((response (generate-new-buffer " *image-response*")))
                   (with-current-buffer response
                     (set-buffer-multibyte nil)
                     (insert "HTTP/1.1 200 OK\nContent-Type: image/png\n\n")
                     (setq-local url-http-response-status 200
                                 url-http-end-of-headers (copy-marker (1- (point))))
                     (insert-file-contents-literally source))
                   response))))
      (let ((destination (expand-file-name "download.png" cos-root)))
        (cos-assets-download cos-test-uri destination)
        (should (equal (cos-assets-sha256 source)
                       (cos-assets-sha256 destination)))))))

(ert-deftest cos-assets-refuses-corrupt-cache ()
  (cos-test-with-assets
    (cl-letf (((symbol-function 'cos-assets-download)
               (lambda (_uri output) (copy-file source output t))))
      (let ((cached (cos-assets-original cos-test-uri)))
        (with-temp-file cached (insert "changed"))
        (should-error (cos-assets-original cos-test-uri))))))

(ert-deftest cos-assets-offline-cache-miss-does-not-fetch ()
  (cos-test-with-assets
    (setenv "IPFS_OFFLINE" "1")
    (cl-letf (((symbol-function 'cos-assets-download)
               (lambda (&rest _) (ert-fail "Offline build attempted a download"))))
      (should-error (cos-assets-original cos-test-uri)))))

(ert-deftest cos-assets-exports-image-attributes-and-nested-relative-paths ()
  (cos-test-with-assets
    (cl-letf (((symbol-function 'cos-assets-download)
               (lambda (_uri output) (copy-file source output t))))
      (let* ((input (concat "#+ATTR_HTML: :alt A red square :loading lazy\n[["
                            cos-test-uri "]]\n\n[[https://example.org][Example]]\n"))
             (html (org-export-string-as input 'cos-html t
                    (list :input-file (expand-file-name "guide/start.org" cos-content)))))
        (should (string-match-p "<img src=\"../img/test-[a-f0-9]+.webp\"" html))
        (should (string-match-p "alt=\"A red square\"" html))
        (should (string-match-p "loading=\"lazy\"" html))
        (should (string-match-p "href=\"https://example.org\"" html))
        (should-not (string-match-p "ipfs://" html))
        (should (string-match-p "ipfs://" input))
        (should (= 1 (hash-table-count cos-assets-rendered)))))))

(ert-deftest cos-assets-reuses-derivatives-and-keeps-originals-unchanged ()
  (cos-test-with-assets
    (cl-letf (((symbol-function 'cos-assets-download)
               (lambda (_uri output) (copy-file source output t))))
      (let* ((before (cos-assets-sha256 source))
             (first (cos-assets-render cos-test-uri)))
        (should (equal first (cos-assets-render cos-test-uri)))
        (should (file-exists-p (expand-file-name first cos-output)))
        (should (equal before (cos-assets-sha256 source)))
        (should (= 1 (length (directory-files (expand-file-name "img/" cos-output)
                                             nil "\\.webp$"))))))))

(ert-deftest cos-assets-renders-publicly-readable-images ()
  (cos-test-with-assets
    (set-file-modes source #o600)
    (cl-letf (((symbol-function 'cos-assets-download)
               (lambda (_uri output) (copy-file source output t))))
      (let ((cached (cos-assets-original cos-test-uri)))
        (set-file-modes cached #o600)
        (let* ((relative (cos-assets-render cos-test-uri))
               (rendered (expand-file-name relative cos-output)))
          (should (= #o644 (file-modes rendered)))
          ;; Replacing output from an older build must repair its mode too.
          (set-file-modes rendered #o600)
          (clrhash cos-assets-rendered)
          (should (equal relative (cos-assets-render cos-test-uri)))
          (should (= #o644 (file-modes rendered)))
          (should (= #o600 (file-modes source)))
          (should (= #o600 (file-modes cached))))))))

;;; assets-test.el ends here
