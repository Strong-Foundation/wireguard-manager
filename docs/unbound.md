### Blocking Domains Using Unbound

To block domains using Unbound, add the necessary configuration and restart the Unbound service:

```bash
# Append configuration to include hosts.conf in unbound.conf
echo -e "\tinclude: /etc/unbound/unbound.conf.d/hosts.conf" >> /etc/unbound/unbound.conf

# Fetch the list of domains to block and format it for Unbound
curl "https://raw.githubusercontent.com/complexorganizations/content-blocker/main/assets/hosts" | awk '{print "local-zone: \""$1"\" always_refuse"}' > /etc/unbound/unbound.conf.d/hosts.conf

# Restart Unbound to apply changes
systemctl restart unbound || service unbound restart
```

### Enabling Logging in Unbound

To enable detailed logging in Unbound, update the configuration and create the log file:

```bash
# Increase verbosity level for detailed logging
sed -i "s|verbosity: 0|verbosity: 5|" /etc/unbound/unbound.conf

# Specify log file location and enable query logging
echo -e "\tlogfile: /var/log/unbound.log\n\tlog-queries: yes" >> /etc/unbound/unbound.conf

# Create and set permissions for the log file
touch /var/log/unbound.log
chown unbound:unbound /var/log/unbound.log

# Restart Unbound to apply changes
systemctl restart unbound || service unbound restart

# Optional: Tail the log file to view logs in real-time
tail -f /var/log/unbound.log
```

### Resolving Domain Issues in Unbound

If Unbound is not resolving domains, modify the trust anchor file setting and restart the service:

```bash
# Comment out auto-trust-anchor-file setting in unbound.conf
sed -i "s|auto-trust-anchor-file: /var/lib/unbound/root.key|# auto-trust-anchor-file: /var/lib/unbound/root.key|" /etc/unbound/unbound.conf

# Restart Unbound to apply changes
systemctl restart unbound || service unbound restart
```