;;; publish.el --- Build the site from content/ into site/  -*- lexical-binding: t; -*-

;;; Commentary:

;; Run by `make build':
;;
;;   emacs --batch -Q --load publish.el --funcall cos-build
;;
;; Every Org file under content/ becomes an HTML page at the same path under
;; site/.  Org exports the body of the page; template.html supplies everything
;; around it.  Every other file under content/ is copied as it is.

;;; Code:

(defconst cos-root (file-name-directory (or load-file-name buffer-file-name))
  "The repository's top directory.")

;; Keep batch Emacs state and temporary files in disposable build storage.
(setq user-emacs-directory (expand-file-name ".cache/emacs/" cos-root)
      auto-save-list-file-prefix (expand-file-name "auto-save/" user-emacs-directory)
      package-gnupghome-dir (expand-file-name "gnupg/" user-emacs-directory)
      project-list-file (expand-file-name "projects" user-emacs-directory)
      temporary-file-directory (expand-file-name ".cache/tmp/" cos-root))
(make-directory temporary-file-directory t)
(require 'ox-publish)
(load (expand-file-name "assets.el" cos-root) nil t)

(defconst cos-content (expand-file-name "content/" cos-root)
  "Where the Org files and the files copied beside them are.")

(defconst cos-output (expand-file-name "site/" cos-root)
  "Where the built site goes.")

(defconst cos-template-file (expand-file-name "template.html" cos-root)
  "The page every Org file's body is placed in.")

(defun cos-attribute (text)
  "Encode TEXT for use in a double-quoted HTML attribute."
  (replace-regexp-in-string "\"" "&quot;" (org-html-encode-plain-text text) t t))

(defun cos-root-prefix (file)
  "Return the relative path from the page built from FILE to the site's top."
  (let ((depth (length (split-string (file-relative-name file cos-content) "/"))))
    (apply #'concat (make-list (1- depth) "../"))))

(defun cos-template (contents info)
  "Return template.html with its placeholders filled in.
CONTENTS is the exported body of the page and INFO the export's
property list.  A placeholder is a name in double braces:

  {{title}}        the page's title as plain text
  {{heading}}      the page's title as an h1, or nothing when the
                   file says #+OPTIONS: title:nil
  {{description}}  the file's #+DESCRIPTION, for an attribute
  {{root}}         the relative path to the top of the site
  {{page}}         the page path, for an attribute
  {{content}}      the body

A link in the template to the page being built gains
aria-current=\"page\", which the stylesheet uses to mark it."
  (let* ((title (plist-get info :title))
         (page (concat (file-name-sans-extension
                        (file-relative-name (plist-get info :input-file)
                                            cos-content))
                       ".html"))
         (values
          `(("title" . ,(org-html-plain-text
                         (org-element-interpret-data title) info))
            ("heading" . ,(if (plist-get info :with-title)
                             (format "<h1>%s</h1>"
                                     (org-export-data title info))
                           ""))
            ("description" . ,(cos-attribute
                               (or (plist-get info :description) "")))
            ("root" . ,(cos-root-prefix (plist-get info :input-file)))
            ("page" . ,(cos-attribute page))
            ("content" . ,(string-trim-right contents)))))
    (with-temp-buffer
      (insert-file-contents cos-template-file)
      (let ((link (format "href=\"{{root}}%s\"" page)))
        (while (search-forward link nil t)
          (insert " aria-current=\"page\"")))
      (replace-regexp-in-string
       "{{\\([a-z]+\\)}}"
       (lambda (match)
         (let ((name (match-string 1 match)))
           (or (cdr (assoc name values))
               (error "template.html uses {{%s}}, which is not a placeholder"
                      name))))
       (buffer-string) t t))))

(org-export-define-derived-backend 'cos-html 'html
  :translate-alist '((template . cos-template))
  :filters-alist '((:filter-parse-tree . cos-assets-links)))

(defun cos-publish-page (plist filename pub-dir)
  "Publish the Org file FILENAME as a page in PUB-DIR.
PLIST is the project's property list."
  ;; Org draws the ids it gives headings from `random'.  Seeding it with the
  ;; file's name gives a page the same ids every time it is built.
  (random (file-relative-name filename cos-content))
  (org-publish-org-to 'cos-html filename ".html" plist pub-dir))

(defun cos-build ()
  "Build the whole site into site/."
  (cos-assets-start)
  (let ((make-backup-files nil)
        (org-publish-timestamp-directory (expand-file-name ".cache/org-publish/" cos-root))
        (org-publish-use-timestamps-flag nil)
        ;; Highlighted source is marked with classes for the stylesheet,
        ;; never with inline style, which the site is served without.
        (org-html-htmlize-output-type 'css)
        (org-publish-project-alist
         `(("pages"
            :base-directory ,cos-content
            :base-extension "org"
            :recursive t
            :publishing-directory ,cos-output
            :publishing-function cos-publish-page
            :html-doctype "html5"
            :html-html5-fancy t
            :section-numbers nil
            :with-toc nil
            :with-sub-superscript {})
           ("files"
            :base-directory ,cos-content
            :base-extension any
            :exclude "\\(\\.org\\|~\\)\\'"
            :recursive t
            :publishing-directory ,cos-output
            :publishing-function org-publish-attachment))))
    (org-publish-all t)))

;;; publish.el ends here
