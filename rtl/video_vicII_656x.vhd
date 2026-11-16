-- -----------------------------------------------------------------------
--
--                                 FPGA 64
--
--     A fully functional commodore 64 implementation in a single FPGA
--
-- -----------------------------------------------------------------------
-- Peter Wendrich (pwsoft@syntiac.com)
-- http://www.syntiac.com/fpga64.html
-- -----------------------------------------------------------------------
--
-- VIC-II - Video Interface Chip no 2
--
-- -----------------------------------------------------------------------
-- Dar 08/03/2014 : shift hsync to sprite #3
-- -----------------------------------------------------------------------
-- VIC-IIe (C128) changes by Erik Scheffers
--
-- VIC-IIx (C128plus) extensions (enabled only after the unlock sequence $A5,$96 to $D03F):
--   * 16 additional sprites (8..23), hardware multiplexed: sprites n, n+8 and
--     n+16 share DMA slot n. A free slot goes to the lowest numbered sprite
--     that starts on that line. Sprite pointers for 8..15 are at
--     screen+$3F0..$3F7 and for 16..23 at screen+$3E8..$3EF (the unused bytes
--     after the 1000 screen codes). No additional memory cycles are used.
--   * Programmable palette: the 16 colour indices map to 8-bit hue/luminance
--     values (256 colours) when PALEN is set.
--   * Hardware scrolling: programmable screen start address and row length,
--     and a separately placeable sprite pointer table. Start and row length
--     are latched at the start of each frame.
--   * Extension register banks at $D040-$D07F and $D080-$D0BF (see the
--     register list in writeRegisters).
--   While locked the chip behaves exactly like a stock VIC-IIe and the
--   registers are mirrored every 64 bytes as before.

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.ALL;

entity video_vicii_656x is
	generic (
		registeredAddress : boolean;
		emulateRefresh : boolean := false;
		emulateLightpen : boolean := false;
		emulateGraphics : boolean := true
	);
	port (
		clk: in std_logic;
		-- phi = 0 is VIC cycle
		-- phi = 1 is CPU cycle (only used by VIC when BA is low)
		phi : in std_logic;
		enaData : in std_logic;
		enaPixel : in std_logic;

		baSync : in std_logic;
		ba: out std_logic;
		ba_dma : out std_logic;

		mode6569 : in std_logic; -- PAL 63 cycles and 312 lines
		mode6567old : in std_logic; -- old NTSC 64 cycles and 262 line
		mode6567R8 : in std_logic; -- new NTSC 65 cycles and 263 line
		mode6572 : in std_logic; -- PAL-N 65 cycles and 312 lines

		turbo_en   : in  std_logic;
		turbo_state: out std_logic;

		vic2e : in std_logic := '0'; -- C128 VIC-IIe
		variant : in std_logic_vector(1 downto 0); -- 00 - NMOS, 01 - HMOS, 10 - old HMOS
		reset : in std_logic;
		cs : in std_logic;
		we : in std_logic;
		lp_n : in std_logic;

		aRegisters: in unsigned(7 downto 0);
		diRegisters: in unsigned(7 downto 0);

		di: in unsigned(7 downto 0);
		diColor: in unsigned(3 downto 0);
		do: out unsigned(7 downto 0);

		vicAddr: out unsigned(13 downto 0);
		irq_n: out std_logic;

		-- Video output
		hSync : out std_logic;
		vSync : out std_logic;
		colorIndex : out unsigned(3 downto 0);
		-- C128plus extended palette output: hue & luminance, valid when extColorEn = '1'
		extColor   : out unsigned(7 downto 0);
		extColorEn : out std_logic;
	   invertV : out std_logic;  -- YUV V-component inversion side-effect (VIC-IIe only)

		-- VIC-IIe only I/O pins
		ko : out unsigned(2 downto 0);

		-- Debug outputs
		debugX  : out unsigned(9 downto 0);
		debugY  : out unsigned(8 downto 0);
		vicRefresh : out std_logic;
		addrValid : out std_logic
	);
end entity;

architecture rtl of video_vicii_656x is
	type vicCycles is (
		cycleRefresh1, cycleRefresh2, cycleRefresh3, cycleRefresh4, cycleRefresh5,
		cycleIdle1, cycleIdle2,
		cycleChar,
		cycleCalcSprites, cycleSpriteBa1, cycleSpriteBa2, cycleSpriteBa3,
		cycleSpriteA, cycleSpriteB
	);
	subtype ColorDef is unsigned(3 downto 0);
	type MFlags is array(0 to 7) of boolean;
	type MXdef is array(0 to 7) of unsigned(8 downto 0);
	type MYdef is array(0 to 7) of unsigned(7 downto 0);
	type MXdef24 is array(0 to 23) of unsigned(8 downto 0);
	type MYdef24 is array(0 to 23) of unsigned(7 downto 0);
	type spriteColorsDef24 is array(23 downto 0) of unsigned(3 downto 0);
	type ownDef is array(0 to 7) of unsigned(1 downto 0);
	type paletteDef is array(0 to 15) of unsigned(7 downto 0);
	type MCntDef is array(0 to 7) of unsigned(5 downto 0);
	type MPixelsDef is array(0 to 7) of unsigned(23 downto 0);
	type MCurrentPixelDef is array(0 to 7) of unsigned(1 downto 0);
	type charStoreDef is array(38 downto 0) of unsigned(11 downto 0);
	type spriteColorsDef is array(7 downto 0) of unsigned(3 downto 0);
	type pixelColorStoreDef is array(7 downto 0) of unsigned(3 downto 0);

	constant PIX_DELAY : integer := 6;

-- State machine
	signal lastLineFlag : boolean; -- True for on last line of the frame.
	signal vicCycle : vicCycles := cycleRefresh1;
	signal sprite : unsigned(2 downto 0) := "000";
	signal shiftChars : boolean;
	signal shiftLoadEna : boolean;
	signal idle: std_logic := '1';
	signal rasterIrqDone : std_logic; -- Only one interrupt each rasterLine
	signal rasterEnable: std_logic;

-- BA signal
   signal aec : std_logic;
	signal badLine : boolean; -- true if we have a badline condition
	signal baLoc : std_logic;
	signal baCnt : unsigned(2 downto 0);

	signal baChars : std_logic;
	signal baSprite04 : std_logic;
	signal baSprite15 : std_logic;
	signal baSprite26 : std_logic;
	signal baSprite37 : std_logic;
	signal baSpriteLast : std_logic;

-- Memory refresh cycles
   signal refresh : std_logic;
	signal refreshCounter : unsigned(7 downto 0);

-- User registers
	-- Sprite registers (C128plus: 24 logical sprites, 8..23 only usable when unlocked)
	signal MX : MXdef24; -- Sprite X
	signal MY : MYdef24; -- Sprite Y
	signal ME : unsigned(23 downto 0); -- Sprite enable
	signal MXE : unsigned(23 downto 0); -- Sprite X expansion
	signal MYE : unsigned(23 downto 0); -- Sprite Y expansion
	signal MPRIO : unsigned(23 downto 0); -- Sprite priority
	signal MCDelay : unsigned(23 downto 0); -- sprite multi color (register)

	-- C128plus sprite slot ownership: slot i shows sprite i ("00"), sprite i+8 ("01")
	-- or sprite i+16 ("10").
	-- own is the DMA owner, it can change in cycles 55/56 when the slot is free.
	-- ownDisp is the display owner, it follows own at the slot's p-access, the
	-- same moment new sprite data starts arriving, so a sprite still being drawn
	-- in the right border keeps its own position and colours.
	-- The s* signals are the register values of the sprite that owns each slot.
	signal own : ownDef := (others => "00");
	signal own_next : ownDef;
	signal ownDisp : ownDef := (others => "00");
	signal sMX : MXdef;
	signal sMY : MYdef;
	signal sME : unsigned(7 downto 0);
	signal sMXE : unsigned(7 downto 0);
	signal sMYE : unsigned(7 downto 0);
	signal sMPRIO : unsigned(7 downto 0);
	signal sMCDelay : unsigned(7 downto 0);
	signal sColors : spriteColorsDef;

	signal MC : unsigned(7 downto 0); -- sprite multi color (per slot)
	signal MCColorDelay : unsigned(7 downto 0);
	signal MCColor : unsigned(7 downto 0); -- sprite multi color switch for color decoding

	-- mode
	signal BMM: std_logic; -- Bitmap mode
	signal BMMDelay: std_logic;
	signal ECM: std_logic; -- Extended color mode
	signal ECMDelay: std_logic;
	signal MCM: std_logic; -- Multi color mode
	signal MCMDelay: std_logic;
	signal DEN: std_logic; -- DMA enable
	signal RSEL: std_logic; -- Visible rows selection (24/25)
	signal CSEL: std_logic; -- Visible columns selection (38/40)

	signal RES: std_logic;

	signal VM: unsigned(13 downto 10);
	signal CB: unsigned(13 downto 11);

	signal EC : ColorDef;  -- border color
	signal B0C : ColorDef; -- background color 0
	signal B1C : ColorDef; -- background color 1
	signal B2C : ColorDef; -- background color 2
	signal B3C : ColorDef; -- background color 3
	signal MM0 : ColorDef; -- sprite multicolor 0
	signal MM1 : ColorDef; -- sprite multicolor 1
	signal spriteColors: spriteColorsDef24;

-- borders and blanking
	signal MainBorder: std_logic;
	signal TBBorder: std_logic;
	signal setTBBorder: boolean;
	signal vBlank: std_logic;
	signal hBlank: std_logic;
	signal xscroll: unsigned(2 downto 0);
	signal yscroll: unsigned(2 downto 0);
	signal rasterCmp : unsigned(8 downto 0);

-- Address generator
	signal vicAddrReg : unsigned(13 downto 0);
	signal vicAddrLoc : unsigned(13 downto 0);

-- Address counters
	signal ColCounter: unsigned(10 downto 0) := (others => '0'); -- VC (C128plus: only bits 9..0 address memory)
	signal ColRestart: unsigned(10 downto 0) := (others => '0'); -- VCBASE
	signal RowCounter: unsigned(2 downto 0) := (others => '0');

-- IRQ Registers
	signal IRST: std_logic := '0';
	signal ERST: std_logic := '0';
	signal IMBC: std_logic := '0';
	signal EMBC: std_logic := '0';
	signal IMMC: std_logic := '0';
	signal EMMC: std_logic := '0';
	signal ILP: std_logic := '0';
	signal ELP: std_logic := '0';
	signal IRQ: std_logic;

-- Collision detection registers
	signal collision : unsigned(7 downto 0);
	signal M2M: unsigned(23 downto 0); -- Sprite to sprite collision
	signal M2D: unsigned(23 downto 0); -- Sprite to character collision
	signal M2DDelay: unsigned(23 downto 0); -- Sprite to character collision
	signal M2Mhit : std_logic;
	signal M2Dhit : std_logic;
	signal M2MClr : std_logic; -- collision register clear flag

-- Raster counters
	signal rasterX : unsigned(9 downto 0) := (others => '0');
	signal rasterY : unsigned(8 downto 0) := (others => '0');
	signal rasterY_next : unsigned(8 downto 0);
	signal cycleLast : boolean;
	signal cycleLastDelay : boolean;
	signal cycleTest : boolean;
	signal skipTest : boolean;
	signal rasterIncr : boolean;
	signal rasterXDelay : unsigned(9 downto 0);

-- Light pen
	signal lightPenHit: std_logic;
	signal lpX : unsigned(7 downto 0);
	signal lpY : unsigned(7 downto 0);

-- IRQ Resets
	signal resetLightPenIrq: std_logic;
	signal resetIMMC : std_logic;
	signal resetIMBC : std_logic;
	signal resetRasterIrq : std_logic;

-- Character generation
	signal charStore: charStoreDef;
	signal diChar : unsigned(7 downto 0);
	signal nextChar : unsigned(11 downto 0);
	-- Char/Pixels pair waiting to be shifted
	signal waitingChar : unsigned(11 downto 0);
	signal waitingChar_r : unsigned(11 downto 0);
	signal waitingPixels : unsigned(7 downto 0);
	signal waitingPixels_r : unsigned(7 downto 0);
	-- Stores colorinfo and the Pixels that are currently in shift register
	signal shiftingChar : unsigned(11 downto 0);
	signal shiftingChar_d : unsigned(11 downto 0);
	signal shiftingPixels : unsigned(7 downto 0);
	signal currentPixels : unsigned(1 downto 0);
	signal currentPixels_d : unsigned(1 downto 0);
	signal shifting_ff : std_logic; -- Multicolor shift-regiter status bit.

-- Sprite work registers
	signal MPtr : unsigned(7 downto 0); -- sprite base pointer
	signal MPixels : MPixelsDef; -- Sprite 24 bit shift register
	signal MPixelStore : unsigned(15 downto 0); -- Store fetched sprite bytes until ready to load into the shift register
	signal MActive : MFlags; -- Sprite is active
	signal MActive_next : MFlags; -- Sprite is active combinatorial
	signal MDMA : MFlags; -- Sprite DMA is enabled
	signal MDMA_next : MFlags; -- Sprite DMA is enabled combinatorial
	signal MCnt : MCntDef;
	signal MCnt_next : MCntDef;
	signal MCBase : MCntDef;
	signal MCBase_next : MCntDef;
	signal MXE_ff : unsigned(7 downto 0); -- Sprite X expansion flipflop
	signal MYE_ff : unsigned(7 downto 0); -- Sprite Y expansion flipflop
	signal MYE_ff_next : unsigned(7 downto 0); -- Sprite Y expansion flipflop combinatorial
	signal MC_ff : unsigned(7 downto 0); -- controls sprite shift-register in multicolor
	signal MShift_stop : MFlags; -- Stop sprite shifting flag
	signal MCurrentPixel_r : MCurrentPixelDef;
	signal MCurrentPixel : MCurrentPixelDef;

-- Current colors and pixels
	signal pixelBgFlag: std_logic; -- For collision detection

-- Read/Write lines
	signal we_r : std_logic;
	signal rd_r : std_logic;
	signal addr_r: unsigned(5 downto 0);
	signal addr2_r: unsigned(5 downto 0);
	signal ext_r: std_logic;
	signal extSel_r: unsigned(1 downto 0);
	signal di_r: unsigned(7 downto 0);

	signal myWr_phi1 : std_logic;
	signal myWr_a : std_logic;
	signal myWr_b : std_logic;
	signal myWr_c : std_logic;
	signal myRd : std_logic;

-- VIC-IIe registers and state
   signal k_reg : unsigned(2 downto 0) := (others => '0');
	signal turbo_reg : std_logic := '0';
	signal test_reg : std_logic := '0';
	signal turbo_state_s : std_logic_vector(1 downto 0);

-- C128plus extension registers and state
	signal regAddr : unsigned(5 downto 0);  -- base bank register address
	signal ext : std_logic;                 -- access to an extension bank while unlocked
	signal extSel : unsigned(1 downto 0);   -- "01" = $D040-$D07F, "10" = $D080-$D0BF, "11" = unused
	signal addr2 : unsigned(5 downto 0);    -- extension bank register address
	signal unlocked : std_logic := '0';
	signal unlockStep : std_logic := '0';
	signal PALEN : std_logic := '0';
	signal palette : paletteDef;
	signal colorIndexLoc : unsigned(3 downto 0);

	-- C128plus scrolling registers (written by the CPU) ...
	signal SCRSTART : unsigned(10 downto 0) := (others => '0'); -- screen start offset
	signal SCRSTART_HI : unsigned(2 downto 0) := (others => '0'); -- high bits written to $D072, applied with $D071
	signal ROWLEN : unsigned(7 downto 0) := (others => '0');    -- row length in characters (<40 = 40)
	signal PTRSEP : std_logic := '0';                           -- sprite pointers in their own page
	signal PTRPAGE : unsigned(5 downto 0) := (others => '0');   -- sprite pointer page (address bits 13..8)
	-- ... and the values in use, latched at the start of each frame
	signal activeStride : unsigned(7 downto 0) := to_unsigned(40, 8);
	signal blankLoc : std_logic;

	constant DEFAULT_PALETTE : paletteDef := (
		x"00", x"0F", x"14", x"8B", x"E6", x"78", x"B3", x"4D",
		x"26", x"33", x"18", x"04", x"07", x"6D", x"B8", x"0A"
	);

begin
-- -----------------------------------------------------------------------
-- Ouput signals
-- -----------------------------------------------------------------------
	ba <= baLoc or turbo_state_s(0) or turbo_state_s(1);
	vicAddr <= vicAddrReg when registeredAddress else vicAddrLoc;
	irq_n <= not IRQ;
	turbo_state <= turbo_state_s(0) or turbo_state_s(1);
	ko <= k_reg;

-- -----------------------------------------------------------------------
-- C128plus: register bank decode
-- While locked, address bits 7..6 are ignored (stock mirroring every 64 bytes).
-- While unlocked, $D040-$D07F and $D080-$D0BF are extension banks and
-- $D0C0-$D0FF is unused; the base bank decoders then see $D031 (an unused
-- register) so they ignore the access.
-- -----------------------------------------------------------------------
	extSel <= aRegisters(7 downto 6);
	ext <= unlocked when extSel /= "00" else '0';
	regAddr <= "110001" when ext = '1' else aRegisters(5 downto 0);
	addr2 <= aRegisters(5 downto 0);

-- -----------------------------------------------------------------------
-- C128plus: per-slot sprite registers (selected by slot owner)
-- -----------------------------------------------------------------------
	slotMux: for i in 0 to 7 generate
		-- DMA side
		sMY(i)      <= MY(i+16)           when own(i) = "10" else MY(i+8)           when own(i) = "01" else MY(i);
		sME(i)      <= ME(i+16)           when own(i) = "10" else ME(i+8)           when own(i) = "01" else ME(i);
		sMYE(i)     <= MYE(i+16)          when own(i) = "10" else MYE(i+8)          when own(i) = "01" else MYE(i);
		-- display side
		sMX(i)      <= MX(i+16)           when ownDisp(i) = "10" else MX(i+8)           when ownDisp(i) = "01" else MX(i);
		sMXE(i)     <= MXE(i+16)          when ownDisp(i) = "10" else MXE(i+8)          when ownDisp(i) = "01" else MXE(i);
		sMPRIO(i)   <= MPRIO(i+16)        when ownDisp(i) = "10" else MPRIO(i+8)        when ownDisp(i) = "01" else MPRIO(i);
		sMCDelay(i) <= MCDelay(i+16)      when ownDisp(i) = "10" else MCDelay(i+8)      when ownDisp(i) = "01" else MCDelay(i);
		sColors(i)  <= spriteColors(i+16) when ownDisp(i) = "10" else spriteColors(i+8) when ownDisp(i) = "01" else spriteColors(i);
	end generate;

	process(clk)
	begin
		if rising_edge(clk) then
			if phi = '0'
			and enaData = '1'
			and vicCycle = cycleSpriteA then
				ownDisp(to_integer(sprite)) <= own(to_integer(sprite));
			end if;
		end if;
	end process;

-- -----------------------------------------------------------------------
-- C128plus: palette output
-- -----------------------------------------------------------------------
	colorIndex <= colorIndexLoc;
	extColor   <= (others => '0') when blankLoc = '1' else palette(to_integer(colorIndexLoc));
	extColorEn <= PALEN;

-- -----------------------------------------------------------------------
-- VIC-IIe turbo mode and test mode
-- -----------------------------------------------------------------------
	turbo_state_s(0) <= turbo_reg and (vic2e or turbo_en);

	process(clk)
	begin
		if rising_edge(clk) then
			if enaPixel = '1' and rasterX(2 downto 0) = "011" then
				turbo_state_s(1) <= turbo_state_s(0);
			end if;
		end if;
	end process;

	process(clk)
	begin
		if rising_edge(clk) then
			if baSync = '0' and enaData = '1' then
				if phi = '0' then
					if test_reg = '0' or vic2e = '0' then
						cycleTest <= false;
					end if;
				else
					if test_reg = '1' and vic2e = '1' then
						cycleTest <= true;
					end if;
				end if;
			end if;
		end if;
	end process;

-- -----------------------------------------------------------------------
-- chip-select signals and data/address bus latch
-- -----------------------------------------------------------------------
	process(clk)
	begin
		if rising_edge(clk) then
			if phi = '1' then
				we_r <= cs and we;
				rd_r <= cs and not we;
				addr_r <= regAddr;
				addr2_r <= addr2;
				ext_r <= ext;
				extSel_r <= extSel;
				di_r <= diRegisters;
			end if;
		end if;
	end process;

	myWr_phi1 <= cs and phi and we;
	myWr_a <= '1' when we_r = '1' and enaPixel = '1' and rasterX(2 downto 0) = "011" else '0';
	myWr_b <= '1' when we_r = '1' and enaPixel = '1' and rasterX(2 downto 0) = "100" else '0';
	myWr_c <= '1' when we_r = '1' and enaPixel = '1' and rasterX(2 downto 0) = "101" else '0';
	-- timing of the read is only important for the collision register reads
	myRd   <= '1' when cs = '1' and phi = '1' and we = '0' and enaPixel = '1' and rasterX(1 downto 0) = "01" else '0';

-- -----------------------------------------------------------------------
-- debug signals
-- -----------------------------------------------------------------------
	debugX <= rasterXDelay;
	debugY <= rasterY;

-- -----------------------------------------------------------------------
-- Badline condition
-- -----------------------------------------------------------------------
	process(rasterY, yscroll, rasterEnable)
	begin
		badLine <= false;
		if (rasterY(2 downto 0) = yscroll)
		and (rasterEnable = '1') then
			badLine <= true;
		end if;
	end process;

-- -----------------------------------------------------------------------
-- BA=low counter
-- -----------------------------------------------------------------------
	process(clk)
	begin
		if rising_edge(clk) then
			if baLoc = '0' then
				if phi = '0'
				and enaData = '1'
				and (turbo_state_s = "00")
				and baCnt(2) = '0' then
					baCnt <= baCnt + 1;
				end if;
			else
				baCnt <= (others => '0');
			end if;
		end if;
	end process;

-- -----------------------------------------------------------------------
-- Calculate lastLineFlag
-- -----------------------------------------------------------------------
	process(clk)
		variable rasterLines : integer range 0 to 312;
	begin
		if rising_edge(clk) then
			lastLineFlag <= false;

			rasterLines := 311; -- PAL
			if mode6567old = '1' then
				rasterLines := 261; -- NTSC (R7 and earlier have 262 lines)
			end if;
			if mode6567R8 = '1' then
				rasterLines := 262; -- NTSC (R8 and newer have 263 lines)
			end if;
			if rasterY = rasterLines then
				lastLineFlag <= true;
			end if;
		end if;
	end process;

-- -----------------------------------------------------------------------
-- State machine
-- -----------------------------------------------------------------------
vicStateMachine: process(clk)
	begin
		if rising_edge(clk) then
			if enaData = '1'
			and baSync = '0' then
				if phi = '0' then
					case vicCycle is
					when cycleRefresh1 => vicCycle <= cycleRefresh2;
					when cycleRefresh2 => vicCycle <= cycleRefresh3;
					when cycleRefresh3 => vicCycle <= cycleRefresh4;  -- X=0..7 on this cycle
					when cycleRefresh4 => vicCycle <= cycleRefresh5;
					when cycleRefresh5 => vicCycle <= cycleChar;
					when cycleChar =>
						if rasterX(9 downto 3) = "0101000" then
							if mode6569 = '1' or mode6572 = '1' then -- PAL/PAL-N
							vicCycle <= cycleCalcSprites;
						end if;
							if mode6567R8  = '1' or mode6567old = '1' then -- New/Old NTSC
								vicCycle <= cycleIdle1;
							end if;
						end if;
					when cycleIdle1 =>
						if mode6567R8  = '1' then
							vicCycle <= cycleIdle2; -- New NTSC - 2 extra idle cycles (65 cycles/line)
						else
							vicCycle <= cycleCalcSprites; -- Old NTSC - 1 extra idle cycle (64 cycles/line)
						end if;
					when cycleIdle2 => vicCycle <= cycleCalcSprites;
					when cycleCalcSprites => vicCycle <= cycleSpriteBa1;
					when cycleSpriteBa1   => vicCycle <= cycleSpriteBa2;
					when cycleSpriteBa2   => vicCycle <= cycleSpriteBa3;
					when others =>
						null;
					end case;
				else
					case vicCycle is
					when cycleSpriteBa3 => vicCycle <= cycleSpriteA;
					when cycleSpriteA =>
						vicCycle <= cycleSpriteB;
					when cycleSpriteB =>
						vicCycle <= cycleSpriteA;
						if sprite = 7 then
							vicCycle <= cycleRefresh1;
						end if;
					when others =>
						null;
					end case;
				end if;
			end if;
		end if;
	end process;

-- -----------------------------------------------------------------------
-- Iterate through all sprites.
-- Only used when state-machine above is in any sprite cycles.
-- -----------------------------------------------------------------------
	process(clk)
	begin
		if rising_edge(clk) then
			if phi = '1'
			and enaData = '1'
			and vicCycle = cycleSpriteB
			and baSync = '0' then
				sprite <= sprite + 1;
			end if;
		end if;			
	end process;

-- -----------------------------------------------------------------------
-- Address generator
-- -----------------------------------------------------------------------
	process(phi, vicCycle, sprite, shiftChars, idle,
			VM, CB, ECM, BMM, nextChar, colCounter, rowCounter, MPtr, MCnt,
			MDMA_next, refreshCounter, own, PTRSEP, PTRPAGE, unlocked)
	begin
		--
		-- Default case ($3FFF fetches)
		vicAddrLoc <= (others => '1');
		if (idle = '0')
		and shiftChars then
			if BMM = '1' then
				vicAddrLoc <= CB(13) & colCounter(9 downto 0) & rowCounter;
			else
				vicAddrLoc <= CB & nextChar(7 downto 0) & rowCounter;
			end if;
		end if;

		case vicCycle is
		when cycleRefresh1 | cycleRefresh2 | cycleRefresh3 | cycleRefresh4 | cycleRefresh5 =>
			if emulateRefresh then
				vicAddrLoc <= "111111" & refreshCounter;
			else
				vicAddrLoc <= (others => '-');
			end if;
		when cycleSpriteBa1 | cycleSpriteBa2 | cycleSpriteBa3 =>
			vicAddrLoc <= (others => '1');
		when cycleSpriteA =>
			if phi = '1' then
				if MDMA_Next(to_integer(sprite)) then
					vicAddrLoc <= MPtr & MCnt(to_integer(sprite));
				end if;
			else
				-- p-access: sprite n at $3F8+n, C128plus sprite n+8 at $3F0+n, sprite n+16 at $3E8+n.
				-- C128plus: with PTRSEP they are $F8/$F0/$E8 in the page selected by PTRPAGE.
				if unlocked = '1' and PTRSEP = '1' then
					vicAddrLoc <= PTRPAGE & "111" & (not own(to_integer(sprite))) & sprite;
				else
					vicAddrLoc <= VM & "11111" & (not own(to_integer(sprite))) & sprite;
				end if;
			end if;
		when cycleSpriteB =>
			if MDMA_Next(to_integer(sprite)) then
				vicAddrLoc <= MPtr & MCnt(to_integer(sprite));
			end if;
		when others =>
			if ECM = '1' then
				vicAddrLoc(10 downto 9) <= "00";
			end if;
			if phi = '1' then
				vicAddrLoc <= VM & colCounter(9 downto 0);
			end if;
		end case;
	end process;

	-- Registered address
	process(clk)
	begin
		if rising_edge(clk) then
			vicAddrReg <= vicAddrLoc;
		end if;
	end process;

-- -----------------------------------------------------------------------
-- Character storage
-- -----------------------------------------------------------------------
	diChar <= di when refresh = '0' and (aec = '1' or cs = '1') else (others => '1');

	process(clk)
	begin
		if rising_edge(clk) then
			if enaData = '1'
			and shiftChars
			and phi = '1' then
				if baChars = '0' then
					nextChar(7 downto 0) <= diChar;
					nextChar(11 downto 8) <= diColor;
				else
					nextChar <= charStore(38);
				end if;
				charStore <= charStore(37 downto 0) & nextChar;
			end if;
		end if;
	end process;

-- -----------------------------------------------------------------------
-- Sprite base pointer (MPtr)
-- -----------------------------------------------------------------------
	process(clk)
	begin
		if rising_edge(clk) then
			if phi = '0'
			and enaData = '1'
			and vicCycle = cycleSpriteA then
				MPtr <= (others => '1');
				if MActive_next(to_integer(sprite)) then
					MPtr <= di;
				end if;

				-- If refresh counter is not emulated we don't care about
				-- MPtr having the correct value in idle state.
				if not emulateRefresh then
					MPtr <= di;
				end if;
			end if;
		end if;
	end process;

-- -----------------------------------------------------------------------
-- Refresh counter
-- -----------------------------------------------------------------------
	vicRefresh <= refresh;

	process(clk)
	begin
		if rising_edge(clk) then
			refresh <= '0';
			case vicCycle is
			when cycleRefresh1 | cycleRefresh2 | cycleRefresh3 | cycleRefresh4 | cycleRefresh5 =>
				refresh <= '1';
				if phi = '0'
				and enaData = '1'
				and baSync = '0' then
					refreshCounter <= refreshCounter - 1;
				end if;
			when others =>
				null;
			end case;
			if lastLineFlag then
				refreshCounter <= (others => '1');
			end if;
		end if;
	end process;

-- -----------------------------------------------------------------------
-- Generate Raster Enable
-- -----------------------------------------------------------------------
	process(clk)
	begin
		-- Enable screen and character display.
		-- This is only possible in line 48 on the VIC-II.
		-- On other lines any DEN changes are ignored.
		if rising_edge(clk) then
			if (rasterY = 48) and (DEN = '1') then
				rasterEnable <= '1';
			end if;
			if (rasterY = 248) then
				rasterEnable <= '0';
			end if;
		end if;
	end process;


-- -----------------------------------------------------------------------
-- BA generator (Text/Bitmap)
-- -----------------------------------------------------------------------
--
-- For Text/Bitmap BA goes low 3 cycles before real access. So BA starts
-- going low during refresh2 state. See diagram below for timing:
--
-- X               0  0  0  0  0
--                 0  0  0  0  1
--                 0  4  8  C  0
--
-- phi ___   ___   ___   ___   ___   ___   ___   ___...
--        ___   ___   ___   ___   ___   ___   ___   ...
--
--          |     |     |     |     |     |     |...
--     rfr2  rfr3  rfr4  rfr5  char1 char2 char3
--
-- BA _______
--        \\\_______________________________________
--          |  1  |  2  |  3  |
--
-- BACnt 000  001 | 010 | 011 | 100   100   100  ...
--
-- -----------------------------------------------------------------------
	process(clk)
	begin
		if rising_edge(clk) then
			if phi = '0' then
				baChars <= '1';
				case vicCycle is
				when cycleRefresh2 | cycleRefresh3 | cycleRefresh4 | cycleRefresh5 =>
					if badLine then
						baChars <= '0';
					end if;
				when others =>
					if rasterX(9 downto 3) < "0101001"
					and badLine then
						baChars <= '0';
					end if;
				end case;
			end if;
		end if;
	end process;

-- -----------------------------------------------------------------------
-- BA generator (Sprites)
-- -----------------------------------------------------------------------
	process(clk)
	begin
		if rising_edge(clk) then
			if phi = '0' then
				if sprite = 1 then
					baSprite04 <= '1';
				end if;
				if sprite = 2 then
					baSprite15 <= '1';
				end if;
				if sprite = 3 then
					baSprite26 <= '1';
				end if;
				if sprite = 4 then
					baSprite37 <= '1';
				end if;
				if sprite = 5 then
					baSprite04 <= '1';
				end if;
				if sprite = 6 then
					baSprite15 <= '1';
				end if;
				if sprite = 7 then
					baSprite26 <= '1';
				end if;
				if vicCycle = cycleRefresh1 then
					baSprite37 <= '1';
					baSpriteLast <= baSpriteLast and baSprite37;
				end if;
				if vicCycle = cycleRefresh3 then
					baSprite37 <= '1';
					baSpriteLast <= '1';
				end if;

				if MDMA_next(0) and (vicCycle = cycleCalcSprites) then
					baSprite04 <= '0';
				end if;
				if MDMA(1) and (vicCycle = cycleSpriteBa2) then
					baSprite15 <= '0';
				end if;
				if MDMA(2) and (vicCycle = cycleSpriteB) and (sprite = 0) then
					baSprite26 <= '0';
				end if;
				if MDMA(3) and (vicCycle = cycleSpriteB) and (sprite = 1) then
					baSprite37 <= '0';
				end if;
				if MDMA(4) and (vicCycle = cycleSpriteB) and (sprite = 2) then
					baSprite04 <= '0';
				end if;
				if MDMA(5) and (vicCycle = cycleSpriteB) and (sprite = 3) then
					baSprite15 <= '0';
				end if;
				if MDMA(6) and (vicCycle = cycleSpriteB) and (sprite = 4) then
					baSprite26 <= '0';
				end if;
				if MDMA(7) and (vicCycle = cycleSpriteB) and (sprite = 5) then
					baSprite37 <= '0';
				end if;
			end if;
		end if;
	end process;
	baLoc <= baChars and baSprite04 and baSprite15 and baSprite26 and baSprite37;
	ba_dma <= '1' when (baSpriteLast = '0' or vicCycle = cycleRefresh3) and badLine else '0';

-- -----------------------------------------------------------------------
-- Address valid?
-- -----------------------------------------------------------------------
	addrValid <= aec;

	process(phi, baCnt, turbo_state_s, vic2e, refresh)
	begin
		aec <= '0';
		if (turbo_state_s = "00" or vic2e = '0' or refresh = '1') and (phi = '0' or baCnt(2) = '1') then
			aec <= '1';
		end if;
	end process;

-- -----------------------------------------------------------------------
-- Generate ShiftChars and ShiftLoadEna flags
-- -----------------------------------------------------------------------
	process(rasterX, rasterXDelay)
	begin
		shiftChars <= false;
		if rasterX(9 downto 3) > "0000001"
		and rasterX(9 downto 3) <= "0101001" then
			shiftChars <= true;
		end if;
		shiftLoadEna <= false;
		if rasterXDelay(9 downto 3) > "0000001"
		and rasterXDelay(9 downto 3) <= "0101010" then
			shiftLoadEna <= true;
		end if;

	end process;

-- -----------------------------------------------------------------------
-- RowCounter and ColCounter
-- -----------------------------------------------------------------------
	process(clk)
	begin
		if rising_edge(clk) then
			if phi = '0'
			and enaData = '1'
			and baSync = '0' then
				-- 4. VC and VMLI are incremented after each g-access in display state.
				if shiftChars
				and idle = '0' then
					colCounter <= colCounter + 1;
				end if;

				case vicCycle is
				when cycleRefresh4 =>
					-- 2. In the first phase of cycle 14 of each line, VC is loaded from VCBASE
					-- (VCBASE->VC) and VMLI is cleared. If there is a Bad Line Condition in
					-- this phase, RC is also reset to zero.
					colCounter <= colRestart;
					if badline then
						rowCounter <= (others => '0');
					end if;
				when cycleSpriteA =>
					-- 5. In the first phase of cycle 58, the VIC checks if RC=7. If so, the video
					-- logic goes to idle state and VCBASE is loaded from VC (VC->VCBASE). If
					-- the video logic is in display state afterwards (this is always the case
					-- if there is a Bad Line Condition), RC is incremented.
					if sprite = "000" then
						if rowCounter = 7 then
							-- C128plus: rows can be longer than 40 characters in memory
							if idle = '0' then
								colRestart <= colCounter + (("000" & activeStride) - 40);
							else
								colRestart <= colCounter;
							end if;
							idle <= '1';
						else
							rowCounter <= rowCounter + 1;
						end if;
						if badline then
							rowCounter <= rowCounter + 1;
						end if;
					end if;
				when others =>
					null;					
				end case;
				if lastLineFlag then
					-- 1. Once somewhere outside of the range of raster lines $30-$f7 (i.e.
					-- outside of the Bad Line range), VCBASE is reset to zero. This is
					-- presumably done in raster line 0, the exact moment cannot be determined
					-- and is irrelevant.
					-- C128plus: VCBASE starts at the screen start offset; the scrolling registers
					-- are latched here so a frame is never drawn with half-updated values.
					if unlocked = '1' then
						colRestart <= SCRSTART;
						if ROWLEN < 40 then
							activeStride <= to_unsigned(40, 8);
						else
							activeStride <= ROWLEN;
						end if;
					else
						colRestart <= (others => '0');
						activeStride <= to_unsigned(40, 8);
					end if;
				end if;

				-- Set display mode (leave idle-mode) as soon as
				-- there is a badline condition.
				if badline then
					idle <= '0';
				end if;
			end if;
		end if;
	end process;

-- -----------------------------------------------------------------------
-- X/Y Raster counter
-- -----------------------------------------------------------------------
cycleLast <= (vicCycle = cycleSpriteB) and (sprite = 2);
rasterIncr <= ((((lastLineFlag and cycleLastDelay) or (not lastLineFlag and cycleLast))) and not (cycleTest and skipTest)) or (cycleTest and not skipTest);
rasterY_next <= (others => '0') when (rasterIncr and lastLineFlag) 
                else rasterY+1  when rasterIncr
					 else rasterY;

rasterCounters: process(clk, rasterX, rasterXDelay)
	variable firstLine: boolean := false;
	begin
		if rising_edge(clk) then
			if enaPixel = '1' then
				rasterX(2 downto 0) <= rasterX(2 downto 0) + 1;
				rasterXDelay <= rasterXDelay + 1;
				if rasterX = PIX_DELAY - 1 then
					rasterXDelay <= (others => '0');
				end if;
			end if;
			if baSync = '0' and enaData = '1' then
				skipTest <= false;

				if phi = '0' then
					rasterX(9 downto 3) <= rasterX(9 downto 3) + 1;
					rasterX(2 downto 0) <= (others => '0');
					if vicCycle = cycleRefresh3 then
						rasterX <= (others => '0');
					end if;
					if cycleTest then
						rasterY <= rasterY_next;
					end if;
					if rasterY_next = 0 and not firstLine then
						firstLine := cycleTest;
						skipTest <= true;
					else
						firstLine := false;
					end if;
				else 
					cycleLastDelay <= cycleLast and lastLineFlag and not cycleTest;
					if (lastLineFlag and cycleLastDelay) or (not lastLineFlag and cycleLast) then
						rasterY <= rasterY_next;
						skipTest <= true;
					end if;
					if firstLine then
						skipTest <= true;
					end if;
				end if;
			end if;
		end if;
	end process;

-- -----------------------------------------------------------------------
-- Raster IRQ
-- -----------------------------------------------------------------------
	process(clk)
	begin
		if rising_edge(clk) then
			if phi = '1'
			and enaData = '1'
			and baSync = '0'
			and ((lastLineFlag and cycleLastDelay) or (not lastLineFlag and cycleLast)) then
				rasterIrqDone <= '0';
			end if;
			if resetRasterIrq = '1' then
				IRST <= '0';
			end if;
			if (rasterIrqDone = '0')
			and (rasterY = rasterCmp) then
				rasterIrqDone <= '1';
				IRST <= '1';
			end if;
		end if;
	end process;


-- -----------------------------------------------------------------------
-- Light pen
-- -----------------------------------------------------------------------
-- On a negative edge on the LP input, the current position of the raster beam
-- is latched in the registers LPX ($d013) and LPY ($d014). LPX contains the
-- upper 8 bits (of 9) of the X position and LPY the lower 8 bits (likewise of
-- 9) of the Y position. So the horizontal resolution of the light pen is
-- limited to 2 pixels.

-- Only one negative edge on LP is recognized per frame. If multiple edges
-- occur on LP, all following ones are ignored. The trigger is not released
-- until the next vertical blanking interval.
-- -----------------------------------------------------------------------
lightPen: process(clk)
	begin
		if rising_edge(clk) then
			if emulateLightpen then
				if resetLightPenIrq = '1' then
					-- Reset light pen interrupt
					ILP <= '0';
				end if;			
				if lastLineFlag then
					-- Reset lightpen state at beginning of frame
					lightPenHit <= '0';
				elsif (lightPenHit = '0') and (lp_n = '0') then
					-- One hit/frame
					lightPenHit <= '1'; 
					-- Toggle Interrupt
					ILP <= '1'; 
					-- Store position of beam
					lpx <= rasterX(8 downto 1);
					lpy <= rasterY(7 downto 0);
				end if;
			else
				ILP <= '0';
				lpx <= (others => '1');
				lpy <= (others => '1');
			end if;
		end if;
	end process;

-- -----------------------------------------------------------------------
-- VSync
-- -----------------------------------------------------------------------
doVSync: process(clk, mode6567old, mode6567R8)
		variable rasterBlank : integer range 0 to 311;
		variable rasterSync : integer range 0 to 311;
		variable rasterSyncEnd : integer range 0 to 311;
		variable rasterBlankEnd : integer range 0 to 311;
	begin
		rasterBlank := 300;
		rasterSync := 304;
		rasterSyncEnd := 307;
		rasterBlankEnd := 311;
		if mode6567R8 = '1' or mode6567old = '1' then
			rasterBlank := 13;
			rasterSync := 17;
			rasterSyncEnd := 20;
			rasterBlankEnd := 24;
		end if;
		if rising_edge(clk) then
			if enaData = '1'
			and baSync = '0'
			then
				vBlank <= '0';
				if rasterY >= rasterBlank and rasterY < rasterBlankEnd then
					vBlank <= '1';
				end if;
				vSync <= '0';
				if rasterY >= rasterSync and rasterY < rasterSyncEnd and not cycleTest then
					vSync <= '1';
            end if;
			end if;
		end if;
	end process;

-- -----------------------------------------------------------------------
-- HSync
-- -----------------------------------------------------------------------
doHSync: process(clk)
	begin
		if rising_edge(clk) then
			if enaPixel = '1' then
				if sprite = 2 then
					hBlank <= '1';
				end if;
				if vicCycle = cycleRefresh1 then
					hBlank <= '0';
				end if;
				if rasterX = 396 then -- from VIC II datasheet
					hSync <= '1';
				elsif rasterX = 496 then -- from VIC II datasheet
					hSync <= '0';
				end if;
			end if;
		end if;
	end process;

-- -----------------------------------------------------------------------
-- Borders
-- -----------------------------------------------------------------------
calcBorders: process(clk)
	variable newTBBorder: std_logic;
	begin
		if rising_edge(clk) then
			if enaPixel = '1' then
				newTBBorder := TBBorder;
				-- 1. If the X coordinate reaches the right comparison value, the main border
				--   flip flop is set (comparison values are from VIC II datasheet).
				if (rasterX = 339 + 3 and CSEL = '0') or (rasterX = 348 + 3 and CSEL = '1')  then
					MainBorder <= '1';
				end if;
				-- 2. If the Y coordinate reaches the bottom comparison value in cycle 63, the
				-- vertical border flip flop is set. FIX: compare during the whole line, but set at cycle 63
				-- 3. If the Y coordinate reaches the top comparison value in cycle 63 and the
				-- DEN bit in register $d011 is set, the vertical border flip flop is
				-- reset. FIX: compare during the whole line and act immediately
				if (rasterY = 247 and RSEL = '0') or (rasterY = 251 and RSEL = '1') then
					setTBBorder <= true;
				end if;
				if ((rasterY = 55 and RSEL = '0') or (rasterY = 51 and RSEL = '1')) and DEN = '1' then
					newTBBorder := '0';
				end if;
				if cycleLast then
					if setTBBorder then
						newTBBorder := '1';
						setTBBorder <= false;
					end if;
				end if;
				if (rasterX = 35 + 3 and CSEL = '0') or (rasterX = 28 + 3 and CSEL = '1') then
					-- 4. If the X coordinate reaches the left comparison value and the Y
					-- coordinate reaches the bottom one, the vertical border flip flop is set.
					-- FIX: act on the already triggered condition
					if setTBBorder then
						newTBBorder := '1';
						setTBBorder <= false;
					end if;
					-- 5. If the X coordinate reaches the left comparison value and the Y
					-- coordinate reaches the top one and the DEN bit in register $d011 is set,
					-- the vertical border flip flop is reset.
					if ((rasterY = 55 and RSEL = '0') or (rasterY = 51 and RSEL = '1')) and DEN = '1' then
						newTBBorder := '0';
					end if;
					-- 6. If the X coordinate reaches the left comparison value and the vertical
					-- border flip flop is not set, the main flip flop is reset.
					if newTBBorder = '0' and setTBBorder = false then
						MainBorder <= '0';
					end if;
				end if;
				TBBorder <= newTBBorder;
			end if;
		end if;
	end process;

-- -----------------------------------------------------------------------
-- Pixel generator for Text/Bitmap screen
-- -----------------------------------------------------------------------
calcBitmap: process(clk)
	variable multiColor : std_logic;
	begin
		if rising_edge(clk) then
			if enaPixel = '1' then
				--
				-- Toggle flipflop for multicolor 2-bits shift.
				shifting_ff <= not shifting_ff;

				--
				-- Multicolor mode is active with MCM, but for character
				-- mode it depends on bit3 of color ram too.
				multiColor := MCM and (BMM or ECM or shiftingChar(11));

				-- store the waiting values to be ready at the start of the delayed cell matrix,
				-- otherwise they'll be overwritten too soon
				if rasterXDelay(2 downto 0) = "111" then
					waitingChar_r <= waitingChar;
					waitingPixels_r <= waitingPixels;
				end if;
				
				--
				-- Reload shift register when xscroll=rasterX
				-- otherwise shift pixels
				if shiftLoadEna and xscroll = rasterXDelay(2 downto 0) then
					shifting_ff <= '0';
					shiftingChar <= waitingChar_r;
					shiftingPixels <= waitingPixels_r;
					currentPixels <= waitingPixels_r(7 downto 6);
				else
					shiftingPixels <= shiftingPixels(6 downto 0) & '0';
					if multiColor = '0' or shifting_ff = '1' then
						currentPixels <= shiftingPixels(6 downto 5);
					end if;
				end if;

				--
				-- Calculate if pixel is in foreground or background
				pixelBgFlag <= currentPixels(1);

				currentPixels_d <= currentPixels;
				shiftingChar_d <= shiftingChar;
				MCMDelay <= MCM;
				ECMDelay <= ECM;
				BMMDelay <= BMM;
			end if;

			--
			-- Store fetched pixels, until current pixels are displayed
			-- and shift-register is empty.
			if enaData = '1'
			and phi = '0' then
				-- Store the characters until shiftregister is empty
				waitingPixels <= (others => '0');
				if shiftChars then
					waitingPixels <= di;
					waitingChar <= (others => '0');
					if idle = '0' then
						waitingChar <= nextChar;
					end if;
				end if;
			end if;

		end if;
	end process;

-- -----------------------------------------------------------------------
-- Sprite byte counter
-- Y expansion flipflop
-- -----------------------------------------------------------------------

	process(rasterX, rasterY, MDMA, MCnt, MCBase, MCBase_next, MActive, MYE_ff, ME, MY, MYE, vicCycle, sprite,
	        own, sME, sMY, sMYE, unlocked)
	begin
		own_next <= own;
		MCBase_next <= MCBase;
		MDMA_next <= MDMA;
		MYE_ff_next <= MYE_ff;
		MCnt_next <= MCnt;
		MActive_next <= MActive;

		-- 1. The expansion flip flip is set as long as the bit in MxYE in register
		-- $d017 corresponding to the sprite is cleared.
		for i in 0 to 7 loop
			if sMYE(i) = '0' then
				MYE_ff_next(i) <= '1';
			end if;
		end loop;

		case vicCycle is

		when cycleChar =>
			-- 7. In the first phase of cycle 16, it is checked if the expansion flip flop
			-- is set. If so, MCBASE load from MC (MC->MCBASE), unless the CPU cleared
			-- the Y expansion bit in $d017 in the second phase of cycle 15, in which case
			-- MCBASE is set to X = (101010 & (MCBASE & MC)) | (010101 & (MCBASE | MC)).
			-- After the MCBASE update, the VIC checks if MCBASE is equal to 63 and turns
			-- off the DMA of the sprite if it is. (VIC Addendum)
			if rasterX(9 downto 3) = "0000010" then
				for i in 0 to 7 loop
					if MDMA(i) then
						if MYE_ff(i) = '1' then
							MCBase_next(i) <= MCnt(i);
						elsif sMYE(i) = '0' then
							-- MYE just turned off
							MCBase_next(i) <= ("101010" and (MCBase(i) and MCnt(i))) or ("010101" and (MCBase(i) or MCnt(i)));
						end if;
						if MCBase_next(i) = 63 then
							MDMA_next(i) <= false;
						end if;
					end if;
				end loop;
			end if;

		when cycleCalcSprites | cycleSpriteBa1 =>
			-- 2. If the MxYE bit is set in the first phase of cycle 55, the expansion
			-- flip flop is inverted. FIX: VirtualC64 does it at cycle 56, FLI demos likes it
			for i in 0 to 7 loop
				if sMYE(i) = '1' and vicCycle = cycleSpriteBa1 then
					MYE_ff_next(i) <= not MYE_ff(i);
				end if;
			end loop;
			-- 3. In the first phases of cycle 55 and 56, the VIC checks for every sprite
			-- if the corresponding MxE bit in register $d015 is set and the Y
			-- coordinate of the sprite (odd registers $d001-$d00f) match the lower 8
			-- bits of RASTER. If this is the case and the DMA for the sprite is still
			-- off, the DMA is switched on, MCBASE is cleared, and if the MxYE bit is
			-- set the expansion flip flip is reset.
			-- C128plus: if sprite i does not start, sprite i+8 and then sprite i+16 may
			-- take the free slot. The slot owner only changes when the slot's DMA is off.
			for i in 0 to 7 loop
				if not MDMA(i) then
					if ME(i) = '1' and rasterY(7 downto 0) = MY(i) then
						own_next(i) <= "00";
						MCBase_Next(i) <= (others => '0');
						MDMA_Next(i) <= true;
						if MYE(i) = '1' then
							if vicCycle = cycleCalcSprites then
								MYE_ff_Next(i) <= '1'; -- will inverted in the next cycle
							else
								MYE_ff_Next(i) <= '0';
							end if;
						end if;
					elsif unlocked = '1' and ME(i+8) = '1' and rasterY(7 downto 0) = MY(i+8) then
						own_next(i) <= "01";
						MCBase_Next(i) <= (others => '0');
						MDMA_Next(i) <= true;
						if MYE(i+8) = '1' then
							if vicCycle = cycleCalcSprites then
								MYE_ff_Next(i) <= '1'; -- will inverted in the next cycle
							else
								MYE_ff_Next(i) <= '0';
							end if;
						end if;
					elsif unlocked = '1' and ME(i+16) = '1' and rasterY(7 downto 0) = MY(i+16) then
						own_next(i) <= "10";
						MCBase_Next(i) <= (others => '0');
						MDMA_Next(i) <= true;
						if MYE(i+16) = '1' then
							if vicCycle = cycleCalcSprites then
								MYE_ff_Next(i) <= '1'; -- will inverted in the next cycle
							else
								MYE_ff_Next(i) <= '0';
							end if;
						end if;
					end if;
				end if;
			end loop;

		when cycleSpriteA =>
			-- 4. In the first phase of cycle 58, the MC of every sprite is loaded from
			-- its belonging MCBASE (MCBASE->MC) and it is checked if the DMA for the
			-- sprite is turned on and the Y coordinate of the sprite matches the lower
			-- 8 bits of RASTER. If this is the case, the display of the sprite is
			-- turned on.
			-- VIC Addendum: the actual disabling of sprite display is likely handled
			-- during the first phase of cycle 58 (see rule 4).

			if sprite = "000" then
				for i in 0 to 7 loop
					MCnt_Next(i) <= MCBase(i);
					if MDMA(i) then
						if sME(i) = '1' and rasterY(7 downto 0) = sMY(i) then
							MActive_Next(i) <= true;
						end if;
					else
						MActive_next(i) <= false;
					end if;
				end loop;
			end if;

		when others => null;
		end case;

	end process;

	process(clk)
	begin
		if rising_edge(clk) then

			if phi = '0'
			and enaData = '1' then
				MCBase <= MCBase_Next;
				MDMA <= MDMA_Next;
				own <= own_next;
				MYE_ff <= MYE_ff_Next;
				MCnt <= MCnt_Next;
			end if;
			if phi = '1'
			and enaPixel = '1' then
				MActive <= MActive_Next;
			end if;

			-- 5. If the DMA for a sprite is turned on, three s-accesses are done in
			-- sequence in the corresponding cycles assigned to the sprite (see the
			-- diagrams in section 3.6.3.). The p-accesses are always done, even if the
			-- sprite is turned off. The read data of the first access is stored in the
			-- upper 8 bits of the shift register, that of the second one in the middle
			-- 8 bits and that of the third one in the lower 8 bits.
			-- MC is incremented by one after each s-access.
			if enaData = '1' then
				if (vicCycle = cycleSpriteA and phi = '1')
				or (vicCycle = cycleSpriteB) then
					if MDMA(to_integer(sprite)) then
						MCnt(to_integer(sprite)) <= MCnt(to_integer(sprite)) + 1;
					end if;
				end if;
			end if;
		end if;
	end process;

-- -----------------------------------------------------------------------
-- Sprite pixel Shift register
-- -----------------------------------------------------------------------
	process(clk)
	variable MShift : MFlags; -- Sprite is shifting
	begin

		if rising_edge(clk) then
			if enaPixel = '1' then
				for i in 0 to 7 loop
					-- Enable sprites on the correct X position
					if MActive(i) and rasterXDelay = sMX(i) then
						MShift(i) := true;
					end if;
					-- Stop shifting in the third s cycle
					MShift_stop(i) <= false;
					if sprite = i and phi = '1' and vicCycle = cycleSpriteB then
						MShift_stop(i) <= true;
					end if;
					if MShift_stop(i) then
						MShift(i) := false;
					end if;
				end loop;

				-- Shift one pixel of the sprite from the shift register.
				for i in 0 to 7 loop
					if MShift(i) then
						MXE_ff(i) <= (not MXE_ff(i)) and sMXE(i);
						if MXE_ff(i) = '0' then
							MC_ff(i) <= (not MC_ff(i)) and MC(i);
							if MC_ff(i) = '0' then
								MCurrentPixel_r(i) <= MPixels(i)(23 downto 22);
								if MPixels(i) = 0 then
									MShift(i) := false;
								end if;
							end if;
							-- Don't shift in the s cycles (sprite0move.prg, demusinterruptus.prg)
							if not (sprite = i and ((vicCycle = cycleSpriteA and phi = '1') or vicCycle = cycleSpriteB)) then
								MPixels(i) <= MPixels(i)(22 downto 0) & '0';
							end if;
						end if;
					else
						MXE_ff(i) <= '0';
						MC_ff(i) <= '0';
						MCurrentPixel_r(i) <= "00";
					end if;
					MCurrentPixel(i) <= MCurrentPixel_r(i);
				end loop;

				-- Changing the MC register directly affects the MC flip-flop
				-- Also looks like the value used for color decoding is delayed to
				-- what's used for the shift register (ss-hires-mc.prg)
				for i in 0 to 7 loop
					MC(i) <= sMCDelay(i);
					MCColorDelay(i) <= MC(i);
					MCColor(i) <= MCColorDelay(i);
					if sMCDelay(i) /= MC(i) then
						MC_ff(i) <= sMCDelay(i);
					end if;
				end loop;
			end if;

			--
			-- Fill Sprite shift-register with new data (even if the sprite is not active)
			if enaData = '1' then
				case vicCycle is
				when cycleSpriteA =>
					if phi = '1' then
						MPixelStore(15 downto 8) <= di;
					end if;
				when cycleSpriteB =>
					if phi = '0' then
						MPixelStore(7 downto 0) <= di;
					else
						MPixels(to_integer(sprite)) <= MPixelStore & di;
					end if;
					when others => null;
				end case;
			end if;
		end if;
	end process;

-- -----------------------------------------------------------------------
-- Video output
-- -----------------------------------------------------------------------

	process(clk)
		variable pixelColor: ColorDef;
		variable multiColor : std_logic;
		variable myColor: unsigned(3 downto 0);
		variable muxSprite : unsigned(2 downto 0);
		variable muxColor : unsigned(1 downto 0);
		-- 00 = pixels
		-- 01 = MM0
		-- 10 = Sprite
		-- 11 = MM1
	   variable lastBlank: std_logic;
	begin
		if rising_edge(clk) then
			muxColor := "00";
			muxSprite := (others => '-');
			for i in 7 downto 0 loop
				if MCColor(i) = '1' then
					if MCurrentPixel(i) /= "00" then
						if (sMPRIO(i) = '0') or (pixelBgFlag = '0') then
							muxColor := MCurrentPixel(i);
						else
							muxColor := "00";
						end if;
						muxSprite := to_unsigned(i, 3);
					end if;
				elsif MCurrentPixel(i)(1) = '1' then
					if (sMPRIO(i) = '0') or (pixelBgFlag = '0') then
						muxColor := "10";
					else
						muxColor := "00";
					end if;
					muxSprite := to_unsigned(i, 3);
				end if;
			end loop;

			-- Multicolor mode is active with MCM, but for character
			-- mode it depends on bit3 of color ram too.
			multiColor := MCMDelay and (BMMDelay or ECMDelay or shiftingChar_d(11));

			--
			-- Calculate color of next pixel
			pixelColor := B0C;
			if (BMMDelay = '0') and (ECMDelay='0') then
				if (multiColor = '0') then
					-- normal character mode
					if currentPixels_d(1) = '1' then
						pixelColor := shiftingChar_d(11 downto 8);
					end if;
				else
					-- multi-color character mode
					case currentPixels_d is
					when "01" => pixelColor := B1C;
					when "10" => pixelColor := B2C;
					when "11" => pixelColor := '0' & shiftingChar_d(10 downto 8);
					when others => null;
					end case;
				end if;
			elsif (MCMDelay = '0') and (BMMDelay = '0') and (ECMDelay = '1') then
				-- extended-color character mode
				-- multiple background colors but only 64 characters
				if currentPixels_d(1) = '1' then
					pixelColor := shiftingChar_d(11 downto 8);
				else
					case shiftingChar_d(7 downto 6) is
					when "01" => pixelColor := B1C;
					when "10" => pixelColor := B2C;
					when "11" => pixelColor := B3C;
					when others	=> null;
					end case;
				end if;
			elsif emulateGraphics and (MCMDelay = '0') and (BMMDelay = '1') and (ECMDelay = '0') then
				-- highres bitmap mode
				if currentPixels_d(1) = '1' then
					pixelColor := shiftingChar_d(7 downto 4);
				else
					pixelColor := shiftingChar_d(3 downto 0);
				end if;
			elsif emulateGraphics and (MCMDelay = '1') and (BMMDelay = '1') and (ECMDelay = '0') then
				-- Multi-color bitmap mode
				case currentPixels_d is
				when "01" => pixelColor := shiftingChar_d(7 downto 4);
				when "10" => pixelColor := shiftingChar_d(3 downto 0);
				when "11" => pixelColor := shiftingChar_d(11 downto 8);
				when others => null;
				end case;
			else
				-- illegal display mode, the output is black
				pixelColor := "0000";
			end if;

			myColor := pixelColor;
			case muxColor is
			when "01" => myColor := MM0;
			when "10" => myColor := sColors(to_integer(muxSprite));
			when "11" => myColor := MM1;
			when others =>
				null;
			end case;
		
		
--			myColor := pixelColor;
--			for i in 7 downto 0 loop
--				if (MPRIO(i) = '0') or (pixelBgFlag = '0') then
--					if MC(i) = '1' then
--						case MCurrentPixel(i) is
--						when "01" => myColor := MM0;
--						when "10" => myColor := spriteColors(i);
--						when "11" => myColor := MM1;
--						when others => null;
--						end case;
--					elsif MCurrentPixel(i)(1) = '1' then
--						myColor := spriteColors(i);
--					end if;
--				end if;
--			end loop;
			
			if enaPixel = '1' then
				lastBlank := hBlank or vBlank;
				blankLoc <= hBlank or vBlank;

				colorIndexLoc <= myColor;

-- Krestage 3 debugging routine
--				if (cs = '1' and aRegisters = "011100") then
--					colorIndex <= "1111";
--				end if;
				if MainBorder = '1' then
					colorIndexLoc <= EC;
				end if;
				if hBlank = '0' and vBlank = '0' and lastBlank = '1' and variant = "10" then
					colorIndexLoc <= (others => '1');
				end if;
				if hBlank = '1' or vBlank = '1' then
					colorIndexLoc <= (others => '0');
				end if;
			end if;
		end if;
	end process;

	YUVinverter: process(clk)
		variable state : boolean := false;
	begin
		if rising_edge(clk) then
			if enaPixel = '1'
			and baSync = '0'
			and rasterX(2 downto 0) = "100" then
				if cycleTest and not skipTest and vic2e = '1' then
					state := not state;
				end if;
				if cycleLast and rasterY = 30 then
					state := false;
				end if;
			end if;

			if state then
				invertV <= '1';
			else
				invertV <= '0';
			end if;
		end if;
	end process;

-- -----------------------------------------------------------------------
-- Collision register clear flag
-- -----------------------------------------------------------------------
collisionClearFlag: process(clk)
	begin
		if rising_edge(clk) then
			-- spritevssprite.prg
			if myRd = '1' and regAddr = "011110" then
				M2MClr <= '1';
			end if;
			if phi = '0' and enaPixel = '1' and not (addr_r = "011110" and rd_r = '1') then
				M2MClr <= '0';
			end if;
		end if;
	end process;

-- -----------------------------------------------------------------------
-- Sprite to sprite collision
-- -----------------------------------------------------------------------
spriteSpriteCollision: process(clk)
	begin
		if rising_edge(clk) then
			if resetIMMC = '1' then
				IMMC <= '0';
			end if;

			if enaPixel = '1' then
				for i in 0 to 7 loop
					if MC(i) = '0' then
						collision(i) <= MCurrentPixel(i)(1);
					else
						collision(i) <= MCurrentPixel(i)(1) or MCurrentPixel(i)(0);
					end if;
				end loop;
				if  (collision /= "00000000")
				and (collision /= "00000001")
				and (collision /= "00000010")
				and (collision /= "00000100")
				and (collision /= "00001000")
				and (collision /= "00010000")
				and (collision /= "00100000")
				and (collision /= "01000000")
				and (collision /= "10000000") then
					-- C128plus: report the collision for the sprite that owns each slot
					for i in 0 to 7 loop
						if collision(i) = '1' then
							case ownDisp(i) is
							when "01"   => M2M(i+8) <= '1';
							when "10"   => M2M(i+16) <= '1';
							when others => M2M(i) <= '1';
							end case;
						end if;
					end loop;
				end if;

				-- Give collision interrupt but only once until clear of register
				if M2M /= 0 and M2Mhit = '0' then
					IMMC <= '1';
					M2Mhit <= '1';
				end if;

				if M2MClr = '1' then
					M2M <= (others => '0');
					M2Mhit <= '0';
				end if;
			end if;
		end if;
	end process;

-- -----------------------------------------------------------------------
-- Sprite to background collision
-- -----------------------------------------------------------------------
spriteBackgroundCollision: process(clk)
	begin
		if rising_edge(clk) then			
			if resetIMBC = '1' then
				IMBC <= '0';
			end if;

			if enaPixel = '1' then
				for i in 0 to 7 loop
					if ((MC(i) = '0' and MCurrentPixel(i)(1) = '1') or
					    (MC(i) = '1' and MCurrentPixel(i) /= "00"))
					and pixelBgFlag = '1'
					and (TBBorder = '0') then
						case ownDisp(i) is
						when "01"   => M2DDelay(i+8) <= '1';
						when "10"   => M2DDelay(i+16) <= '1';
						when others => M2DDelay(i) <= '1';
						end case;
					end if;
				end loop;

				M2D <= M2DDelay;
				-- Give collision interrupt but only once until clear of register
				if M2DDelay /= 0 and M2Dhit = '0' then
					IMBC <= '1';
					M2Dhit <= '1';
				end if;
			end if;

			if (myRd = '1')
			and	(regAddr = "011111") then
				M2D <= (others => '0');
				M2DDelay <= (others => '0');
				M2Dhit <= '0';
			end if;
		end if;
	end process;

-- -----------------------------------------------------------------------
-- Generate IRQ signal
-- -----------------------------------------------------------------------
	IRQ <= (ILP and ELP) or (IMMC and EMMC) or (IMBC and EMBC) or (IRST and ERST);

-- -----------------------------------------------------------------------
-- Write registers
-- -----------------------------------------------------------------------
writeRegisters: process(clk)
	begin
		if rising_edge(clk) then
			resetLightPenIrq <= '0';
			resetIMMC <= '0';
			resetIMBC <= '0';
			resetRasterIrq <= '0';
		
			--
			-- write to registers
			if(reset = '1') then
				MX(0) <= (others => '0');
				MX(1) <= (others => '0');
				MX(2) <= (others => '0');
				MX(3) <= (others => '0');
				MX(4) <= (others => '0');
				MX(5) <= (others => '0');
				MX(6) <= (others => '0');
				MX(7) <= (others => '0');
				for i in 8 to 23 loop
					MX(i) <= (others => '0');
					MY(i) <= (others => '0');
					spriteColors(i) <= (others => '0');
				end loop;
				unlocked <= '0';
				unlockStep <= '0';
				PALEN <= '0';
				palette <= DEFAULT_PALETTE;
				SCRSTART <= (others => '0');
				SCRSTART_HI <= (others => '0');
				ROWLEN <= (others => '0');
				PTRSEP <= '0';
				PTRPAGE <= (others => '0');
				rasterCmp <= (others => '0');
				ECM <= '0';
				BMM <= '0';
				DEN <= '0';
				RSEL <= '0';
				yscroll <= (others => '0');
				ME <= (others => '0');
				RES <= '0';
				MCM <= '0';
				CSEL <= '0';
				xscroll <= (others => '0');
				MYE <= (others => '0');
				VM <= (others => '0');
				CB <= (others => '0');
				resetLightPenIrq <= '0';
				resetIMMC <= '0';
				resetIMBC <= '0';
				resetRasterIrq <= '0';
				ELP <= '0';
				EMMC <= '0';
				EMBC <= '0';
				ERST <= '0';
				MPRIO <= (others => '0');
				MCDelay <= (others => '0');
				MXE <= (others => '0');
				EC <= (others => '0');
				B0C <= (others => '0');
				B1C <= (others => '0');
				B2C <=(others => '0');
				B3C <= (others => '0');
				MM0 <= (others => '0');
				MM1 <= (others => '0');
				spriteColors(0) <= (others => '0');
				spriteColors(1) <= (others => '0');
				spriteColors(2) <= (others => '0');
				spriteColors(3) <= (others => '0');
				spriteColors(4) <= (others => '0');
				spriteColors(5) <= (others => '0');
				spriteColors(6) <= (others => '0');
				spriteColors(7) <= (others => '0');
				turbo_reg <= '0';
				test_reg <= '0';
				k_reg <= (others => '0');
			else

				if (myWr_phi1 = '1' and (rasterX(1 downto 0) = "00" and enaPixel = '0' and variant = "01")) then
					-- HMOS versions seems to use the color registers too fast, before they latch the proper value from the bus
					case regAddr is
					when "100000" => EC <= x"F";
					when "100001" => B0C <= x"F";
					when "100010" => B1C <= x"F";
					when "100011" => B2C <= x"F";
					when "100100" => B3C <= x"F";
					when "100101" => MM0 <= x"F";
					when "100110" => MM1 <= x"F";
					when "100111" => spriteColors(0) <= x"F";
					when "101000" => spriteColors(1) <= x"F";
					when "101001" => spriteColors(2) <= x"F";
					when "101010" => spriteColors(3) <= x"F";
					when "101011" => spriteColors(4) <= x"F";
					when "101100" => spriteColors(5) <= x"F";
					when "101101" => spriteColors(6) <= x"F";
					when "101110" => spriteColors(7) <= x"F";
					when others => null;
					end case;
				end if;

				if (myWr_phi1 = '1' and (enaPixel = '1' or variant = "10")) then
					-- assumption: color registers are latched during the whole PHI high cycle
					case regAddr is
					when "100000" => EC <= diRegisters(3 downto 0);
					when "100001" => B0C <= diRegisters(3 downto 0);
					when "100010" => B1C <= diRegisters(3 downto 0);
					when "100011" => B2C <= diRegisters(3 downto 0);
					when "100100" => B3C <= diRegisters(3 downto 0);
					when "100101" => MM0 <= diRegisters(3 downto 0);
					when "100110" => MM1 <= diRegisters(3 downto 0);
					when "100111" => spriteColors(0) <= diRegisters(3 downto 0);
					when "101000" => spriteColors(1) <= diRegisters(3 downto 0);
					when "101001" => spriteColors(2) <= diRegisters(3 downto 0);
					when "101010" => spriteColors(3) <= diRegisters(3 downto 0);
					when "101011" => spriteColors(4) <= diRegisters(3 downto 0);
					when "101100" => spriteColors(5) <= diRegisters(3 downto 0);
					when "101101" => spriteColors(6) <= diRegisters(3 downto 0);
					when "101110" => spriteColors(7) <= diRegisters(3 downto 0);
					when others => null;
					end case;
				end if;

				if (myWr_a = '1') then
					case addr_r is
					when "010001" =>
						RSEL <= di_r(3);
					when "011001" =>
						resetLightPenIrq <= di_r(3);
						resetIMMC <= di_r(2);
						resetIMBC <= di_r(1);
						resetRasterIrq <= di_r(0);
					when "011101" => MXE(7 downto 0) <= di_r;
					when "110000" => 
						if vic2e = '1' or turbo_en = '1' then
							turbo_reg <= di_r(0);
							test_reg <= di_r(1);
						end if;
					when others => null;
					end case;
				end if;
				if (myWr_b = '1') then
					case addr_r is
					when "010001" =>
						rasterCmp(8) <= di_r(7);
						ECM <= di_r(6);
						BMM <= di_r(5);
						DEN <= di_r(4);
						yscroll <= di_r(2 downto 0);
					when "010010" =>
						rasterCmp(7 downto 0) <= di_r;
					when "010101" =>
						ME(7 downto 0) <= di_r;
					when "010110" =>
						RES <= di_r(5);
						MCM <= di_r(4);
						CSEL <= di_r(3);
					when "010111" => MYE(7 downto 0) <= di_r;
					when "011000" =>
						VM <= di_r(7 downto 4);
						CB <= di_r(3 downto 1);
					when "011010" =>
						ELP <= di_r(3);
						EMMC <= di_r(2);
						EMBC <= di_r(1);
						ERST <= di_r(0);
					when "011011" => MPRIO(7 downto 0) <= di_r;
					when "011100" =>
						-- MC <= di_r;
						MCDelay(7 downto 0) <= di_r; -- !!! Krestage 3 hack
					when "011101" => MXE(7 downto 0) <= di_r;
					when "101111" => 
						if vic2e = '1' then
							k_reg <= di_r(2 downto 0);
						end if;
					when "111111" =>
						-- C128plus unlock register $D03F: write $A5 then $96 to unlock,
						-- any other value locks again.
						unlockStep <= '0';
						unlocked <= '0';
						if vic2e = '1' then
							if di_r = x"A5" then
								unlockStep <= '1';
							elsif di_r = x"96" and unlockStep = '1' then
								unlocked <= '1';
							end if;
						end if;
					when others => null;
					end case;

					-- C128plus extension banks (unlocked only)
					--   $D040-$D04F  sprite 8..15 X/Y position
					--   $D050        sprite 8..15 X position bit 8
					--   $D051        sprite 8..15 enable
					--   $D052        sprite 8..15 Y expand
					--   $D053        sprite 8..15 background priority
					--   $D054        sprite 8..15 multicolour
					--   $D055        sprite 8..15 X expand
					--   $D056        sprite 8..15 sprite-sprite collision (read only)
					--   $D057        sprite 8..15 sprite-background collision (read only)
					--   $D058-$D05F  sprite 8..15 colour
					--   $D060-$D06F  palette entry 0..15: hue (bits 7..4), luminance (bits 3..0)
					--   $D070        bit 0: PALEN, use programmable palette
					--   $D071        screen start offset, bits 7..0; writing it also applies
					--                the bits held in $D072             (latched at frame start)
					--   $D072        screen start offset, bits 9..8; held until $D071 is written
					--   $D073        row length in characters, <40 = 40 (latched at frame start)
					--   $D074        bit 1: PTRSEP, sprite pointers in the PTRPAGE page
					--   $D075        PTRPAGE: sprite pointer page, VIC address bits 13..8
					--   $D080-$D09F  sprite 16..23, same layout as $D040-$D05F
					if ext_r = '1' and extSel_r = "01" then
						if addr2_r(5 downto 4) = "00" then
							if addr2_r(0) = '0' then
								MX(8 + to_integer(addr2_r(3 downto 1)))(7 downto 0) <= di_r;
							else
								MY(8 + to_integer(addr2_r(3 downto 1))) <= di_r;
							end if;
						elsif addr2_r(5 downto 3) = "011" then
							spriteColors(8 + to_integer(addr2_r(2 downto 0))) <= di_r(3 downto 0);
						else
							case addr2_r is
							when "010000" =>
								for i in 0 to 7 loop
									MX(8 + i)(8) <= di_r(i);
								end loop;
							when "010001" => ME(15 downto 8) <= di_r;
							when "010010" => MYE(15 downto 8) <= di_r;
							when "010011" => MPRIO(15 downto 8) <= di_r;
							when "010100" => MCDelay(15 downto 8) <= di_r;
							when "010101" => MXE(15 downto 8) <= di_r;
							when "110000" => PALEN <= di_r(0);
							-- the high byte is held until the low byte is written, so the
							-- 10-bit start offset always changes in one step
							when "110001" => SCRSTART <= SCRSTART_HI & di_r;
							when "110010" => SCRSTART_HI <= '0' & di_r(1 downto 0);
							when "110011" => ROWLEN <= di_r;
							when "110100" => PTRSEP <= di_r(1);
							when "110101" => PTRPAGE <= di_r(5 downto 0);
							when others =>
								if addr2_r(5 downto 4) = "10" then
									palette(to_integer(addr2_r(3 downto 0))) <= di_r;
								end if;
							end case;
						end if;
					elsif ext_r = '1' and extSel_r = "10" then
						if addr2_r(5 downto 4) = "00" then
							if addr2_r(0) = '0' then
								MX(16 + to_integer(addr2_r(3 downto 1)))(7 downto 0) <= di_r;
							else
								MY(16 + to_integer(addr2_r(3 downto 1))) <= di_r;
							end if;
						elsif addr2_r(5 downto 3) = "011" then
							spriteColors(16 + to_integer(addr2_r(2 downto 0))) <= di_r(3 downto 0);
						else
							case addr2_r is
							when "010000" =>
								for i in 0 to 7 loop
									MX(16 + i)(8) <= di_r(i);
								end loop;
							when "010001" => ME(23 downto 16) <= di_r;
							when "010010" => MYE(23 downto 16) <= di_r;
							when "010011" => MPRIO(23 downto 16) <= di_r;
							when "010100" => MCDelay(23 downto 16) <= di_r;
							when "010101" => MXE(23 downto 16) <= di_r;
							when others => null;
							end case;
						end if;
					end if;
				elsif (myWr_c = '1') then
					case addr_r is
					when "000000" => MX(0)(7 downto 0) <= di_r;
					when "000001" => MY(0) <= di_r;
					when "000010" => MX(1)(7 downto 0) <= di_r;
					when "000011" => MY(1) <= di_r;
					when "000100" => MX(2)(7 downto 0) <= di_r;
					when "000101" => MY(2) <= di_r;
					when "000110" => MX(3)(7 downto 0) <= di_r;
					when "000111" => MY(3) <= di_r;
					when "001000" => MX(4)(7 downto 0) <= di_r;
					when "001001" => MY(4) <= di_r;
					when "001010" => MX(5)(7 downto 0) <= di_r;
					when "001011" => MY(5) <= di_r;
					when "001100" => MX(6)(7 downto 0) <= di_r;
					when "001101" => MY(6) <= di_r;
					when "001110" => MX(7)(7 downto 0) <= di_r;
					when "001111" => MY(7) <= di_r;
					when "010110" => xscroll <= di_r(2 downto 0);
					when "010000" =>
						MX(0)(8) <= di_r(0);
						MX(1)(8) <= di_r(1);
						MX(2)(8) <= di_r(2);
						MX(3)(8) <= di_r(3);
						MX(4)(8) <= di_r(4);
						MX(5)(8) <= di_r(5);
						MX(6)(8) <= di_r(6);
						MX(7)(8) <= di_r(7);
					when others => null;
					end case;
				end if;
			end if;
		end if;
	end process;

-- -----------------------------------------------------------------------
-- Read registers
-- -----------------------------------------------------------------------
readRegisters: process(clk)
	begin
		if rising_edge(clk) then
			if myRd = '1' and ext = '1' then
				-- C128plus extension banks (see writeRegisters for the register list)
				do <= (others => '1');
				if extSel = "01" then
					if addr2(5 downto 4) = "00" then
						if addr2(0) = '0' then
							do <= MX(8 + to_integer(addr2(3 downto 1)))(7 downto 0);
						else
							do <= MY(8 + to_integer(addr2(3 downto 1)));
						end if;
					elsif addr2(5 downto 3) = "011" then
						do <= "1111" & spriteColors(8 + to_integer(addr2(2 downto 0)));
					else
						case addr2 is
						when "010000" => do <= MX(15)(8) & MX(14)(8) & MX(13)(8) & MX(12)(8) & MX(11)(8) & MX(10)(8) & MX(9)(8) & MX(8)(8);
						when "010001" => do <= ME(15 downto 8);
						when "010010" => do <= MYE(15 downto 8);
						when "010011" => do <= MPRIO(15 downto 8);
						when "010100" => do <= MCDelay(15 downto 8);
						when "010101" => do <= MXE(15 downto 8);
						when "010110" => do <= M2M(15 downto 8);
						when "010111" => do <= M2D(15 downto 8);
						when "110000" => do <= "1111111" & PALEN;
						when "110001" => do <= SCRSTART(7 downto 0);
						when "110010" => do <= "11111" & SCRSTART_HI;
						when "110011" => do <= ROWLEN;
						when "110100" => do <= "111111" & PTRSEP & '1';
						when "110101" => do <= "11" & PTRPAGE;
						when "100000" | "100001" | "100010" | "100011" | "100100" | "100101" | "100110" | "100111" |
						     "101000" | "101001" | "101010" | "101011" | "101100" | "101101" | "101110" | "101111" =>
							do <= palette(to_integer(addr2(3 downto 0)));
						when others => null;
						end case;
					end if;
				elsif extSel = "10" then
					if addr2(5 downto 4) = "00" then
						if addr2(0) = '0' then
							do <= MX(16 + to_integer(addr2(3 downto 1)))(7 downto 0);
						else
							do <= MY(16 + to_integer(addr2(3 downto 1)));
						end if;
					elsif addr2(5 downto 3) = "011" then
						do <= "1111" & spriteColors(16 + to_integer(addr2(2 downto 0)));
					else
						case addr2 is
						when "010000" => do <= MX(23)(8) & MX(22)(8) & MX(21)(8) & MX(20)(8) & MX(19)(8) & MX(18)(8) & MX(17)(8) & MX(16)(8);
						when "010001" => do <= ME(23 downto 16);
						when "010010" => do <= MYE(23 downto 16);
						when "010011" => do <= MPRIO(23 downto 16);
						when "010100" => do <= MCDelay(23 downto 16);
						when "010101" => do <= MXE(23 downto 16);
						when "010110" => do <= M2M(23 downto 16);
						when "010111" => do <= M2D(23 downto 16);
						when others => null;
						end case;
					end if;
				end if;
			elsif myRd = '1' then
			case regAddr is
			when "000000" => do <= MX(0)(7 downto 0);
			when "000001" => do <= MY(0);
			when "000010" => do <= MX(1)(7 downto 0);
			when "000011" => do <= MY(1);
			when "000100" => do <= MX(2)(7 downto 0);
			when "000101" => do <= MY(2);
			when "000110" => do <= MX(3)(7 downto 0);
			when "000111" => do <= MY(3);
			when "001000" => do <= MX(4)(7 downto 0);
			when "001001" => do <= MY(4);
			when "001010" => do <= MX(5)(7 downto 0);
			when "001011" => do <= MY(5);
			when "001100" => do <= MX(6)(7 downto 0);
			when "001101" => do <= MY(6);
			when "001110" => do <= MX(7)(7 downto 0);
			when "001111" => do <= MY(7);
			when "010000" =>
				do <= MX(7)(8) & MX(6)(8) & MX(5)(8) & MX(4)(8)
				& MX(3)(8) & MX(2)(8) & MX(1)(8) & MX(0)(8);
			when "010001" => do <= rasterY(8) & ECM & BMM & DEN & RSEL & yscroll;
			when "010010" => do <= rasterY(7 downto 0);
			when "010011" => do <= lpX;
			when "010100" => do <= lpY;
			when "010101" => do <= ME(7 downto 0);
			when "010110" => do <= "11" & RES & MCM & CSEL & xscroll;
			when "010111" => do <= MYE(7 downto 0);
			when "011000" => do <= VM & CB & '1';
			when "011001" => do <= IRQ & "111" & ILP & IMMC & IMBC & IRST;
			when "011010" => do <= "1111" & ELP & EMMC & EMBC & ERST;
			when "011011" => do <= MPRIO(7 downto 0);
			when "011100" => do <= MCDelay(7 downto 0);
			when "011101" => do <= MXE(7 downto 0);
			when "011110" => do <= M2M(7 downto 0);
			when "011111" => do <= M2D(7 downto 0);
			when "100000" => do <= "1111" & EC;
			when "100001" => do <= "1111" & B0C;
			when "100010" => do <= "1111" & B1C;
			when "100011" => do <= "1111" & B2C;
			when "100100" => do <= "1111" & B3C;
			when "100101" => do <= "1111" & MM0;
			when "100110" => do <= "1111" & MM1;
			when "100111" => do <= "1111" & spriteColors(0);
			when "101000" => do <= "1111" & spriteColors(1);
			when "101001" => do <= "1111" & spriteColors(2);
			when "101010" => do <= "1111" & spriteColors(3);
			when "101011" => do <= "1111" & spriteColors(4);
			when "101100" => do <= "1111" & spriteColors(5);
			when "101101" => do <= "1111" & spriteColors(6);
			when "101110" => do <= "1111" & spriteColors(7);
			when "101111" => if vic2e = '1' then
			                    do <= "11111" & k_reg;
			                 else
			                    do <= (others => '1');
			                 end if;
			when "110000" => if vic2e = '1' or turbo_en ='1' then
									  do <= "111111" & (test_reg or not vic2e) & turbo_reg;
								  else
								     do <= (others => '1');
								  end if;
			when "111111" => do <= "1111111" & (not unlocked); -- C128plus: $FE when unlocked
			when others => do <= (others => '1');
			end case;
			end if;
		end if;
	end process;
end architecture;
