#include <stdlib.h>
#include <iostream>
#include <fstream>
#include <iomanip>
#include <list>
#include "Vcpu_cache_sdram_tb.h"
#include "verilated.h"
#include "verilated_vcd_c.h"


static Vcpu_cache_sdram_tb *tb;
static VerilatedVcdC *trace;
static double timestamp = 0;

double sc_time_stamp() {
	return timestamp;
}

void tick(int c) {
	tb->clk_114 = c;
	tb->eval();
	trace->dump(timestamp);
	timestamp += 4.38;
}

void cpuWrite(int addr, int data)
{
	tb->cpuAddr = addr;
	tb->cpuWR = data;
	tb->cpuState = 3;
	while (!tb->clkena) {
		tick(1);
		tick(0);
	}
	tick(1);
	tick(0);
	tb->cpuState = 1;
}

int cpuRead(int addr, char d)
{
	tb->cpuAddr = addr;
	tb->cpuState = d ? 2 : 0;
	while (!tb->clkena) {
		tick(1);
		tick(0);
	}
	tick(1);
	tick(0);
	tb->cpuState = 1;
	return tb->cpuRD;
}

char basic_test() {
	char ok = 1;
	for (int i=0; i<16;i++) {
		cpuWrite(i,i);
		int dat = cpuRead(i,1);
		if (i != dat) {
			std::cout << "error at addr: " << i << ": " << dat << std::endl;
			ok = 0;
		}
	}
	return ok;
}

char random_test() {
	char ok = 1;
	std::list<int> addresses;
	std::cout << "memory random fill" << std::endl;
	for (int i=0; i<10000; i++)
	{
		int a = rand() & 0xfffffc;
		addresses.push_back(a);
		cpuWrite(a,a & 0xffff);
	}

	std::cout << "memory read back after random fill" << std::endl;
	for (std::list<int>::iterator it=addresses.begin(); it != addresses.end(); ++it)
	{
		int data = cpuRead(*it, 1);
		if ((*it & 0xffff) != data) {
			std::cout << "error: " << std::setw(8) << std::setfill('0') << std::hex << *it << ": " << data << std::dec << std::endl;
			ok = 0;
		}
	}
	return ok;
}

int main(int argc, char **argv) {

	// Initialize Verilators variables
	Verilated::commandArgs(argc, argv);
//	Verilated::debug(1);
	Verilated::traceEverOn(true);
	trace = new VerilatedVcdC;

	// Create an instance of our module under test
	tb = new Vcpu_cache_sdram_tb;
	tb->trace(trace, 99);
	trace->open("sdram.vcd");

	tb->reset = 0;
	tb->cpuL = 0;
	tb->cpuU = 0;
	tb->cpuLongWord = 0;
	tb->cpuState = 1;
	tb->cpuWR = 0xdead;
	tb->cpuAddr = 0;
	tick(1);
	tick(0);
	tick(1);
	tick(0);
	tb->reset = 1;
	tick(1);
	tick(0);

	if (basic_test())
		std::cout << "Basic test: OK" << std::endl;
	else
		std::cout << "Basic test: ERROR" << std::endl;

	if (random_test())
		std::cout << "Random test: OK" << std::endl;
	else
		std::cout << "Random test: ERROR" << std::endl;

	trace->close();

}
