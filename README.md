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
* `sa_password` - The password for the SQL instance. The default is `dbatools.I0`
* `show_log` - Show the log file for the docker container

### Outputs

None

### Details

| Setting | Description | Default Value | Type |
| -------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------ | ------------- |
| Case Sensitive | Case sensitive search | false | Boolean |
| Codicon | The codicon that shows up on the side of the filename. Alternatives include `file-binary`, `book`, and more. | file | String |
| Depth | The depth of subfolders to include in the search. | 0 | Number 0-5 |
| Folder | The folder to look for workspace files in. If Folder is empty, your home folder will be used. | None (all of your current workspaces will be used) | String |
| Include File Types | Return only these specific file types. Example: php, ts, ps1 | | String |
| Search minimum | The minimum number of workspaces required before the search box is displayed. 0 Will always display the search box. | 15 | Number 0-100 |
| Show Paths | Show the paths to the workspaces in the sidebar. Available options are: 'Always', 'Never', 'As needed' (will only display paths if there are duplicate labels). | As Needed | Dropdown List |

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

