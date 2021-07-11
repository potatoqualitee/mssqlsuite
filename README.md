# sqlsuite
A GitHub Action that automatically installs SQL Server suite of tools (sqlcmd, sqlpackage, sql engine) for Windows, macOS and Linux.

## Documentation

Just copy the code below and modify the line **`install: engine, sqlclient, sqlpackage, localdb`** with the options you need.

```yaml
    - name: Install a SQL Server suite of tools
      uses: potatoqualitee/sqlsuite@v1
      with:
        install: engine, sqlclient, sqlpackage, localdb
```

## Usage

### Pre-requisites

Create a workflow `.yml` file in your repositories `.github/workflows` directory. An [example workflow](#example-workflow) is available below. For more information, reference the GitHub Help Documentation for [Creating a workflow file](https://help.github.com/en/articles/configuring-a-workflow#creating-a-workflow-file).

### Inputs

* `install` - The apps to install. Options include: `engine`, `sqlclient`, `sqlpackage`, and `localdb`
* `sa_password` - The sa password for the SQL instance. The default is `dbatools.I0`
* `show_log` - Show the log file for the docker container

### Outputs

None

### Details

| Application | Operating System | Details | Install time |
| -------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------ | ------------- |
| SQL Server Engine | Linux | Docker container with SQL Server 2019, accessible at `localhost` | ~45 seconds |
| SQL Server Engine | macOS | Docker container with SQL Server 2019 running on VirtualBox, accessible at `localhost`. Docker [not supported on macOS](https://github.community/t/why-is-docker-not-installed-on-macos/17017) in GitHub Actions. | ~5 minutes |
| SQL Server Engine | Windows | Full install of SQL Server 2019, accessible at `localhost`. Docker took like 15 minutes. Windows and SQL Server authentication both supported. | ~5 minutes |
| Microsoft SQL Server Express LocalDB | Linux | Not supported | N/A |
| Microsoft SQL Server Express LocalDB | macOS | Not supported | N/A |
| Microsoft SQL Server Express LocalDB | Windows | Accessible at `(localdb)\MSSQLLocalDB` | ~30 seconds |
| SQL Client Tools | Linux | Already included in runner, including sqlcmd, bcp, and odbc drivers | N/A |
| SQL Client Tools | macOS | Includes sqlcmd, bcp, and odbc drivers | ~2 minutes |
| SQL Client Tools | Windows | Already included in runner, including sqlcmd, bcp, and odbc drivers | N/A |
| sqlpackage | Linux | Installed from web | ~20 seconds |
| sqlpackage | macOS | Installed from web | ~25 seconds |
| sqlpackage | Windows | Installed using chocolatey | ~1.5 minutes |


### Example workflows

Installing everything on all OSes

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
      - uses: actions/checkout@v2

      - name: Run the action
        uses: potatoqualitee/sqlsuite@initial
        with:
          install: engine, sqlclient, sqlpackage, localdb

      - name: Run sqlclient
        run: sqlclient -S localhost -U sa -P dbatools.I0 -d tempdb -Q "SELECT @@version;"
```

## Contributing
Pull requests are welcome!

## TODO
* Wait for GitHub Actions to support more stuff to make the install sleeker. 

## License
The scripts and documentation in this project are released under the [MIT License](LICENSE)

