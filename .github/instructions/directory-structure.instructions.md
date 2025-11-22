# Project Directory Structure

Below is the directory structure for the `nbrly` workspace, with descriptions and intent for each folder and file.

## Folder Descriptions

- **.github/**: Contains GitHub-specific files, including detailed design documents, requirements, and AI prompts.
- **.vscode/**: Configuration for the Visual Studio Code editor to ensure consistent settings across the team.
- **app-gtway-apps/**: Holds Dockerfiles and configurations for various applications (e.g., `bmapp`, `nbapp`) deployed via the application gateway.
- **docs/**: General project documentation.
- **iac-cli/**: Contains Infrastructure as Code scripts and CLI tools for provisioning and managing resources.
- **logs/**: Directory for storing log files generated during execution or build processes.
- **sample-app/**: Source code for a sample application used for testing or demonstration.
- **.gitignore**: Prevents committing unnecessary files to version control.
- **README.md**: Entry point for understanding the project.

> **Intent:**  
> This structure is designed to separate concerns, improve maintain// filepath: .github/instructions/directory-structure.md
# Project Directory Structure

Below is the directory structure for the `nbrly` workspace, with descriptions and intent for each folder and file.

```
nbrly/
├── .github/                  # GitHub-specific configuration and documentation
│   ├── instructions/         # Documentation and guidelines for contributors
│   │   └── directory-structure.md  # This file: describes the project structure and intent
│   ├── prompts/              # Prompts for AI assistants or templates
│   ├── app-requirement.md    # Application requirements documentation
│   ├── azure-ca-appgtwy-detail-design.md # Detailed design for Azure Container Apps & App Gateway
│   ├── azure-ca-appgtwy.md   # High-level design for Azure Container Apps & App Gateway
│   ├── capacity-container-size-analysis.md # Analysis of container sizing and capacity
│   └── ...                   # Other documentation and backup files
├── .vscode/                  # VS Code editor settings
│   └── settings.json         # Workspace-specific settings
├── app-gtway-apps/           # Container definitions for application gateway apps
│   ├── Dockerfile.bmapp1     # Dockerfile for bare metal app 1
│   ├── Dockerfile.bmapp2     # Dockerfile for bare metal app 2
│   ├── Dockerfile.nbapp1     # Dockerfile for notebook app 1
│   └── ...                   # Other Dockerfiles and configuration
├── docs/                     # Project documentation
├── iac-cli/                  # Infrastructure as Code (IaC) CLI tools and scripts
├── logs/                     # Application or build logs
├── sample-app/               # Sample application source code
├── .gitignore                # Specifies files and directories to be ignored by Git
├── .gitignore-guide.md       # Guide explaining the .gitignore rules
└── TODO.md                   # List of pending tasks and to-dos
```

## Folder Descriptions

- **.github/**: Contains GitHub-specific files, including detailed design documents, requirements, and AI prompts.
- **.vscode/**: Configuration for the Visual Studio Code editor to ensure consistent settings across the team.
- **app-gtway-apps/**: Holds Dockerfiles and configurations for various applications (e.g., `bmapp`, `nbapp`) deployed via the application gateway.
- **docs/**: General project documentation.
- **iac-cli/**: Contains Infrastructure as Code scripts and CLI tools for provisioning and managing resources.
- **logs/**: Directory for storing log files generated during execution or build processes.
- **sample-app/**: Source code for a sample application used for testing or demonstration.
- **.gitignore**: Prevents committing unnecessary files to version control.
- **README.md**: Entry point for understanding the project.

> **Intent:**  
> This structure is designed to separate concerns, improve maintain

## Instruction to follow

- **docs/**: Always place the generated documentation md in docs folder of the project and do not clutter documentation in the other folders
- **iac-cli/**: Contains Infrastructure as Code scripts and CLI tools for provisioning and managing resources.
- **iac-cli/scripts: All the sh scripts needs to created here related to iac and respective sub directories such as helpers and others can be created as per the need.
- **iac-cli/config: All the configuration parameters needs to created here related to iac and respective sub directories such as .generated and others can be created as per the need.
- **iac-cli/creds: This directory will have files containing sensitive information such secrets, certificates, password. This directory content should not be committed to git

- **app-gtway-apps/**: This folder will hold the sample applications.
- any iac resource references must be copied into app-gtway-apps/config for configuration parameters or app-gtway-apps/creds for secrets and password.
-  **app-gtway-apps/** should treated as a isolated directory which can be later taken out independently.
-  **app-gtway-apps/** Hence any dpendency on iac-cli content must be copied over to respective directory under app-gtway-apps
-  **app-gtway-apps/scripts** will have scripts folder to contain the generated sh scripts and will have subdirectories as per the need.