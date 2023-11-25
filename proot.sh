#!/bin/bash

print_help() {
  echo "Usage: proot [options]"
  echo "Options:"
  echo "  -u username     Specify the username. Do not include domain."
  echo "  -p password     Specify the password. Only an Argon2id hash will be stored."
  echo "  -adduser        Add a new user to the database. Must also specify -u and -p."
  echo "  -deluser        Delete a user from the database and Maildir. Must specify -u."
  echo "  -users          Display a list of usernames from the database."
  echo "  -passwords      Display a list of usernames and corresponding password hashes from the database."
  echo "  -help           Display this help message."
}

username=""
password=""
domain=$DOMAIN
database_path=$DATABASE_PATH
add_user=false

while [ "$#" -gt 0 ]; do
  case "$1" in
    -u)
      shift
      username="$1"
      ;;
    -p)
      shift
      password="$1"
      ;;
    -adduser)
      add_user=true
      ;;
    -deluser)
      delete_user=true
      ;;
    -users)
      query="SELECT username FROM mailbox;"
      ;;
    -passwords)
      query="SELECT username, password FROM mailbox;"
      ;;
    -help)
      print_help
      exit 0
      ;;
    *)
      echo "Invalid flag: $1"
      exit 1
      ;;
  esac
  shift
done

# -adduser flag to add new user to database
if [ "$add_user" = true ]; then
  # Salt, hash and base64 encode password
  password_salt=$(openssl rand -hex 16)
  hashed_password=$(echo -n "$password" | argon2 "$password_salt" -k 65536 -t 4 -p 2 -e)
  hashed_password=$(echo -n "$hashed_password" | base64 -w0)
  hashed_password=$(echo -n "{ARGON2ID.b64}$hashed_password")

  # Add user and corresponding salted b64 encoded argon2id hashed password to database
  query="INSERT INTO mailbox (username, password, domain, crypt) VALUES ('$username', '$hashed_password', '$domain', 2);"
  sqlite3 $database_path "$query"
  echo "User '$username' added to database."

  # Use the hash to generate password derived user key and re-encrypt folder keys
  doveadm_password_option=""
  if [ -n "$password" ]; then
    doveadm_password_option="-o plugin/mail_crypt_private_password=$hashed_password"
  fi
  doveadm $doveadm_password_option mailbox cryptokey generate -u "$username" -UR
fi

# -deluser flag deletes user from database and Maildir
maildir_path="/var/mail/Maildir/$domain/$username@$domain"
if [ "$delete_user" = true ]; then
  # Delete user from the database
  query="DELETE FROM mailbox WHERE username='$username';"
  sqlite3 $database_path "$query"
  echo "User '$username' deleted from database."

  # Delete user's Maildir directory

  if [ -d "$maildir_path" ]; then
    rm -rf "$maildir_path"
    echo "User '$username' Maildir deleted."
  else
    echo "Maildir for user '$username' not found."
  fi
fi

# If a username is specified, set up a query to retrieve the corresponding password
if [ -n "$username" ]; then
  query="SELECT password FROM mailbox WHERE username='$username';"
fi

# Execute the query and output results
result=$(sqlite3 $database_path "$query")
echo "$result"