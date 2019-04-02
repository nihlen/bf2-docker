#! /usr/bin/python
#
# rotate_demo.py: simple file-rotation and index updating script
#
# Requires Python 2.3 or newer.
#
# Theory of operation:
# When automatic demo recording is enabled in the BF2 dedicated server it will
# call a hook program (such as this) when a new demo file is ready for
# publishing. The server will wait for the hook program to complete before
# notifying connected clients of the URL the demo can be downloaded from. It is
# therefore important that all work is done in a blocking manner in this
# program, or clients might try to download demos that aren't in place on the
# web server yet.
#
# Copyright (c)2004 Digital Illusions CE AB
# Author: Andreas Fredriksson

import os
import sys
import shutil

# for debugging a hack like this might be useful since stdout and stderr are
# discarded when the script is run
#class writer:
#	def __init__(self):
#		self.stream = open('log.txt', 'w')
#	def write(self, str):
#		self.stream.write(str)
#
#sys.stdout = writer()

# helper function to create directories as needed -- this doesn't care about
# umask or permissions in general so consider this a starting point
def ensure_exists(path):
	try:
		os.stat(path)
	except:
		try:
			os.makedirs(path)
		except:
			pass

# set some sane defaults
options = {
	'use_ftp':'0',
	'ftp_server':'',
	'ftp_target_dir':'',
	'ftp_user':None,
	'ftp_password':None,
	'target_root': 'webroot',
	'file_limit': '10',
}

# parse the config file, if it's there
try:
	config = open('rotate_demo.cfg', 'rt')
	for line_ in config:
		line = line_.strip()
		if len(line) == 0 or line.startswith('#'): continue
		try:
			key, value = line.split('=')
			options[key.strip()] = value.strip()
		except ValueError, ex:
			print ex
except IOError:
	pass

# our first argument indicates the demo file which is ready to be moved
path = os.path.normpath(sys.argv[1].replace('"', ''))

# handle local file shuffling (web server on same host as bf2 server, or on network share)
if options['use_ftp'] == '0':
	# this is our target directory (i.e. the download dir)
	target_demo_dir = os.path.join(options['target_root'], 'demos')

	# create the directory structure if it doesn't exist
	ensure_exists(options['target_root'])
	ensure_exists(os.path.join(options['target_root'], 'demos'))

    # don't move if path and target are the same
    if os.path.abspath(os.path.dirname(path)) != os.path.abspath(target_demo_dir):
        try:
            # NOTE: this requires atleast Python 2.3
            print "moving '%s' to '%s'" % (path, target_demo_dir)
            shutil.move(path, target_demo_dir)
        except IOError:
            sys.exit(1)

	timestamped = []

	# get a list of .bf2demo files in the target dir (including our own file)
	for pf in filter(lambda x: x.endswith('.bf2demo'), os.listdir(target_demo_dir)):
		try:
			ppath = os.path.join(target_demo_dir, pf)
            os.chmod(ppath, 0644) # make web-readable
			timestamped.append((os.stat(ppath).st_mtime, ppath))
		except IOError:
			pass # don't let I/O errors stop us

	# sort the timestamped file list according to modification time
	# NOTE: this sort is reversed so that older files are at the end of the list
	def compare_times(f1, f2): return cmp(f2[0], f1[0]) # note reverse sort order
	timestamped.sort(compare_times)

	# delete the oldest files to meet the file limit
	file_limit = int(options['file_limit'])
	for timestamp, deletium in timestamped[file_limit:]:
		try:
			os.remove(deletium)
		except IOError:
			pass # file in use?

	# create the index file
	if 0: # dep: I guess this is superfluous
		idxf = open(os.path.join(options['target_root'], 'index.lst'), 'w')
		for timestamp, keptfile in timestamped[:file_limit]:
			fn = keptfile.split(os.sep)[-1]
			idxf.write('demos/%s\n' % (fn))
		idxf.close()

else: # use ftp
	try:
		import ftplib
		import re

		path.replace('\\\\', '\\')

		path = os.path.normpath(path).replace('\\', '/')

		fn = path
		idx = fn.rfind('/')
		if idx != -1: fn = fn[idx+1:]

		demof = open(path, 'rb')

		# set up ftp connection and change cwd
		ftp = ftplib.FTP(options['ftp_server'], options['ftp_user'], options['ftp_password'])
		ftp.cwd(options['ftp_target_dir'])

		file_limit = int(options['file_limit'])

		try:
			files = ftp.nlst()
		except Exception:
			files = []
		files = filter(lambda x: x.endswith('.bf2demo'), files)
		files.sort()

		# store the new file
		ftp.storbinary('STOR '+fn, demof)

		demof.close()

		try:
			# delete local file
			os.unlink(path)
		except OSError:
			# couldn't unlink local file, what to do?
			pass

		# handle rotation
		while len(files) + 1 > file_limit:
			# dep: nb: this relies on the data formatting in the bf2demo filenames
			# if you have other
			#print 'deleting %s' % (files[0])
			ftp.delete(files[0])
			del files[0]

		# bye bye
		ftp.quit()

	except Exception, detail:
		import traceback
		log = open('rotate_demo_err.txt', 'w')
		ex = sys.exc_info()
		traceback.print_exception(ex[0], ex[1], ex[2], 16, log)
		log.write('\n')
		log.close()
		sys.exit(1)