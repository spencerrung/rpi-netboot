# Ansible Vault - Sensitive Data Management

This project uses Ansible Vault to encrypt sensitive data like SSH keys and passwords.

## Encrypted Files

- `group_vars/vault.yml` - Contains sensitive variables (SSH keys, passwords)

## Setup

### 1. Encrypt the Vault File (First Time)

```bash
# You'll be prompted for a password
ansible-vault encrypt group_vars/vault.yml
```

**IMPORTANT:** Save this password securely! You'll need it to run playbooks.

### 2. Save Password for Convenience (Optional)

Create a password file (NOT committed to git):

```bash
echo "your-vault-password" > .vault_pass
chmod 600 .vault_pass
```

## Usage

### Running Playbooks with Vault

**Option 1: Prompt for password**
```bash
ansible-playbook -i inventory.yml playbooks/rpi-netboot.yml --ask-vault-pass
```

**Option 2: Use password file**
```bash
ansible-playbook -i inventory.yml playbooks/rpi-netboot.yml --vault-password-file .vault_pass
```

**Option 3: With Docker**
```bash
docker run --rm \
  -v "c:/Users/Spencer/.ssh/raspberrypi_rsa:/tmp/key:ro" \
  -v "$(pwd)/..:/workspace:ro" \
  -e ANSIBLE_VAULT_PASSWORD="your-password" \
  cytopia/ansible:latest-tools sh -c '\
    mkdir -p /root/.ssh && \
    cp /tmp/key /root/.ssh/raspberrypi_rsa && \
    chmod 600 /root/.ssh/raspberrypi_rsa && \
    cd /workspace/ansible && \
    echo "$ANSIBLE_VAULT_PASSWORD" > /tmp/vault_pass && \
    ansible-playbook -i inventory.yml playbooks/rpi-netboot.yml \
    --vault-password-file /tmp/vault_pass \
    --ssh-common-args="-o StrictHostKeyChecking=no"'
```

## Managing Vault

### View Encrypted File

```bash
ansible-vault view group_vars/vault.yml
```

### Edit Encrypted File

```bash
ansible-vault edit group_vars/vault.yml
```

### Change Vault Password

```bash
ansible-vault rekey group_vars/vault.yml
```

### Decrypt (Temporarily)

```bash
# Decrypt to edit manually
ansible-vault decrypt group_vars/vault.yml

# Edit the file...

# Re-encrypt before committing
ansible-vault encrypt group_vars/vault.yml
```

## What's in vault.yml

- `vault_ssh_public_key` - SSH public key for pi user authentication
- `vault_pi_password` - Default password for pi user console access

## Security Best Practices

1. ✅ **Never commit unencrypted vault.yml**
2. ✅ **Never commit .vault_pass file**
3. ✅ **Use strong vault password**
4. ✅ **Rotate SSH keys periodically**
5. ✅ **Share vault password securely** (password manager, not email/chat)

## For New Team Members

1. Get vault password from team lead (securely)
2. Create `.vault_pass` file with password
3. Verify access: `ansible-vault view group_vars/vault.yml`
4. Run playbooks with `--vault-password-file .vault_pass`

## Troubleshooting

### "Decryption failed" Error

- Vault password is incorrect
- File may not be encrypted (check with `cat group_vars/vault.yml`)

### Forgot Vault Password

- If vault.yml is encrypted and password is lost, you'll need to:
  1. Delete vault.yml
  2. Create new vault.yml with your SSH keys
  3. Re-encrypt with new password
