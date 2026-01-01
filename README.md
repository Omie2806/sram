# 4-Way Set Associative Cache (Using LRU Policy)
A fully functional 4 way set associative cache implemented in system verilog and tested using icarus.

## Overview
This project features a 4 way set associative cache which uses LRU Policy for write-backs.
**Project status:** Completed and Verified.
**Development Time:** October - November 2024  
**Language:** SystemVerilog  

## Key features:
- **4-Way Set-Associative Architecture**
  - 256 sets with 4 ways per set
  - 16-word (64-byte) cache blocks
  - Total cache size: 32 KB

- **LRU Replacement Policy**
  - LRU implementation using counters
  - Efficient victim selection on cache misses
  - First-free replacement on write misses (Prefering free blocks over LRU count)

- **Write-Back Policy**
  - Dirty bit tracking per cache line
  - Write-back on eviction only
  - Reduced memory traffic

- **Write-Allocate Strategy**
  - Fetch block on write miss
  - Consistent with write-back policy
  - Improved spatial locality exploitation

  - **Comprehensive FSM Control**
  - 7-state finite state machine
  - Handles hits, misses, and evictions
  - Clean state transitions

### Cache Organization:

Total Size:    32 KB
Block Size:    64 bytes (16 words)
Associativity: 4-way
Number of Sets: 256
Address Width: 32 bits [31 : 0]
Data Width:    32 bits [31 : 0]

### Address Breakdown
No. of sets = 256, hence 8 bits required to uniquely express each set (2^8 = 256)
No. of words = 16 since 2^4 = 16 
Remaining MSBs are used for tag matching. 

```mermaid
flowchart TB
    A["32-bit Address<br/>[31:0]"]
    
    A --> B["Tag<br/>[31:14]<br/>18 bits"]
    A --> C["Set Index<br/>[13:6]<br/>8 bits"]
    A --> D["Word Offset<br/>[5:2]<br/>4 bits"]
    A --> E["Byte Offset<br/>[1:0]<br/>2 bits"]
    
    B --> F["Identifies unique<br/>memory block"]
    C --> G["Selects 1 of<br/>256 sets"]
    D --> H["Selects 1 of<br/>16 words in block"]
    E --> I["Byte within word<br/>(not used)"]
    
    style A fill:#e1f5ff,stroke:#333,stroke-width:2px
    style B fill:#ffe1e1,stroke:#333,stroke-width:2px
    style C fill:#e1ffe1,stroke:#333,stroke-width:2px
    style D fill:#fff3e1,stroke:#333,stroke-width:2px
    style E fill:#f0f0f0,stroke:#333,stroke-width:2px
```

(Last 2 bits used as BYTE OFFSET)

## 🔄 FSM State Machine

The cache controller uses a 7-state finite state machine to manage cache operations:

```mermaid
stateDiagram-v2
    [*] --> IDLE
    
    IDLE --> READ : ~write_en
    IDLE --> WRITE : write_en
    
    READ --> IDLE : cache hit
    READ --> READ_MISS : cache miss
    
    WRITE --> IDLE : cache hit
    WRITE --> GET_VICTIM : miss & all_ways_valid
    WRITE --> READ_MISS : miss & free_way_available
    
    READ_MISS --> GET_VICTIM : victim_dirty
    READ_MISS --> READ_FROM_MEM : victim_clean
    
    GET_VICTIM --> WRITE_BACK : victim_dirty
    GET_VICTIM --> READ_FROM_MEM : victim_clean
    
    WRITE_BACK --> READ_FROM_MEM
    
    READ_FROM_MEM --> IDLE : pending_write
    READ_FROM_MEM --> READ : normal_read
    
    note right of WRITE
        Write Miss Cases:
        1. Free way → READ_MISS
        2. All valid → GET_VICTIM
    end note
```

### State Transitions & Performance

**Read Hit:** `IDLE → READ → IDLE` (2 cycles)
- Fast path: Tag compare and data output

**Read Miss (clean victim):** `IDLE → READ → READ_MISS → READ_FROM_MEM → READ → IDLE` (~6 cycles)
- Fetch new block from memory, no writeback needed

**Read Miss (dirty victim):** `IDLE → READ → READ_MISS → GET_VICTIM → WRITE_BACK → READ_FROM_MEM → READ → IDLE` (~7 cycles)
- Writeback dirty victim, then fetch new block

**Write Hit:** `IDLE → WRITE → IDLE` (2 cycles)
- Update cache line, mark dirty

**Write Miss - Case 1 (free way available):** `IDLE → WRITE → READ_MISS → READ_FROM_MEM → IDLE` (~5 cycles)
- At least one invalid way exists
- Fetch block and write to free way
- No victim selection or writeback needed

**Write Miss - Case 2 (all ways valid, dirty victim):** `IDLE → WRITE → GET_VICTIM → WRITE_BACK → READ_FROM_MEM → IDLE` (~7 cycles)
- All ways valid, use LRU replacement
- Selected victim is dirty (dirty bit = 1)
- Writeback victim, then fetch new block

> **Note:** Cycle counts assume single-cycle memory access in simulation. In real hardware with DRAM, the miss penalty would be significantly higher.

### Control Signals

The FSM generates the following control signals:

- `read_true` - Asserted in READ state on cache hit
- `write_hit_true` - Asserted in WRITE state on cache hit  
- `write_back_true` - Asserted in WRITE_BACK state
- `read_from_main_mem_true` - Asserted in READ_FROM_MEM state

These signals control the cache datapath operations for each transaction.


## Verification & Results

### Test Coverage

The testbench includes 11 comprehensive test scenarios:

1. **Cold Start Read Miss** - Initial cache population
2. **Read Hit** - Same location access
3. **Different Offset Hit** - Within same block
4. **Fill All Ways** - Complete set population
5. **LRU Verification** - Replacement policy testing
6. **Write Hit** - Write-back behavior
7. **Write Miss** - Write-allocate policy
8. **Multiple Sets** - Set isolation verification
9. **Multi-Way Access** - Associativity testing
10.**Full Block Read** - All offsets in block
11.**Multi-Offset Write** - Multiple writes to same block


## Key Implementations

### LRU Replacement 

>replaces the least recently used block

function automatic integer get_replacement;
input [SET_WIDTH - 1 : 0] set_index;
    begin
    integer max;
    integer victim;
        max    = -1;
        victim = 0;

        for (integer i = 0; i < WAY; i++) begin
            if (LRU_COUNTER[set_index][i] > max) begin
                max    = LRU_COUNTER[set_index][i];
                victim = i;
            end
        end
        return victim;
    end
endfunction

### Free-Way selection

>override LRU when a write miss occurs and a free block/way is availabe

function automatic integer free_way;
input[SET_WIDTH - 1 : 0] set_index;
    begin
        for (integer i = 0; i < WAY; i++) begin
            if(VALID[set_index][i] == 1'b0) begin
                return i;
            end
        end
    end
endfunction

### Latch onto the address and data received (write)

>save the address and received that so that write backs and other multicycle operations can be performed 

latched_set    <= set;
latched_tag    <= tag;
latched_offset <= offset;
latched_data_in <= data_in;


### Critical Path Analysis

The critical path in the design is:
1. Tag comparison (parallel across 4 ways)
2. Hit detection (OR of 4 comparisons)
3. Way selection multiplexing
4. Data output

## Debugging Journey

### Challenge 1: Single-Cycle to Multi-Cycle Redesign

**Problem:** Initially designed the cache as a single-cycle memory system, which didn't properly model real cache behavior.

**Root Cause:** Misunderstanding of cache timing - hits and misses have different latencies.

**Solution:** Complete FSM redesign with 7 states to handle multi-cycle operations (hits, misses, writebacks).


### Challenge 2: Address Latching Timing

**Problem:** Not latching address and data early enough caused timing synchronization issues - operations were using stale or incorrect addresses.

**Root Cause:** Address was being captured in the wrong FSM state, causing offset and data misalignment.

**Solution:** Latch address and write data in IDLE state before transitioning to READ/WRITE states:
```systemverilog
IDLE: begin
    if (read_en || write_en) begin
        latched_set    <= set;
        latched_tag    <= tag;
        latched_offset <= offset;
        latched_data_in <= data_in;  // For writes
    end
end
```


### Challenge 3: Writeback Address Calculation

**Problem:** Dirty victim blocks were being written back to incorrect memory addresses.

**Root Cause:** Wasn't properly reconstructing full address from victim's tag and set index.

**Solution:** Correct address reconstruction:
```systemverilog
 victim_addr = {victim_tag, latched_set};
```


## What I Learned

### Technical Skills

- **FSM Design:** Importance of proper state transitions and timing
- **Replacement Policies:** LRU implementation and hardware costs
- **Write Policies:** Write-back vs write-through trade-offs
- **Timing Analysis:** Critical importance of signal latching timing


## Future implementation

- **Psuedo LRU Behaviour:** To reduce hardware complexity for synthesis
- **Performing other operations while handling misses:** Perform reads and writes for other addresses while handling previous misses
- **Performance Counters**: Add hit/miss rate monitoring 
- **Multi-Level Cache**: Add L2 cache support
- **Integration with a RISC-V CPU**

##  Author

**[Om Gupta]**
- GitHub: [@Omie2806](https://github.com/Omie2806)
- Email: omgupta2806@gmail.com

*Electronics Engineering*  
*VJTI Mumbai*


## Acknowledgments

- Inspired by Digital System design by Harris and Harris
- Digital System design NPTEL course 
- Claude AI for testbenches and help with debugging
