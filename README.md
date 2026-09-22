# mssqlsuite
This GitHub Action automatically installs a SQL Server suite of tools including sqlcmd, bcp, sqlpackage, the sql engine, localdb and more for Windows, macOS and Linux.

> **Note:** `sqlcmd` is always installed by default because this action needs it to execute some SQL.

## Documentation

Add this step to a workflow and adjust `install` for the tools you need. For a Linux runner, this step installs SQL Server 2022, the default version:

```yaml
    - name: Install a SQL Server suite of tools
      uses: potatoqualitee/mssqlsuite@v2
      with:
        install: sqlengine, sqlpackage
```

## Usage

### Prerequisites

Create a workflow `.yml` file in your repository's `.github/workflows` directory. [Example workflows](#example-workflows) are available below. For more information, see GitHub's [workflow documentation](https://docs.github.com/en/actions/get-started/quickstart).

### Inputs

* `install` - The tools to install: `sqlengine`, `sqlclient`, `sqlpackage`, `localdb`, `fulltext`, and `ssis`. `localdb` and `ssis` are Windows-only.
* `sa-password` - The sa password for the SQL instance. The default is `dbatools.I0`
* `admin-username` - The admin username for the SQL instance. The default is `sa`. When specified, the built-in `sa` user will be renamed to this username
* `collation` - Change the collation associated with the SQL Server instance
* `version` - The SQL Server version in year format. Defaults to `2022`; set `version: 2025` to install SQL Server 2025. Windows supports 2016, 2017, 2019, 2022, and 2025. Linux and macOS support 2019, 2022, and 2025.
* `show-log` - Show logs, including docker logs, for troubleshooting
* `edition` - SQL Server edition to install. Defaults to `Developer`. Linux and macOS containers accept `Developer`, `Evaluation`, `Express`, `Web`, `Standard`, `Enterprise`, `EnterpriseCore`, and (with SQL Server 2025) `StandardDeveloper`. Windows uses Developer media by default; paid editions require `product-key`. Evaluation, Express, and StandardDeveloper are not supported by the current Windows media.
* `product-key` - Product key for a paid Windows edition. Supply it from a GitHub Actions secret. It is passed to SQL Server setup as `/PID`.
* `disable-telemetry` - Set to `true` to request CEIP telemetry opt-out. Defaults to `false`. Developer, Express, and StandardDeveloper editions do not permit opt-out and will be rejected. On Windows, the CEIP service remains installed and running; the action sets the supported CustomerFeedback opt-out registry value.

For example, to run a Standard edition container without CEIP telemetry:

```yaml
- uses: potatoqualitee/mssqlsuite@v2
  with:
    install: sqlengine
    edition: Standard
    disable-telemetry: true
```

For a paid Windows installation, set `edition: Standard` and `product-key: ${{ secrets.SQL_SERVER_PRODUCT_KEY }}`. The key must match the selected edition and version. The runner must have a license for that edition.

### Outputs

None

**Notes:**
- `ssis` is only supported on Windows runners. It also installs `sqlengine` and ensures the SSISDB catalog exists.
- With `version: 2025`, the Windows `localdb` option installs SQL Server 2022 LocalDB because this action does not yet provide a 2025 LocalDB installer.
- macOS runner tests are currently disabled because of Homebrew timeouts during Docker/Colima installation. macOS support is therefore unverified in CI.

### Details

| Application | Keyword | OS | Details |
| --- | --- | --- | --- |
| SQL Engine | `sqlengine` | Linux | Docker container for the selected version, accessible at `localhost` |
| SQL Engine | `sqlengine` | Windows | Local SQL Server installation for the selected version, accessible at `localhost`; Windows and SQL authentication are supported |
| SQL Engine | `sqlengine` | macOS | Docker container for the selected version, accessible at `localhost` |
| Client Tools | `sqlclient` | Linux, macOS | Installs client tools including `bcp` and ODBC drivers |
| Client Tools | `sqlclient` | Windows | Client tools are already included on the runner |
| sqlpackage | `sqlpackage` | Linux, macOS | Downloaded from the web |
| sqlpackage | `sqlpackage` | Windows | Installed using Chocolatey |
| Full-Text Search | `fulltext` | Linux, macOS | Builds a Docker image with full-text search for the selected SQL Server version; use with `sqlengine` |
| Full-Text Search | `fulltext` | Windows | Enabled during SQL Engine installation; use with `sqlengine` |
| SqlLocalDB | `localdb` | Windows | Accessible at `(localdb)\MSSQLLocalDB` |
| SSIS (Integration Services) | `ssis` | Windows | Installs Integration Services and creates the SSISDB catalog |

### Example workflows

Create a SQL Server 2022 container and install sqlpackage on Linux (omit `version` to use the default):

```yaml
on: [push]

jobs:
  test-everywhere:
    name: Test Action on all platforms
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v4

      - name: Run the action
        uses: potatoqualitee/mssqlsuite@v2
        with:
          install: sqlengine, sqlpackage

      - name: Run sqlclient
        run: sqlcmd -S localhost -U sa -P dbatools.I0 -d tempdb -Q "SELECT @@version;" -C
```

To use SQL Server 2025 instead, set `version: 2025`:

```yaml
on: [push]

jobs:
  test-sql-2025:
    runs-on: ubuntu-latest
    steps:
      - uses: potatoqualitee/mssqlsuite@v2
        with:
          install: sqlengine, fulltext
          version: 2025
```

Install SQL Server 2019 with full-text search, LocalDB, and SSIS on Windows, using a custom collation:

```yaml
on: [push]

jobs:
  test-windows:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4
      - name: Run the action
        uses: potatoqualitee/mssqlsuite@v2
        with:
          install: sqlengine, sqlclient, sqlpackage, localdb, fulltext, ssis
          version: 2019
          show-log: true
          collation: Latin1_General_BIN
      - name: Run sqlcmd
        run: sqlcmd -S localhost -U sa -P dbatools.I0 -d tempdb -Q "SELECT @@version;" -C
```

Using a custom admin username instead of the default 'sa'

```yaml
on: [push]

jobs:
  test-custom-admin:
    name: Test with custom admin user
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v4

      - name: Run the action with custom admin
        uses: potatoqualitee/mssqlsuite@v2
        with:
          install: sqlengine, sqlclient
          admin-username: dbadmin
          sa-password: MySecureP@ssword123

      - name: Test connection with custom admin user
        run: sqlcmd -S localhost -U dbadmin -P MySecureP@ssword123 -d tempdb -Q "SELECT @@version;" -C
```

## Contributing
Pull requests are welcome!

## TODO
* MacOS: Migrate docker from qemu to vz to speed up the process.
* Wait for GitHub Actions to support more stuff to make the install sleeker.
* Maybe more tools from [here](https://docs.microsoft.com/en-us/sql/tools/sqlpackage/sqlpackage-download?view=sql-server-ver15).
  * mssql-cli (command-line query tool)
  * osql
  * SQLdiag
  * sqlmaint
  * sqllogship
  * tablediff

## License
The scripts and documentation in this project are released under the [MIT License](LICENSE)

## Notes

The `SqlServer` PowerShell module is included on the Windows runner. You can find more information about what's installed on GitHub runners on their [docs page](https://docs.github.com/en/actions/using-github-hosted-runners/about-github-hosted-runners#supported-software).

## SSIS Support (Windows Only)

- **Install Option:** You can now add `ssis` to the `install` list to enable SQL Server Integration Services (SSIS) on Windows runners.
- **Catalog Creation:** When `ssis` is specified, the action will ensure the SSISDB catalog exists (creating it if necessary).
- **CI/CD Test:** The workflow includes a Windows-only test that verifies the SSISDB catalog is present after installation.

**Example:**
```yaml
    - name: Install SQL Server with SSIS
      uses: potatoqualitee/mssqlsuite@v2
      with:
        install: sqlengine, ssis
```

