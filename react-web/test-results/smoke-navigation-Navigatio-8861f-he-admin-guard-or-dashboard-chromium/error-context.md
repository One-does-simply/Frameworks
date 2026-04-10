# Page snapshot

```yaml
- generic [ref=e2]:
  - generic [ref=e3]:
    - generic [ref=e4]:
      - generic [ref=e5]:
        - generic [ref=e6]: ODS Admin Login
        - generic [ref=e7]:
          - text: Enter the PocketBase superadmin credentials. If this is your first time, create a superadmin at
          - code [ref=e8]: http://127.0.0.1:8090/_/
          - text: using
          - strong [ref=e9]: admin@ods.local
          - text: as the email.
      - generic [ref=e11]:
        - generic [ref=e12]:
          - generic [ref=e13]: Admin Email
          - textbox "Admin Email" [active] [ref=e14]:
            - /placeholder: admin@ods.local
        - generic [ref=e15]:
          - generic [ref=e16]: Admin Password
          - textbox "Admin Password" [ref=e17]:
            - /placeholder: Password
        - button "Connect to PocketBase" [ref=e18]
    - paragraph [ref=e19]: ODS React Web Framework
  - region "Notifications alt+T"
```