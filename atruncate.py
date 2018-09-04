#!/usr/bin/python3
# -*- coding: utf-8 -*-
#
# Quick and dirty clone of atruncate
#

import sys

import os

import io

import re

if __name__ != "__main__":
	raise Exception("This application is meant to be used stand-alone")

file_to_truncate = sys.argv[1]

BLOCK_SIZE = 2048 * 1024

class ReversedFile(io.FileIO):

	def __init__(self, *args, **kwargs):

		super().__init__(*args, **kwargs)

		# To the end
		self.file_end = os.path.getsize(self.name)
		self.seek(self.file_end)

		self._end_reached = False

	def read(self, size=-1):

		if self._end_reached:
			return b""

		if size > -1:
			starting_point = self.tell() - size
			if starting_point < 0:
				self.seek(0)
				block = super().read(size + starting_point)

				self.seek(0)
				self._end_reached = True
			else:
				self.seek(starting_point)

				block = super().read(size)
				self.seek(starting_point)

			return block[::-1]
		else:
			return super().read(size)[::-1]

expr = re.compile(b"^\x00*")

with ReversedFile(file_to_truncate, "r+b") as f:
	empty_block = b"\x00" * BLOCK_SIZE

	end = 0
	skipped = 0
	while True:
		block = f.read(BLOCK_SIZE)

		if block == empty_block:
			skipped += BLOCK_SIZE
			continue
		else:
			end_result = expr.search(block)
			if end is not None:
				end = end_result.end()
				skipped += end
				break

	f.truncate(f.file_end - skipped)
