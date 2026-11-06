@echo -off
# Run by the UEFI shell in \EFI\slbounce\ (boot entry "Ubuntu (EL2 KVM)"):
# start the DSPs (qebspil, if installed), install the slbounce hook, then
# hand over to the EL2 GRUB. qebspil boots ADSP/CDSP/SLPI inside
# ExitBootServices(); slbounce switches to EL2 only after it returns.
# The ESP's fsN number depends on the firmware (fs13 on this X13s), so scan.
for %i run (0 31)
  if exist fs%i:\EFI\slbounce\slbounce.efi then
    fs%i:
    cd \EFI\slbounce
    if exist qebspilaa64.efi then
      load qebspilaa64.efi
    endif
    load slbounce.efi
    grubel2.efi
    echo "grubel2.efi returned; dropping to shell"
    goto done
  endif
endfor
echo "slbounce.efi not found on fs0-fs31"
:done
