;;; assets.el --- Fetch archived images for the site -*- lexical-binding: t; -*-

(require 'json)
(require 'url)
(require 'url-http)
(require 'org-element)

(defvar cos-assets-lock nil "IPFS addresses and expected SHA-256 hashes.")
(defvar cos-assets-rendered nil "Images already rendered during this build.")

(defun cos-assets-start ()
  "Read the image lock file and start a fresh build."
  (setq cos-assets-lock
        (with-temp-buffer
          (insert-file-contents (expand-file-name "image-lock.json" cos-root))
          (json-parse-buffer :object-type 'hash-table))
        cos-assets-rendered (make-hash-table :test 'equal)))

(defun cos-assets-sha256 (file)
  "Return the SHA-256 of FILE's literal bytes."
  (with-temp-buffer
    (set-buffer-multibyte nil)
    (insert-file-contents-literally file)
    (secure-hash 'sha256 (current-buffer))))

(defun cos-assets-name (uri)
  "Return URI's image filename, refusing paths outside a named bundle."
  (unless (string-match
           "\\`ipfs://b[a-z2-7]+/\\([A-Za-z0-9][A-Za-z0-9._-]*\\.\\(?:png\\|jpg\\|jpeg\\|webp\\)\\)\\'"
           uri)
    (error "Expected ipfs://CID/image.png (or jpg, jpeg, webp): %s" uri))
  (match-string 1 uri))

(defun cos-assets-download (uri destination)
  "Fetch URI through the configured gateway into DESTINATION."
  (let* ((gateway (string-remove-suffix
                   "/" (or (getenv "IPFS_GATEWAY") "https://ipfs.io")))
         (url (concat gateway "/ipfs/" (substring uri (length "ipfs://"))))
         (url-request-extra-headers '(("Accept-Encoding" . "identity")))
         (buffer (url-retrieve-synchronously url t t 30)))
    (unless buffer (error "Could not fetch %s through %s" uri gateway))
    (unwind-protect
        (with-current-buffer buffer
          (unless (equal url-http-response-status 200)
            (error "Gateway returned HTTP %s for %s"
                   url-http-response-status uri))
          (unless url-http-end-of-headers
            (error "Gateway returned no HTTP body for %s" uri))
          ;; url.el's marker precedes the final header newline.
          (goto-char url-http-end-of-headers)
          (forward-line 1)
          (let ((coding-system-for-write 'binary))
            (write-region (point) (point-max)
                          destination nil 'silent)))
      (kill-buffer buffer))))

(defun cos-assets-original (uri)
  "Return a verified cached original for URI, fetching it if necessary.
The reviewed lock file binds the complete URI to a hash of the original
bytes. A gateway response is never trusted merely because its URL has a CID."
  (let* ((name (cos-assets-name uri))
         (entry (and cos-assets-lock (gethash uri cos-assets-lock)))
         (sha (and entry (gethash "sha256" entry)))
         (cache (file-name-as-directory
                 (expand-file-name (or (getenv "COS_ASSET_CACHE")
                                       ".cache/ipfs") cos-root))))
    (unless (and (stringp sha) (string-match-p "\\`[a-f0-9]\\{64\\}\\'" sha))
      (error "No valid image-lock.json entry for %s" uri))
    (make-directory cache t)
    (let ((file (expand-file-name (concat sha "." (file-name-extension name)) cache)))
      (when (and (file-exists-p file)
                 (not (equal sha (cos-assets-sha256 file))))
        (error "Cached image hash mismatch for %s; remove %s and retry" uri file))
      (unless (file-exists-p file)
        (when (equal (getenv "IPFS_OFFLINE") "1")
          (error "Image is not cached in offline mode: %s" uri))
        (let ((temporary (make-temp-file (expand-file-name ".fetch-" cache))))
          (unwind-protect
              (progn
                (cos-assets-download uri temporary)
                (unless (equal sha (cos-assets-sha256 temporary))
                  (error "Downloaded image hash mismatch for %s" uri))
                (rename-file temporary file t))
            (when (file-exists-p temporary) (delete-file temporary)))))
      file)))

(defun cos-assets-render (uri)
  "Return URI's generated path relative to the site root.
Originals are cached; WebP derivatives belong only to the built site."
  (or (gethash uri cos-assets-rendered)
      (let* ((source (cos-assets-original uri))
             (name (file-name-base (cos-assets-name uri)))
             (directory (expand-file-name "img/" cos-output))
             (magick (or (executable-find "magick")
                         (error "ImageMagick 7 (magick) is required for images"))))
        (make-directory directory t)
        (let ((temporary (make-temp-file (expand-file-name ".render-" directory)
                                         nil ".webp")))
          (unwind-protect
              (progn
                (with-temp-buffer
                  (let ((status (call-process magick nil t nil source
                                              "-auto-orient" "-resize" "1280x>"
                                              "-strip" "-quality" "82" temporary)))
                    (unless (equal status 0)
                      (error "Image conversion failed for %s: %s" uri (buffer-string)))))
                (let* ((hash (substring (cos-assets-sha256 temporary) 0 16))
                       (relative (concat "img/" name "-" hash ".webp"))
                       (target (expand-file-name relative cos-output)))
                  (when (and (file-exists-p target)
                             (not (equal (cos-assets-sha256 target)
                                         (cos-assets-sha256 temporary))))
                    (error "Generated image filename collision: %s" relative))
                  ;; Temporary files start private; nginx must read the output.
                  (set-file-modes temporary #o644)
                  (rename-file temporary target t)
                  (puthash uri relative cos-assets-rendered)
                  relative))
            (when (file-exists-p temporary) (delete-file temporary)))))))

(defun cos-assets-links (tree _backend info)
  "Resolve IPFS image links in the export TREE without changing source Org."
  (org-element-map tree 'link
    (lambda (link)
      (when (equal (org-element-property :type link) "ipfs")
        (let* ((uri (org-element-property :raw-link link))
               (path (concat (cos-root-prefix (plist-get info :input-file))
                             (cos-assets-render uri))))
          (org-element-put-property link :type "file")
          (org-element-put-property link :path path)
          (org-element-put-property link :raw-link (concat "file:" path))))))
  tree)

;; Register the scheme so Org parses it as a link before the export filter.
(org-link-set-parameters "ipfs")

(provide 'cos-assets)
;;; assets.el ends here
