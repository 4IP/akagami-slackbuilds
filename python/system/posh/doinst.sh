if [ ! -r etc/shells ]; then
  touch etc/shells
  chmod 644 etc/shells
fi

if ! grep -q /bin/posh etc/shells ; then
  printf %s\\n /bin/posh >> etc/shells
fi
