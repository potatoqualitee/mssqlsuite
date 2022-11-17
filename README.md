# mssqlsuite
This GitHub Action automatically installs a SQL Server suite of tools including sqlcmd, bcp, sqlpackage, the sql engine, localdb and more for Windows, macOS and Linux.

## Documentation

Just copy the code below and modify the line **`install: sqlengine, sqlclient, sqlpackage, localdb`** with the options you need.

```yaml
    - name: Install a SQL Server suite of tools
      uses: potatoqualitee/mssqlsuite@v1.7
      with:
        install: sqlengine, sqlclient, sqlpackage, localdb
```

## Usage

### Pre-requisites

Create a workflow `.yml` file in your repositories `.github/workflows` directory. An [example workflow](#example-workflow) is available below. For more information, reference the GitHub Help Documentation for [Creating a workflow file](https://help.github.com/en/articles/configuring-a-workflow#creating-a-workflow-file).

### Inputs

* `install` - The apps to install. Options include: `sqlengine`, `sqlclient`, `sqlpackage`, and `localdb`
* `sa-password` - The sa password for the SQL instance. The default is `dbatools.I0`
* `collation` - Change the collation associated with the SQL Server instance
* `version` - The version of SQL Server to install in year format. Options are 2017 and 2019, defaults to 2019
* `show-log` - Show logs, including docker logs, for troubleshooting

### Outputs

None

### Details

| Application | Keyword | OS | Details | Time |
| -------------- | ------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------ | ------------- |
| SQL Engine | sqlengine | Linux | Docker container with SQL Server 2019, accessible at `localhost` | ~45s |
| SqlLocalDB | localdb | Linux | Not supported | N/A |
| Client Tools | sqlclient | Linux | Already included in runner, including sqlcmd, bcp, and odbc drivers | N/A |
| sqlpackage | sqlpackage | Linux | Installed from web | ~20s |
| SQL Engine | sqlengine | Windows | Full install of SQL Server 2019, accessible at `localhost`. Docker took like 15 minutes. Windows and SQL authentication both supported. | ~5m |
| SqlLocalDB | localdb | Windows | Accessible at `(localdb)\MSSQLLocalDB` | ~30s |
| Client Tools | sqlclient | Windows | Already included in runner, including sqlcmd, bcp, and odbc drivers | N/A |
| sqlpackage | sqlpackage | Windows | Installed using chocolatey | ~1.5m |
| SQL Engine | sqlengine | macOS | Docker container with SQL Server 2019 accessible at `localhost`. | ~3m |
| SqlLocalDB | localdb | macOS | Not supported | N/A |
| Client Tools | sqlclient | macOS | Includes sqlcmd, bcp, and odbc drivers | ~30s |
| sqlpackage | sqlpackage | macOS | Installed from web | ~5s |

### Example workflows

Create a SQL Server 2019 container and sqlpackage on Linux (the fastest runner, by far)

```yaml
on: [push]

jobs:
  test-everywhere:
    name: Test Action on all platforms
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v3

      - name: Run the action
        uses: potatoqualitee/mssqlsuite@v1.7
        with:
          install: sqlengine, sqlpackage

      - name: Run sqlclient
        run: sqlcmd -S localhost -U sa -P dbatools.I0 -d tempdb -Q "SELECT @@version;"
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
      - uses: actions/checkout@v3

      - name: Run the action
        uses: potatoqualitee/mssqlsuite@v1.7
        with:
          install: sqlengine, sqlclient, sqlpackage, localdb
          version: 2017
          sa-password: c0MplicatedP@ssword
          show-log: true
          collation: Latin1_General_BIN

      - name: Run sqlcmd
        run: sqlcmd -S localhost -U sa -P c0MplicatedP@ssword -d tempdb -Q "SELECT @@version;"
```

## Contributing
Pull requests are welcome!

## TODO
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

