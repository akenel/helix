#!/bin/bash

# # This script finds all files in the current directory and its subdirectories,
# # then displays the contents of each file one by one.

# # The `find` command searches for files (type f) in the current directory ('.').
# # The `while read -r file; do ... done` loop reads each found filename into the 'file' variable.
# # The `-r` option prevents backslash-escapes from being interpreted.
# find . -type f | while read -r file; do
#     # Clear the terminal screen.


#     # Print a header to show which file is currently being displayed.
#     # The 'printf' command is used for better control over the output.
#     printf "\n=== Displaying contents of: %s ===\n\n" "$file"

#     # Use `cat` to print the entire content of the file.
#     cat "$file"

#     # Pause the script and wait for the user to press Enter.
#     # This gives you time to read the file's contents before moving to the next one.
#     read -p "Press [Enter] to display the next file..."
# done

# Clear the screen one last time after the loop has finished.

printf "\nAll files have been displayed.\n"jq -s 'reduce .[] as $item ({}; . * $item)' \
  parts/realm_base.json \
  parts/client-scopes.json \
  parts/groups.json \
  parts/roles.json \
  parts/users.json > helix-realm-full.json
printf "\nAll files have been merged into helix-realm-full.json.\n"
printf "\nDisplaying the contents of helix-realm-full.json:\n\n"
cat helix-realm-full.json
printf "\nPress [Enter] to continue...\n"
read -r