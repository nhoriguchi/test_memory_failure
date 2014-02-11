#!/usr/bin/ruby

# Should be run by root

if ARGV.size == 0
  puts "Usage: #{$0} <vmname> <gpa> [-d]"
  exit
end

vmname = ARGV[0]
# assuming gpa is given in hex number
gpa = ARGV[1].nil? ? nil : ARGV[1].hex
debug = ARGV[2] == "-d"

pidfile = "/var/run/libvirt/qemu/#{vmname}.pid"
raise "VM #{vmname} not running" unless File.exist? pidfile
pid = File::open(pidfile) {|f| f.gets}
max = 0
vaddr = 0
File::open("/proc/#{pid}/maps").each do |line|
  if line =~ /(\w*)-(\w*) /
    size = ($2.hex - $1.hex)
    if size > max
      max = size
      vaddr = $1.hex
    end
  end
end

tmp = `virsh dommemstat #{vmname} | grep actual | awk '{print $2}'`.to_i
STDERR.puts "size is 0x#{max} (dommem 0x#{tmp*1024})\n" if debug == true
raise "Guest RAM is separated in Virtual space of qemu process" if max < tmp * 1024

if gpa.nil?
  tmp = `virsh dommemstat #{vmname} | grep actual | awk '{print $2}'`.to_i
  printf "size is 0x%x (dommem 0x%x)\n", max, tmp * 1024
  raise "Guest RAM is separated in Virtual space of qemu process" if max < tmp * 1024
  printf "vaddr of guest memory is [0x%x-0x%x] ([0x%x+0x%x] in pfn) \n" % [vaddr, vaddr+max, vaddr >> 12, max >> 12]
  exit
end

target = vaddr + (gpa << 12)
if debug == true
  STDERR.puts "vaddr of guest memory is [0x#{vaddr}-0x#{vaddr+max}] ([0x#{vaddr>>12}+0x#{max>>12}] in pfn) \n"
  STDERR.puts "HVASTART:#{vaddr>>12}\n"
  STDERR.puts "HVASIZE:#{max>>12}\n"
  STDERR.puts "target virtual address is #{target}\n"
end

pagemapfile = "/proc/#{pid}/pagemap"
io = open pagemapfile
io.seek((target >> 12) * 8, IO::SEEK_SET)
a = io.read 8
b = a.unpack("Q")[0] & 0xfffffffffff
corruptstr = "0x%x" % b
puts corruptstr
