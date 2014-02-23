"""
File: mips_to_irom.py
Author: Charles Guan
Last Edit: 2014-02-22
---------------------
This module converts MIPS assembly code (*.s) into Verilog IROM format (*.v).

Input:
    MIPS assembly code

Output:
    Verilog IROM file.
"""

# Global variables defining lines of text to write
HEADER = [
'// Custom IROM with self-playing Pong',
'`include "mips_defines.v"',
'`define ADDR_WIDTH 9',
'`define INSTR_WIDTH 32',
'`define NUM_INSTR 512',
'',
'module irom (',
'    input [`ADDR_WIDTH-1:0] addr,',
'    output wire [`INSTR_WIDTH-1:0] dout',
');',
'',
'    wire [`INSTR_WIDTH-1:0] memory [`NUM_INSTR-1:0];',
'    assign dout = memory[addr];',
'',
]
FOOTER = [
'',
'endmodule',
]

def main():
    mips_file = raw_input('Path to MIPS input file: ')
    irom_file = raw_input('Path to IROM output file: ')
    instr_num = 0
    with open (irom_file, 'wb') as wf:
        wf.writelines(HEADER)
        
        with open (mips_file, 'rb') as rf:
            for instr in rf.readlines():
                # Write nothing for whitespace or comment lines
                if not (instr.isspace() or instr[0] == '#'):  
                    wf.write(mips2irom(instr, instr_num))
                    instr_num += 1
                 
                 
                 
        

        wf.writelines(FOOTER)

# It might be a good idea to think of both as CSV files and read them as such.
#TODO: formatting should all og in one function. pre-parse

# Translates a memory access (lw or sw) to Verilog
def mem_format(instr, instr_num):
    """Returns the translated I-format memory access instruction
    
    Translates an I-format assembly language memory access instruction (lw or
    sw)into Verilog IROM format. The instruction should not contain comments.
    
    Args:
        instr (string): An assembly language I-format memory access instruction,
        formatted without comments. Example below:
        sw    $s0, 24($sp)     
        instr_num (int): The current instruction number to be written
    
    Returns:
        verilog_instr (string): Verilog IROM format of instr. Above example
        translated below:
        assign memory[6]={`SW,`SP,`S0,16'd24};
    """
    formatted_instr = instr.upper().replace(',', '').replace('$','`')
    mem_type, rt, offset_rs = formatted_instr.split()
    sign, offset = split_sign(offset_rs.partition("(")[0])
    verilog_instr = "    assign memory[%d]={%s,%s,%s,%s16'd%d};" % (instr_num, mem_type, offset_rs[-4:-1], rt, sign, offset_val)
    return verilog_instr

def branch_format(instr, instr_num):
    """Returns the translated I-format branch instruction
    
    Translates an I-format assembly language branch instruction into Verilog IROM
    format. The instruction should not contain comments.
    
    Args:
        instr (string): An assembly language I-format branch instruction,
        formatted without comments. Example below:
        bne   $t2, $zero, game_loop
        instr_num (int): The current instruction number to be written
    
    Returns:
        verilog_instr (string): Verilog IROM format of instr. Above example
        translated below:
        assign memory[24]={`BNE,`T2,`ZERO,`GAME_LOOP-16'd25};
        We must subtract the instr_num (24) and 1 because of relative addresses
        while branching
    """
    formatted_instr = instr.upper().replace(',', '').replace('$','`')
    branch_type, rs, rt, label = formatted_instr.split()
    verilog_instr = "    assign memory[%d]={`%s,%s,%s,`%s-16'd%d};" % (instr_num,branch_type,rs,rt,label,instr_num+1)
    return verilog_instr

def i_format(instr, instr_num):
    """Returns the translated I-format instruction
    
    Translates an I-format assembly language ALU instruction into Verilog IROM
    format. The instruction should not contain comments.
    
    Args:
        instr (string): An assembly language I-format ALU instruction,
        formatted without comments. Example below:
        addiu $t0, $zero, -10
        instr_num (int): The current instruction number to be written
    
    Returns:
        verilog_instr (string): Verilog IROM format of instr. Above example
        translated below:
        assign memory[13]={`ADDIU,`ZERO,`T0, -16'd10};
    """
    formatted_instr = instr.upper().replace(',', '').replace('$','`')
    i_type, rt, rs imm = formatted_instr.split()
    sign, imm = split_sign(imm)
    verilog_instr = "    assign memory[%d]={`%s,%s,%s,%s16'd%d};" % (instr_num,i_type,rs,rt,sign,imm)
    return verilog_instr

def shift_format(instr, instr_num):
    """Returns the translated R-format shift instruction
    
    Translates a R-format assembly language shift instruction into Verilog IROM
    format. The instruction should not contain comments.
    
    Args:
        instr (string): An assembly language R-format shift instruction,
        formatted without comments. Example below:
        srl   $t0, $s0, 1       
        instr_num (int): The current instruction number to be written
    
    Returns:
        verilog_instr (string): Verilog IROM format of instr. Above example
        translated below:
        assign memory[507]={`SPECIAL,`NULL,`S0,`T0,5'd1,`SRL};
    """
    formatted_instr = instr.upper().replace(',', '').replace('$','`')
    shift_type, rd, rt, shamt = formatted_instr.split()
    verilog_instr = "    assign memory[%d]={`SPECIAL,`NULL,%s,%s,5'd%s,`%s};\n" % (instr_num,rt,rd,shamt,shift_type)
    return verilog_instr

def r_format(instr, instr_num): 
    """Returns the translated R-format instruction
    
    Translates a R-format assembly language instruction into Verilog IROM
    format. The instruction should not contain comments.
    NOT used for instructions using shamt, such as srl and sll
    
    Args:
        instr (string): An assembly language R-format instruction, formatted
        without comments. Example below:
        add   $a0, $s0, $zero
        instr_num (int): The current instruction number to be written
    
    Returns:
        verilog_instr (string): Verilog IROM format of instr. Above example
        translated below:
        assign memory[  7] = {`SPECIAL,`S0,`ZERO,`A0,5'd0,`ADD};
    """
    formatted_instr = instr.upper().replace(',', '').replace('$','`')
    r_type, rd, rs, rt = formatted_instr.split()
    verilog_instr = "    assign memory[%d]={`SPECIAL,%s,%s,%s,`NULL,`%s};\n" % (instr_num,rs,rt,rd,r_type)
    return verilog_instr

def j_format(instr, instr_num):
    """Returns the translated J-format instruction
    
    Translates a J-format assembly language instruction into Verilog IROM
    format. The instruction should not conain comments.
    
    Args:
        instr (string): An assembly language J-format instruction, formatted
        without comments. Example below:
        jal   write_byte 
        instr_num (int): The current instruction number to be written
    
    Returns:
        verilog_instr (string): Verilog IROM format of instr. Example below:
        assign memory[481] = {`JAL,`WRITE_BYTE};
    """
    jump_type, label = instr.upper().split()
    verilog_instr = "    assign memory[%d]={`%s,`%s};\n" % (instr_num,jump_type.upper(),label)
    return verilog_instr

def label(instr, instr_num):
    """Returns a NOP instruction with an associated define statement for label
    
    Translates an assembly language label into Verilog IROM no operation with
    an associated define statement for the label.
    
    Args:
        instr (string): An assembly language label. Example below:
        write_byte:
        instr_num (int): The current instruction number to be written
    
    Returns:
        verilog_instr (string): Verilog IROM format of no op and label define.
        Example below:
        assign memory[481] = {`NOP};
        `define WRITE_BYTE 481
    """
    verilog_instr = "    assign memory[%d]={`NOP};\n" % instr_num
    verilog_instr += "`define %s %d\n" % (instr[:-1].upper(), instr_num)
    return verilog_instr

def split_sign(num):
    num_copy = int(num)
    if num_copy < 0:
        sign = "-"
    else:
        sign = "+"
    return sign, abs(num_copy)

if __name__ == '__main__':
    main()
