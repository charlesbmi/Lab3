//=============================================================================
// EE108B Lab 3
//
// Decode module. Determines what to do with an instruction.
//=============================================================================

`include "mips_defines.v"

module decode (
    input [31:0] pc,
    input [31:0] instr,
    input [31:0] rs_data_in,
    input [31:0] rt_data_in,
    input [4:0] forwarded_reg_addr_mem,
    input [31:0] forwarded_data_mem,
    input [4:0] forwarded_reg_addr_alu,
    input [31:0] forwarded_data_alu,
    input [5:0] op_prev,
    input memory_read,

    output wire [4:0] reg_write_addr,
    output wire jump_branch,
    output wire jump_target,
    output wire jump_reg,
    output wire [31:0] jr_pc,
    output reg [3:0] alu_opcode,
    output wire [31:0] alu_op_x,
    output wire [31:0] alu_op_y,
    output wire mem_we,
    output wire [31:0] mem_write_data,
    output wire mem_read,
    output wire reg_we,
    output wire [4:0] rs_addr,
    output wire [4:0] rt_addr,

    output wire stall,
    output wire [5:0] op_out
);

//******************************************************************************
// instruction field
//******************************************************************************

    wire [5:0] op = instr[31:26];
    assign rs_addr = instr[25:21];
    assign rt_addr = instr[20:16];
    assign op_out = op;
    wire [4:0] rd_addr = instr[15:11];
    wire [4:0] shamt = instr[10:6];
    wire [5:0] funct = instr[5:0];
    wire [15:0] immediate = instr[15:0];

    wire [31:0] rs_data, rt_data;
    wire [31:0] alu_op_x_initial;
    wire [31:0] alu_op_y_initial;
    wire [31:0] alu_op_x_temp;
    wire [31:0] alu_op_y_temp;

//******************************************************************************
// branch instructions decode
//******************************************************************************

    wire isBEQ  = (op == `BEQ);
    wire isBGEZ = (op == `BLTZ_GEZ) & ((rt_addr == `BGEZ) | (rt_addr == `BGEZAL));
    wire isBGTZ = (op == `BGTZ) & (rt_addr == 5'b00000);
    wire isBLEZ = (op == `BLEZ) & (rt_addr == 5'b00000);
    wire isBLTZ = (op == `BLTZ_GEZ) & ((rt_addr == `BLTZ) | (rt_addr == `BLTZAL));
    wire isBNE  = (op == `BNE);
    wire isBranchLink = (isBGEZ & (rt_addr == `BGEZAL)) | (isBLTZ & (rt_addr == `BLTZAL));
    

//******************************************************************************
// jump instructions decode
//******************************************************************************

    wire isJ    = (op == `J);
    wire isJAL  = (op == `JAL);
    wire isJALR = (op == `SPECIAL) & (funct == `JALR);  
    wire isJR   = (op == `SPECIAL) & (funct == `JR);
    
    // determine if the next pc will need to be stored
    wire isLink = isJALR | isJAL | isBranchLink;

//******************************************************************************
// shift instruction decode
//******************************************************************************

    wire isSLL = (op == `SPECIAL) & (funct == `SLL);
    wire isSRA = (op == `SPECIAL) & (funct == `SRA);
    wire isSRL = (op == `SPECIAL) & (funct == `SRL);
    wire isSLLV = (op == `SPECIAL) & (funct == `SLLV);
    wire isSRAV = (op == `SPECIAL) & (funct == `SRAV);
    wire isSRLV = (op == `SPECIAL) & (funct == `SRLV);
    
    wire isShiftImm = isSLL | isSRA | isSRL;
    wire isShift = isShiftImm | isSLLV | isSRAV | isSRLV;

//******************************************************************************
// ALU instructions decode / control signal for ALU datapath
//******************************************************************************
    
    always @* begin
        casex({op, funct})
            {`ADDI, `DC6}:      alu_opcode = `ALU_ADD;
            {`ADDIU, `DC6}:     alu_opcode = `ALU_ADDU;
            {`SLTI, `DC6}:      alu_opcode = `ALU_SLT;
            {`SLTIU, `DC6}:     alu_opcode = `ALU_SLTU;	
            {`ANDI, `DC6}:      alu_opcode = `ALU_AND;
            {`ORI, `DC6}:       alu_opcode = `ALU_OR;
            {`XORI, `DC6}:      alu_opcode = `ALU_XOR;
            {`LW, `DC6}:        alu_opcode = `ALU_ADD;
            {`SW, `DC6}:        alu_opcode = `ALU_ADD;
            {`BEQ, `DC6}:       alu_opcode = `ALU_SUBU;
            {`BNE, `DC6}:       alu_opcode = `ALU_SUBU;
            {`SPECIAL, `ADD}:   alu_opcode = `ALU_ADD;
            {`SPECIAL, `ADDU}:  alu_opcode = `ALU_ADDU;
            {`SPECIAL, `SUB}:   alu_opcode = `ALU_SUB;
            {`SPECIAL, `SUBU}:  alu_opcode = `ALU_SUBU;
            {`SPECIAL, `AND}:   alu_opcode = `ALU_AND;
            {`SPECIAL, `OR}:    alu_opcode = `ALU_OR;
            {`SPECIAL, `XOR}:   alu_opcode = `ALU_XOR;
            {`SPECIAL, `NOR}:   alu_opcode = `ALU_NOR;
            {`SPECIAL, `SLT}:   alu_opcode = `ALU_SLT;
            {`SPECIAL, `SLTU}:  alu_opcode = `ALU_SLTU;
            {`SPECIAL, `SLL}:   alu_opcode = `ALU_SLL;
            {`SPECIAL, `SRL}:   alu_opcode = `ALU_SRL;
            {`SPECIAL, `SRA}:   alu_opcode = `ALU_SRA;
            {`SPECIAL, `SLLV}:  alu_opcode = `ALU_SLL;
            {`SPECIAL, `SRLV}:  alu_opcode = `ALU_SRL;
            {`SPECIAL, `SRAV}:  alu_opcode = `ALU_SRA;
            // compare rs data to 0, only care about 1 operand
            {`BGTZ, `DC6}:      alu_opcode = `ALU_PASSX;
            {`BLEZ, `DC6}:      alu_opcode = `ALU_PASSX;
            {`BLTZ_GEZ, `DC6}: begin
                if (isBranchLink)
                    alu_opcode = `ALU_PASSY; // pass link address for mem stage
                else
                    alu_opcode = `ALU_PASSX;
            end
            // pass link address to be stored in $ra
            {`JAL, `DC6}:       alu_opcode = `ALU_PASSY;
            {`SPECIAL, `JALR}:  alu_opcode = `ALU_PASSY;
            // or immediate with 0
            {`LUI, `DC6}:       alu_opcode = `ALU_PASSY;
            default:            alu_opcode = `ALU_PASSX;
    	endcase
    end

//******************************************************************************
// Compute value for 32 bit immediate data
//******************************************************************************

    wire use_imm = &{op != `SPECIAL, op != `BNE, op != `BEQ}; // where to get 2nd ALU operand from: 0 for RtData, 1 for Immediate
    
    wire [31:0] imm_sign_extend = {{16{immediate[15]}}, immediate};  
    wire [31:0] imm_zero_extend = {16'b0, immediate};	
    wire [31:0] imm_upper = {immediate, 16'b0};
    
    reg [31:0] imm;
    always @* begin
        if (op == `LUI)
            imm = imm_upper;
        else if (|{op == `ORI, op == `ANDI, op == `XORI})
            imm = imm_zero_extend;
        else
            imm = imm_sign_extend;
    end

//******************************************************************************
// forwarding and stalling logic
//******************************************************************************

    assign rs_data = rs_data_in;
    assign rt_data = rt_data_in;
    
    // these signals will automatically be set to the forwarded versions
    // once you have implemented forwarding in general
    assign jr_pc = alu_op_x_initial;
    assign mem_write_data = alu_op_y_initial;

	assign alu_op_x_temp = ((forwarded_reg_addr_mem === rs_addr) && |rs_addr)?forwarded_data_mem: rs_data;

	assign alu_op_y_temp = ((forwarded_reg_addr_mem === rt_addr) && |rt_addr)? forwarded_data_mem: rt_data;

	assign alu_op_x_initial = ((forwarded_reg_addr_alu === rs_addr) && |rs_addr)? forwarded_data_alu: alu_op_x_temp;
	assign alu_op_y_initial = ((forwarded_reg_addr_alu === rt_addr) && |rt_addr)?forwarded_data_alu: alu_op_y_temp;

	assign stall = ((op_prev === `LW) & (|rs_addr) & ((forwarded_reg_addr_alu === rs_addr) | (forwarded_reg_addr_alu === rt_addr)))? 1'b1: 1'b0;


//******************************************************************************
// Determine ALU inputs and register writeback address
//******************************************************************************

    // for shift operations, use either shamt field or lower 5 bits of rs
    // otherwise use rs
    wire [31:0] shift_amount = isShiftImm ? shamt : rs_data[4:0];
    assign alu_op_x = isShift ? shift_amount : alu_op_x_initial;
    		
    // for link operations, use next pc (current pc + 4)
    // for immediate operations, use Imm
    // otherwise use rt
    
    assign alu_op_y = isLink ? pc + 4'h8 : (use_imm ? imm : alu_op_y_initial);
    assign reg_write_addr = isLink ? `RA : (use_imm ? rt_addr : rd_addr);
    
    // determine when to write back to a register (any operation that isn't a branch, jump, or store)
    assign reg_we = ~|{mem_we, isJ, isJR, isBGEZ, isBGTZ, isBLEZ, isBLTZ, isBNE, isBEQ};
  
//******************************************************************************
// Memory control
//******************************************************************************
    assign mem_we = (op == `SW);    // write to memory
    assign mem_read = (op == `LW);    // use memory data for writing to register


//******************************************************************************
// Forwarding Control
//******************************************************************************


//******************************************************************************
// Branch resolution
//******************************************************************************
    
    wire isEqual = alu_op_x_initial == alu_op_y_initial;
    wire isZero = ~|rs_data;
    wire isNeg = rs_data[31];
    wire isPos = ~(isZero | isNeg);

    assign jump_branch = |{isBEQ & isEqual,
                           isBNE & ~isEqual,
                           isBGEZ & ~isNeg,
                           isBGTZ & isPos,
                           isBLEZ & ~isPos,
                           isBLTZ & isNeg};
    
    assign jump_target = isJ | isJAL;
    assign jump_reg = isJALR | isJR;

endmodule
