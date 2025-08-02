# mssqlsuite
This GitHub Action automatically installs a SQL Server suite of tools including sqlcmd, bcp, sqlpackage, the sql engine, localdb and more for Windows, macOS and Linux.

> **Note:** `sqlcmd` is always installed by default because this action needs it to execute some SQL.

## Documentation

Just copy the code below and modify the line **`install: sqlengine, sqlclient, sqlpackage, localdb, fulltext`** with the options you need.

```yaml
    - name: Install a SQL Server suite of tools
      uses: potatoqualitee/mssqlsuite@v1.11
      with:
        install: sqlengine, sqlclient, sqlpackage, localdb, fulltext, ssis
```

## Usage

### Pre-requisites

Create a workflow `.yml` file in your repositories `.github/workflows` directory. An [example workflow](#example-workflow) is available below. For more information, reference the GitHub Help Documentation for [Creating a workflow file](https://help.github.com/en/articles/configuring-a-workflow#creating-a-workflow-file).

### Inputs

* `install` - The apps to install. Options include: `sqlengine`, `sqlclient`, `sqlpackage`, `localdb`, `fulltext`, and `ssis`
* `sa-password` - The sa password for the SQL instance. The default is `dbatools.I0`
* `admin-username` - The admin username for the SQL instance. The default is `sa`. When specified, the built-in `sa` user will be renamed to this username
* `collation` - Change the collation associated with the SQL Server instance
* `version` - The version of SQL Server to install in year format. Options are 2019 and 2022 (defaults to 2022)
* `show-log` - Show logs, including docker logs, for troubleshooting

### Outputs

None

**Note:** The `ssis` option is only supported on Windows runners. When specified, the action will ensure the SSISDB catalog exists (creating it if necessary).

### Details

| Application | Keyword | OS | Details | Time |
| -------------- | ------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------ | ------------- |
| SQL Engine | sqlengine | Linux | Docker container with SQL Server 2022, accessible at `localhost` | ~30s |
| SqlLocalDB | localdb | Linux | Not supported | N/A |
| Client Tools | sqlclient | Linux | Includes sqlcmd, bcp, and odbc drivers | ~15s |
| sqlpackage | sqlpackage | Linux | Installed from web | ~5s |
| Full-Text Search | fulltext | Linux | Installed using apt-get | ~45s |
| SQL Engine | sqlengine | Windows | Full install of SQL Server 2022, accessible at `localhost`. Docker took like 15 minutes. Windows and SQL authentication both supported. | ~3m |
| SqlLocalDB | localdb | Windows | Accessible at `(localdb)\MSSQLLocalDB` | ~30s |
| Client Tools | sqlclient | Windows | Already included in runner, including sqlcmd, bcp, and odbc drivers | N/A |
| sqlpackage | sqlpackage | Windows | Installed using chocolatey | ~20s |
| Full-Text Search | fulltext | Windows | Enabled during SQL Engine install | ~1m |
| SSIS (Integration Services) | ssis | Windows | Installs SQL Server Integration Services and creates the SSISDB catalog | ~2m |
| SQL Engine | sqlengine | macOS | Docker container with SQL Server 2022 accessible at `localhost`. | ~7m |
| SqlLocalDB | localdb | macOS | Not supported | N/A |
| Client Tools | sqlclient | macOS | Includes bcp and odbc drivers | ~20s |
| sqlpackage | sqlpackage | macOS | Installed from web | ~5s |
| Full-Text Search | fulltext | macOS | Available only via Docker container with SQL Server (see SQL Engine above) | ~7m |

### Example workflows

Create a SQL Server 2022 container and sqlpackage on Linux (the fastest runner, by far)

```yaml
on: [push]

jobs:
  test-everywhere:
    name: Test Action on all platforms
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v4

      - name: Run the action
        uses: potatoqualitee/mssqlsuite@v1.11
        with:
          install: sqlengine, sqlpackage

      - name: Run sqlclient
        run: sqlcmd -S localhost -U sa -P dbatools.I0 -d tempdb -Q "SELECT @@version;" -C
```

Installing everything on all OSes, plus using a different sa password and collation

```yaml
on: [push]

jobs:
  test-everywhere:
    name: Test Action on all platforms
    runs-on: ${{ matrix.os }}
    strategy:
      fail-fast: false
      matrix:
        os: [ubuntu-latest, windows-latest, macOS-latest]

    steps:
      - uses: actions/checkout@v4

      - name: Run the action
        uses: potatoqualitee/mssqlsuite@v1.11
        with:
          install: sqlengine, sqlclient, sqlpackage, localdb, fulltext, ssis
          version: 2019
          sa-password: dbatools.I0
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
        uses: potatoqualitee/mssqlsuite@v1.11
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
---

## SSIS Support (Windows Only)

- **Install Option:** You can now add `ssis` to the `install` list to enable SQL Server Integration Services (SSIS) on Windows runners.
- **Catalog Creation:** When `ssis` is specified, the action will ensure the SSISDB catalog exists (creating it if necessary).
- **CI/CD Test:** The workflow includes a Windows-only test that verifies the SSISDB catalog is present after installation.

**Example:**
```yaml
    - name: Install SQL Server with SSIS
      uses: potatoqualitee/mssqlsuite@v1.11
      with:
        install: sqlengine, ssis
```

