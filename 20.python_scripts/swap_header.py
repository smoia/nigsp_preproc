#!/usr/bin/env python3

"""
Overwrite header of a volume.

From two images, create an image that has data of img1
and affine transform and header of img2.

Usage: swap_header.py img1 img2 out
"""
import sys
import nibabel as nib

if __name__ == '__main__':
    vol_orig = nib.load(sys.argv[1])
    vol_bet = nib.load(sys.argv[2])
    out = nib.Nifti1Image(vol_bet.get_fdata(), vol_orig.affine, vol_orig.header)
    out.to_filename(sys.argv[3])
