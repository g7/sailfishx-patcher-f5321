sailfishx-patcher-f5321
=======================

Important note
--------------

I'm moving away from Sailfish OS, and this means that I won't be able to support this project anymore.  
This compatibility layer has been designed not to be on the way of official OTA upgrades. As such,
I do expect patched devices to run for as long as Jolla supports the base device (Xperia X).

I will continue to accept Pull Requests.

Thanks to everyone who contributed with testing and donations. It has been a blast!

Introduction
------------

This repository contains a tool that permits to apply the [Xperia X Compact compatibility layer](https://github.com/g7/droid-compat-f5321)
on top of official Sailfish X images.

To keep things simple and clean, this guide will show how to patch inside a Vagrant environment.  
You can run it as well without vagrant, but is not recommended. Please read anyway the Vagrantfile to
get the required dependencies.

The following may also work on Windows and macOS machines, but it hasn't been tested (testers welcome!).

Frequently Asked Questions
--------------------------

#### Q: (NEW IN 3.4 "Pallas-Yllästunturi"): Can I disable /home encryption at boot?

A: Since Sailfish OS 3.4 "Pallas-Yllästunturi", /home partition encryption is enabled by default.

While this is a good thing, the current, PIN-only implementation makes this pointless unless
an abnormally long PIN has been set.

This is further exacerbated by the fact that on Xperias at least, an unlocked bootloader
is required and so obtaining the LUKS header (which can be cracked in minutes with short
PIN codes) is easy for a potential adversary.

Thus, disabling encryption by default can be desirable. You can run the following command
to create the `config.sh` file that will be sourced by the patcher script, specifying that
encryption should be disabled:

    echo 'DISABLE_HOME_ENCRYPTION_AT_BOOT="yes"' > config.sh

Thanks to @teleshoes for their contribution.

#### Q: How does this thing work?

A: [droid-compat-f5321](https://github.com/g7/droid-compat-f5321) is a compatibility layer that I've developed
in order to use official Sailfish X images on the Xperia X Compact.

This layer works by overriding some hardware specific parts of the Xperia X adaptation with the ones of the
Xperia X Compact, and where the override operation is not applicable, the patched files are applied
via a diversion, using a rudimentary tool called [rpm-divert](https://github.com/g7/rpm-divert).

The kernel image is patched, so the whole official adaptation is working on the X Compact.

The kernel patch is done with another tool that I've developed, [yabit](https://github.com/g7/yabit).

#### Q: What Sailfish X images are supported?

A: Sailfish X for Xperia X Single Sim (F5121). Currently the following images have been patched successfully:

* Sailfish X F5121 2.1.3.7 "Kymijoki"
* Sailfish X F5121 2.1.4.14 "Lapuanjoki"
* Sailfish X F5121 2.2.0.29 "Mouhijoki"
* Sailfish X F5121 2.2.1.18 "Nurmonjoki"
* Sailfish X F5121 3.0.0.8 "Lemmenjoki"
* Sailfish X F5121 3.0.1.11 "Sipoonkorpi"
* Sailfish X F5121 3.0.2.8 "Oulanka" (thanks to @f03el for their contribution)
* Sailfish X F5121 3.0.3.10 "Hossa"
* Sailfish X F5121 3.1.0.11 "Seitseminen"
* Sailfish X F5121 3.2.0.12 "Torronsuo"
* Sailfish X F5121 3.2.1.20 "Nuuksio"
* Sailfish X F5121 3.3.0.16 "Rokua" (thanks to @teleshoes for their contribution)
* Sailfish X F5121 3.4.0.24 "Pallas-Yllästunturi"

#### Q: What doesn't work?

A: The only things that don't work are:

  * USB OTG (the Xperia X kernel does not supply the driver for the USB Type-C controller of the X Compact)
  * Some secondary sensors (magnetometer, gyroscope, pressure, step counter). This is temporary until I narrow down a battery drain issue I experienced with those.

#### Q: What about those secondary sensors?

##### Note

If you patched **before** 2018-09-09 and upgraded to 2.2.1 Early Access, there can be inconsistencies on
the secondary sensors diversions (i.e. the sensors show as diverted, but in reality they're not).

To fix that, run the following commands:

    devel-su
    zypper ref
    zypper in rpm-divert
    rpm-divert unapply --package droid-compat-f5321-hybris-libsensorfw-qt5
    rpm-divert apply --package droid-compat-f5321-hybris-libsensorfw-qt5

##### Answer

A: I have experienced spikes in CPU usage by sensorfwd during the early days of this patch. Those were hard
to reproduce, and I haven't had the time to properly debug them (it may very well be an issue of my device).

Disabling those sensors helped, and I haven't experienced the problem since.

Those sensors are disabled by default, and it's done with diversions made by the
droid-compat-f5321-hybris-libsensorfw-qt5 package (as far as I know, Sailfish OS 2.2.1
now allows to disable sensors from a configuration file, but a diversion is just as effective).

You can check if you have the diversions applied with the following command:

    rpm-divert list --package droid-compat-f5321-hybris-libsensorfw-qt5

You can unapply them all (and thus restoring their functionality) using

    devel-su rpm-divert unapply --package droid-compat-f5321-hybris-libsensorfw-qt5

You can also selectively unapply them with

    devel-su rpm-divert unapply --source /usr/lib/sensord-qt5/libhybrisgyroscopeadaptor-qt5.so

(this will re-enable the gryoscope sensor, change accordingly with what you want to enable)

If after enabling the sensors you experience the aforementioned battery drain, you can reapply
every diversion (and thus disabling the secondary sensors) using

    devel-su rpm-divert apply --package droid-compat-f5321-hybris-libsensorfw-qt5

**NOTE:** You need to restart the sensors daemon after applying/unapplying diversions. You can
do so using

    devel-su systemctl restart sensorfwd

#### Q: Is it stable?

A: I'm using a patched image on my daily driver since April 2018. Before I was running a custom-built
2.1.2 image and I've yet to notice differences stability-wise.

#### Q: Do I have access to the Sailfish X licensed content (aliendalvik, text prediction, etc)?

A: If your Sailfish X license is valid, yes. Jolla will see your device as a standard, single-sim, Xperia X.

Alien Dalvik and the other 3rd-party content work fine.

#### Q: Are Sailfish Over The Air (OTA) updates safe?

A: They should be. The compatibility layer has been developed with OTAs in mind.

#### Q: Does this mean that I can run official Sailfish X on other Xperia devices?

A: No. The Xperia X and the Xperia X Compact are so similar that an approach similar to mine
can work. Other Xperias (X Performance, XZ*) do not share anything about the hardware so unfortunately
things can't work.

Requirements
------------

* An official Sailfish X image, for the Xperia X Single Sim (F5121)
* [vagrant](https://www.vagrantup.com)
* [virtualbox](https://www.virtualbox.org)
* ~15 GB of disk space

How to patch
------------

First of all, clone this repository and its submodules:

If you are on a Windows host, you need to ensure that the line endings are correct.
Setting `core.autocrlf` to `false` globally will save some headaches:

	git config --global core.autocrlf false

Then you can clone the repository:

	git clone https://github.com/g7/sailfishx-patcher-f5321.git
	cd sailfishx-patcher-f5321
	git submodule init
	git submodule update

You can reset `core.autocrlf` to `true` if you changed it before:

	git config --global core.autocrlf true

Then, install (if you haven't) the vagrant-vbguest plugin:

	vagrant plugin install vagrant-vbguest

Bring up the vagrant environment. This might take a while:

	vagrant up

If everything went well, copy the official Sailfish X image to the `sailfishx-patcher-f5321` directory,
then start the actual patching process:

	vagrant ssh -c "/vagrant/patch.sh -a f5321 -i /vagrant/Sailfish*.zip"

Note: **Do not** change the "`/vagrant`" directory! It already references the `sailfishx-patcher-f5321`
directory where you copied the zip file.

If everything is successful, you should get a patched zipfile in the very same directory.

You can use the official Sailfish X installation instructions to flash to your device. Enjoy!

To destroy the vagrant image, simply execute

	vagrant destroy
