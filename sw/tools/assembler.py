OPCODE_MAP = {
    "LOAD":  "0000",
    "STORE": "0001",
    "ADD":   "0010",
    "SUB":   "0011",
    "CMP":   "0100",
    "LOADI": "0101",
    "ADDI":  "0110",
    "CMPI":  "0111",
    "JMP":   "1000",
    "JZ":    "1001",
    "JNZ":   "1010",
    "NOP":   "1011",
    "OUT":   "1100",
    "IN":    "1101",
    "reserve 1":  "1110",
    "ADDITION":  "1111"  
}

EXT_FUNCT_MAP = {
    "SHL": "0000",
    "SHR": "0001",
    "AND": "0010"
}

label_map = {}

def assemble_line (cmd, operand):
    if operand in label_map:
        dec_val = label_map[operand]
    else:
        dec_val = int(operand, 0)

    if cmd in EXT_FUNCT_MAP:
        opcode_bin = "1111"
        funct_bin = EXT_FUNCT_MAP[cmd]
        reserved_bin = "000000000000"  # 12-bit 0
        operand_bin = format (dec_val, '012b')
        bin_32 = opcode_bin + funct_bin + reserved_bin + operand_bin
    

    elif cmd in ["LOAD","STORE","ADD","SUB","CMP"]:
        opcode_bin = OPCODE_MAP[cmd]
        reserved_bin = "0000000000000000" # 16-bit 0
        operand_bin = format (dec_val, '012b')
        bin_32 = opcode_bin + reserved_bin + operand_bin

    elif cmd in ["LOADI","ADDI","CMPI"]:
        opcode_bin = OPCODE_MAP[cmd]
        operand_bin = format (dec_val, '028b')
        bin_32 = opcode_bin + operand_bin
    
    elif cmd in ["JMP", "JZ", "JNZ"]:
        opcode_bin = OPCODE_MAP[cmd]
        reserved_bin = "0000000000000000" # 16-bit 0'
        operand_bin = format (dec_val, '012b')        
        bin_32 = opcode_bin + reserved_bin + operand_bin

    elif cmd in ["NOP"]:
        opcode_bin = OPCODE_MAP[cmd]
        reserved_bin = "0000000000000000000000000000" # 28-bit 0
        bin_32 = opcode_bin + reserved_bin
    
    elif cmd in ["OUT", "IN"]:
        opcode_bin = OPCODE_MAP[cmd]
        reserved_bin = "000000000000000000000000" # 24-bit 0
        operand_bin = format (dec_val, '04b')        
        bin_32 = opcode_bin + reserved_bin + operand_bin
    
    return format(int(bin_32,2),'08X')

with open ("doorlock.asm","r",encoding="utf-8") as file:
    current_address = 0
    for line in file:
        clean_line = line.split(';')[0].strip()
        if not clean_line: continue

        parts = clean_line.split()
        cmd = parts[0]
        operand = parts[1] if len(parts) > 1 else "0"

        if cmd == "ORG":
            new_address = parts[1]
            current_address = int (new_address, 16)
            continue


        if len(parts) == 1 and clean_line.endswith (":"):
            label_name = clean_line[:-1]
            label_map[label_name] = current_address
        else:
            current_address += 1

with open ("doorlock.asm","r",encoding="utf-8") as file:
    current_address = 0
    machine_codes = {}
    for line in file:
        clean_line = line.split(';')[0].strip()

        if not clean_line or clean_line.endswith(":"):
            continue

        parts = clean_line.split()

        cmd = parts[0]
        operand = parts[1] if len(parts) > 1 else "0"

        if cmd == "ORG":
            new_address = parts[1]
            current_address = int (new_address, 16)
            continue

        elif cmd in OPCODE_MAP or cmd in EXT_FUNCT_MAP:
            trans_machine_code = assemble_line (cmd, operand)
            machine_codes[current_address] = trans_machine_code
            current_address += 1
        


if machine_codes:
    max_addr = max(machine_codes.keys())

    with open ("doorlock.coe", "w") as f:
        f.write("memory_initialization_radix=16;\n")
        f.write("memory_initialization_vector=\n")

        for i in range(max_addr + 1):
            code = machine_codes.get(i,"00000000")

            if i == max_addr:
                f.write (code + ";")
            else:
                f.write (code + ",\n")