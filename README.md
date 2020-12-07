# archlinux-headless

A script to modify the original Arch Linux ISO to enable sshd.service and password-less root login. This gives you a true headless experience

To burn the iso into flash drive, follow the instruction https://wiki.archlinux.org/index.php/USB_flash_installation_medium#Using_manual_formatting

**WARNING** Don't use `cat` or `dd` to directly write the iso into your flash drive as the El Torito boot parameters are not correctly handeled by the script.  You can check https://gitlab.archlinux.org/archlinux/archiso/-/blob/master/archiso/mkarchiso to know how to do it correctly
