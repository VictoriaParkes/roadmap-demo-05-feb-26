# roadmap-demo-05-feb-26


## Best Practice Setup:
### use new terminal each refresh

1. Create access keys (you need some initial credential)

    IAM → Users → Security credentials → Create access key

2. Create role:\
    Trusted entity type = AWS account\
    An AWS account = This account\
    Add permission policies\
        - admin\
    Name = terraform-execution

3. Configure with short-lived credentials:

    `aws configure`\
    `# Enter your keys`

4. Use STS 

    1. to get temporary credentials (15 min - 12 hours):

    `aws sts get-session-token --duration-seconds 3600`

    2. Export the temporary credentials:

    `export AWS_ACCESS_KEY_ID=<from output>`\
    `export AWS_SECRET_ACCESS_KEY=<from output>`\
    `export AWS_SESSION_TOKEN=<from output>`\

    ### OR
    1. Use STS to get temporary credentials (15 min - 12 hours) and copy the output values and export them:

    `eval $(aws sts get-session-token --duration-seconds 3600 --output json | jq -r '.Credentials | "export AWS_ACCESS_KEY_ID=\(.AccessKeyId)\nexport AWS_SECRET_ACCESS_KEY=\(.SecretAccessKey)\nexport AWS_SESSION_TOKEN=\(.SessionToken)"')`


    ### *Can also edit `.config` file manually*

        .config:

        [default]\
        region = eu-west-2\
        output = json\
        role_arn = arn:aws:iam::<aws_account_id>:role/<role_name>\
        source_profile = user1

        .credentials:

        [user1]\
        aws_access_key_id = <Access_key_ID>>\
        aws_secret_access_key = <Secret_access_key>



5. Check caller identity to verify user is used:

    `aws sts get-caller-identity`

    output:

    `"UserId": "<Access_key_ID>>:botocore-session-1770646657",`\
    `"Account": "<aws_account_id>",`\
    `"Arn": "arn:aws:sts::<aws_account_id>:assumed-role/<role_name>/botocore-session-1770646657"`

6. Store long-lived keys securely:

    `chmod 600 ~/.aws/credentials`

---
## Commands:
### Docker

- `docker buildx build --platform linux/amd64 -t roadmap-demo-app:latest .`

### Terraform
- Check for running Terraform processes: `ps aux | grep terraform`

---
To find your ~/.aws/config file, look in your user's home directory. The exact path depends on your operating system: 
1. Standard File Paths
Linux, macOS, or Unix: /Users/USERNAME/.aws/config (often abbreviated as ~/.aws/config).
Windows: C:\Users\USERNAME\.aws\config (accessible via the %USERPROFILE%\.aws\config environment variable). 

2. Quick Terminal Commands 
If you want to view or verify the file location quickly, use these commands:
View file contents:
Mac/Linux: cat ~/.aws/config.
Windows (Command Prompt): type %USERPROFILE%\.aws\config.
Identify active config: Run aws configure list to see exactly which file the AWS CLI is currently using for your settings. 

3. Hidden Folder Tips
Dotfiles: The .aws folder is a "hidden" directory because it starts with a period.
On macOS: In Finder, press Cmd + Shift + . to reveal hidden files.
On Windows: Ensure "Hidden items" is checked in the View tab of File Explorer. 

4. Custom Locations
If the file isn't in the default spot, check if the AWS_CONFIG_FILE environment variable has been set to a different path. 

Note: If the file does not exist yet, you can create it automatically by running the aws configure command in your terminal. 
