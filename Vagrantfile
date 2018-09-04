# -*- mode: ruby -*-
# vi: set ft=ruby :

# If the box image is too old, the kernel headers referenced by
# the APT package list might not be available anymore... and that
# includes the currently installed kernel.
# This is a workaround, it really should be handled by vbguest...
if Vagrant.has_plugin?("vagrant-vbguest")
	class KernelUpgradeWorkaround < VagrantVbguest::Installers::Debian
		def install(opts=nil, &block)
			communicate.sudo("apt-get update", opts, &block)
			# Speed-up things with eatmydata
			communicate.sudo("apt-get install --yes eatmydata", opts, &block)
			communicate.sudo("eatmydata apt-get install --yes linux-image-amd64 linux-headers-amd64", opts, &block)
			communicate.sudo("reboot", opts, &block)

			# Wait
			restarted = false
			(0..5).each do |n|
				sleep(30)
				begin
					communicate.sudo("uname -r", opts, &block)
				rescue
					# Try again
					next
				else
					# End
					restarted = true
					break
				end
			end

			unless restarted
				# Uh oh
				raise "Unable to communicate with the VM after the reboot"
			end

			super
		end
	end
end

Vagrant.configure("2") do |config|
	config.vm.define :sailfish_image_patcher

	config.vm.box = "debian/stretch64"

	# Things do currently work as of SailfishOS 2.2.0 and the default
	# 10GB vmdk disk of the stretch64 box.
	# If you're getting out of space in the VM, install the 'vagrant-disksize'
	# plugin and uncomment the line below
	#config.disksize.size = "15G"

	# simg2img gets killed by OOM with the default memory size (512M)
	# To be on the safe side, I'm defaulting to 2048M.
	# You might try decreasing it. YMMV.

	# You might also increase the CPU count if you want. Just modify
	# and uncomment the v.cpus declaration below.

	config.vm.provider "virtualbox" do |v|
		v.memory = 2048
		#v.cpus = 4
	end

	# This is absolutely bonkers, but it seems that vagrant-vbguest (see
	# below) would not run "apt-get update" to refresh the package list,
	# so things might fail... Let's workaround this way, please forgive
	# me...
	if Vagrant.has_plugin?("vagrant-vbguest")
		config.vbguest.installer = KernelUpgradeWorkaround
	end

	# Force "virtualbox" as the synced folder type. Things are going to
	# get big so it's better to work directly on the shared folder.
	# This requires the guest additions installed.
	# You can install the "vagrant-vbguest" plugin before setting up
	# this image so that everything is hanlded by the plugin.
	# Nowadays you can simply use
	#    vagrant plugin install vagrant-vbguest
	# to install the plugin.
	config.vm.synced_folder ".",
		"/vagrant",
		type: "virtualbox"

	# Install required tools
	config.vm.provision "shell", inline: <<-SHELL
		apt-get update

		if [ ! -x "/usr/bin/eatmydata" ]; then
			apt-get install --yes eatmydata
		fi

		eatmydata apt-get install --yes \
			rsync \
			qemu-user-static \
			binfmt-support \
			simg2img \
			img2simg \
			lvm2 \
			pigz \
			python3 \
			unzip \
			zip

		eatmydata apt-get clean
		eatmydata apt-get autoclean
	SHELL

	config.vm.post_up_message = "Please see https://github.com/g7/sailfishx-patcher-f5321 on how to patch a Sailfish X image."
end
