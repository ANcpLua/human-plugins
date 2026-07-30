# repo-hygiene

Finds generated build output that has been committed to Git. It reads each
repository index with `git ls-files`; it does not scan file contents or mutate
repositories.

```bash
repo-hygiene ~/src
repo-hygiene --quiet .
repo-hygiene --verbose --color never ~
```

Exit `0` means clean, `1` means findings, and `2` means invalid input or an
unreadable repository.
