# sshd-ipset-whitelist

A docker-container with `ipset` and `iptables` from kubernetes, inherited by
using [debian-iptables](https://github.com/kubernetes/kubernetes/tree/master/build/debian-iptables)
as a parent image.

This container can be used to implement ip based whitelisting of the SSH daemon.

By using the country-whitelist published by [IPdeny](http://www.ipdeny.com/), you agree to their
[Terms of Service (TOS)](http://www.ipdeny.com/tos.php) and are familiar with their
[Copyright notice](http://www.ipdeny.com/copyright.php) and [Privacy Policy](http://www.ipdeny.com/privacy.php).

## Requirements

- Make sure to run this as a privileged container with host networking.
- Make sure that you are loading IPv6 related kernel-modules before starting this conatiner,
  see [moby#33605](https://github.com/moby/moby/issues/33605#issuecomment-307361421)

## Configuration

The container can be configured with environment variables:

- `WHITELISTED_IPV4_IPS`: list of IPv4 addresses separated by space that should be whitelisted
- `WHITELISTED_IPV4_NETS`: list of IPv4 networks separated by space that should be whitelisted
- `WHITELISTED_IPV6_IPS`: list of IPv6 addresses separated by space that should be whitelisted
- `WHITELISTED_IPV6_NETS`: list of IPv6 networks separated by space that should be whitelisted
- `WHITELISTED_COUNTRIES`: list of lowercase [ISO 3166-1 alpha-2](https://en.wikipedia.org/wiki/ISO_3166-1_alpha-2)
  country-codes to whitelist; source for the whitelist are hte country IP blocks published by
  [IPdeny](http://www.ipdeny.com/)

## Example

Allow connections from Switzerland, IPv4 private IP addresses and the IPv4 address 8.8.8.8:

```bash
docker run \
    --rm \
    --privileged \
    --net=host \
    -e WHITELISTED_COUNTRIES="ch" \
    -e WHITELISTED_IPV4_NETS="10.0.0.0/8 172.16.0.0/12 192.168.0.0/16" \
    -e WHITELISTED_IPV4_IPS="8.8.8.8" \
  linkyard/sshd-ipset-whitelist
```
