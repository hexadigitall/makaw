# Storage & Drive Policy

- **Target Disk:** All project operations, intermediate files, and temporary outputs must reside on `D:\`.
- **System Drive Protection:** Drive `C:\` has less than 5 GB of free space. Do not write build outputs, caches, or downloads to `C:\`.
- **Environment Variables:**
  - `PUB_CACHE=D:\develop\pub_cache`
  - `GRADLE_USER_HOME=D:\develop\.gradle`
- **Execution Rule:** Avoid unrestricted recursive directory indexing on root directories. Always respect exclusions.
