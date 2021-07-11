# sqlsuite
A GitHub Action that automatically installs SQL Server suite of tools for Windows, macOS and Linux.

## Documentation

Just copy the code below and modify the line **`install: engine, sqlcmd, sqlpackage, localdb`** with the options you need.

```yaml
    - name: Install a SQL Server suite of tools
      uses: potatoqualitee/sqlsuite@v1
      with:
        install: engine, sqlcmd, sqlpackage, localdb
```

## Usage

### Pre-requisites

Create a workflow `.yml` file in your repositories `.github/workflows` directory. An [example workflow](#example-workflow) is available below. For more information, reference the GitHub Help Documentation for [Creating a workflow file](https://help.github.com/en/articles/configuring-a-workflow#creating-a-workflow-file).

### Inputs

* `install` - The apps to install
* `sa_password` - The password for the SQL instance

### Outputs

None

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
          install: engine, sqlcmd, sqlpackage, localdb

      - name: Run sqlcmd
        run: sqlcmd -S localhost -U sa -P dbatools.I0 -d tempdb -Q "SELECT @@version;"
```

## Contributing
Pull requests are welcome!

## TODO
* Wait for GitHub Actions to support more stuff to make the install sleeker. 

## License
The scripts and documentation in this project are released under the [MIT License](LICENSE)

