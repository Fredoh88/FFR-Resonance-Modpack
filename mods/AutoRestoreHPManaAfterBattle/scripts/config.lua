
--[[
    Auto Restore HP And Mana After Battle
    Configuration - v1.1
    --------------------------------------------------

    RESURRECTION: Revive KO'd characters after battle.
    ------------
    allow_resurrection
		0: Does not restore anything on characters with HP = 0 (= does not resurrect them).
		1: Restores characters even if their HP is 0 (= does resurrect them).
    When resurrection is enabled, the game's native FullRecoveryMapUnit() function 
	is used if at least one party member has 0 HP.

	RESTORE ONLY ON LEVEL UP: Restores characters only when they level up after a combat encounter
	------------
	restore_only_on_levelup
		0: Restores all characters after every battle (while respecting allow_resurrection and other options).
		1: Only restores characters whose level increased during this battle (while respecting allow_resurrection and other options).
	Uses GetLevel() to compare past level (prior to battle) to current level (after battle).
	
	RESTORATION TOGGLES: Controls whether to restore or not restore HP and/or MP
	-----------------
	restore_health
	restore_mana
		0 = They will be disabled
		1 = they will restore according to other options

    RESTORE TYPE: Controls which kind of % to restore
    -----------------
	restore_health_type
	restore_mana_type
		restore_health_type = 1 and/or restore_mana_type = 1
			Restore TO a percentage of maximum (HP and/or MP).
			Example:
				Current HP: 50 / 150
				Percentage: 50
				Result: 75 / 150
			Because 50% of 150 max hp is 75, thus current hp 50 is restored up to 75

			If already above 75 HP, no HP is restored.

		restore_health_type = 2 and/or restore_mana_type = 2
			Type 2: Restore BY a percentage of maximum (HP and/or MP).
			Example:
				Current HP: 50 / 150
				Percentage: 50
				Result: 125 / 150
			Because 50% of 150 max hp is 75, thus current hp 50 + 75 = 125

    RESTORE PERCENTAGE: Restores % of HP and/or MP according to values in restore_health_type and restore_mana_type
    -----------
	restore_health_percentage
	restore_mana_percentage
		Use whole numbers (0, 15, 50, 100 etc with no decimals) and stay between 0 and 100.
		Values are rounded UP and limited to 0-100 to prevent unintended problems.
		I normalize them like this (but never below 0 or above 100):
			50.1 -> 51
			150  -> 100
			-20  -> 0
		Zero disables restoration of that resource.
		Restored HP/MP never exceeds the maximum.

    SETTINGS
    --------
    Changes require restarting or reloading the mod.

    The toggle key only affects the current session.
    It does not modify this configuration file.
]]

return {
    -- Master enable/disable
    enable_mod = 1,

    -- Revive KO'd party members
    allow_resurrection = 1,

    -- 1: Only restore characters whose level increased during this battle.
    -- 0: Restore after every battle (existing behavior).
    -- All resource and resurrection settings still apply.
    restore_only_on_levelup = 0,

    -- Health restoration
    restore_health = 1,
    restore_health_type = 1,
    restore_health_percentage = 100,

    -- Mana restoration
    restore_mana = 1,
    restore_mana_type = 1,
    restore_mana_percentage = 100,

    -- Enable/disable hotkey
    toggle_key = "DEL",
}

--[[
======================================================
    KEYBIND REFERENCE
======================================================

Change toggle_key to any value listed below.

Example:
    toggle_key = "F8"

IMPORTANT:
- Key names are case-sensitive.
- Use quotation marks around the key name.
- Only one key is supported by the mod.
- Some keys may conflict with game controls.
- Keyboard layouts can affect punctuation keys.

List from:
https://docs.ue4ss.com/lua-api/table-definitions/key.html

------------------------------------------------------
1. FUNCTION KEYS
------------------------------------------------------

F1              - Function key F1
F2              - Function key F2
F3              - Function key F3
F4              - Function key F4
F5              - Function key F5
F6              - Function key F6
F7              - Function key F7
F8              - Function key F8
F9              - Function key F9
F10             - Function key F10
F11             - Function key F11
F12             - Function key F12
F13             - Function key F13
F14             - Function key F14
F15             - Function key F15
F16             - Function key F16
F17             - Function key F17
F18             - Function key F18
F19             - Function key F19
F20             - Function key F20
F21             - Function key F21
F22             - Function key F22
F23             - Function key F23
F24             - Function key F24


------------------------------------------------------
2. LETTER KEYS
------------------------------------------------------

A               - Letter A
B               - Letter B
C               - Letter C
D               - Letter D
E               - Letter E
F               - Letter F
G               - Letter G
H               - Letter H
I               - Letter I
J               - Letter J
K               - Letter K
L               - Letter L
M               - Letter M
N               - Letter N
O               - Letter O
P               - Letter P
Q               - Letter Q
R               - Letter R
S               - Letter S
T               - Letter T
U               - Letter U
V               - Letter V
W               - Letter W
X               - Letter X
Y               - Letter Y
Z               - Letter Z


------------------------------------------------------
3. NUMBER KEYS (top row, NOT numpad)
------------------------------------------------------

ZERO            - Number 0
ONE             - Number 1
TWO             - Number 2
THREE           - Number 3
FOUR            - Number 4
FIVE            - Number 5
SIX             - Number 6
SEVEN           - Number 7
EIGHT           - Number 8
NINE            - Number 9

------------------------------------------------------
4. NAVIGATION KEYS
------------------------------------------------------

PAGE_UP         - Page Up
PAGE_DOWN       - Page Down
HOME            - Home
END             - End

LEFT_ARROW      - Left Arrow
RIGHT_ARROW     - Right Arrow
UP_ARROW        - Up Arrow
DOWN_ARROW      - Down Arrow

INS             - Insert
DEL             - Delete


------------------------------------------------------
5. STANDARD KEYBOARD KEYS
------------------------------------------------------

BACKSPACE       - Backspace
TAB             - Tab
RETURN          - Enter / Return
ESCAPE          - Escape
SPACE           - Spacebar

CAPS_LOCK       - Caps Lock
NUM_LOCK        - Num Lock
SCROLL_LOCK     - Scroll Lock

PAUSE           - Pause / Break
PRINT_SCREEN    - Print Screen
CLEAR           - Clear


------------------------------------------------------
6. NUMERIC NUMPAD (NOT top row)
------------------------------------------------------

NUM_ZERO        - Numpad 0
NUM_ONE         - Numpad 1
NUM_TWO         - Numpad 2
NUM_THREE       - Numpad 3
NUM_FOUR        - Numpad 4
NUM_FIVE        - Numpad 5
NUM_SIX         - Numpad 6
NUM_SEVEN       - Numpad 7
NUM_EIGHT       - Numpad 8
NUM_NINE        - Numpad 9

MULTIPLY        - Numpad Multiply (*)
ADD             - Numpad Add (+)
SUBTRACT        - Numpad Subtract (-)
DECIMAL         - Numpad Decimal (.)
DIVIDE          - Numpad Divide (/)
SEPARATOR       - Numpad Separator

------------------------------------------------------
7. MOUSE BUTTONS
------------------------------------------------------

LEFT_MOUSE_BUTTON   - Left Mouse Button
RIGHT_MOUSE_BUTTON  - Right Mouse Button
MIDDLE_MOUSE_BUTTON - Middle Mouse Button
XBUTTON_ONE         - Mouse Side Button 1
XBUTTON_TWO         - Mouse Side Button 2

NOTE:
Mouse virtual keys are included in the UE4SS
Key table, but reliable mouse-button triggering
through RegisterKeyBind is not guaranteed.


------------------------------------------------------
8. WINDOWS / SYSTEM KEYS
------------------------------------------------------

LEFT_WIN        - Left Windows Key
RIGHT_WIN       - Right Windows Key
APPS            - Application / Context Menu Key
SLEEP           - Sleep Key

CANCEL          - Cancel / Control-Break
SELECT          - Select Key
PRINT           - Print Key
EXECUTE         - Execute Key
HELP            - Help Key


------------------------------------------------------
9. BROWSER KEYS
------------------------------------------------------

BROWSER_BACK        - Browser Back
BROWSER_FORWARD     - Browser Forward
BROWSER_REFRESH     - Browser Refresh
BROWSER_STOP        - Browser Stop
BROWSER_SEARCH      - Browser Search
BROWSER_FAVORITES   - Browser Favorites
BROWSER_HOME        - Browser Home


------------------------------------------------------
10. MEDIA / VOLUME KEYS
------------------------------------------------------

VOLUME_MUTE         - Mute Volume
VOLUME_DOWN         - Decrease Volume
VOLUME_UP           - Increase Volume

MEDIA_NEXT_TRACK    - Next Track
MEDIA_PREV_TRACK    - Previous Track
MEDIA_STOP          - Stop Media
MEDIA_PLAY_PAUSE    - Play / Pause Media

LAUNCH_MAIL         - Launch Email Application
LAUNCH_MEDIA_SELECT - Launch Media Application
LAUNCH_APP1         - Launch Application 1
LAUNCH_APP2         - Launch Application 2


------------------------------------------------------
11. INPUT METHOD EDITOR (IME) KEYS
------------------------------------------------------

IME_KANA            - Kana Mode
IME_HANGUEL         - Hanguel Mode (alias)
IME_HANGUL          - Hangul Mode
IME_ON              - IME On
IME_JUNJA           - Junja Mode
IME_FINAL           - Final Mode
IME_HANJA           - Hanja Mode
IME_KANJI           - Kanji Mode
IME_OFF             - IME Off

IME_CONVERT         - IME Convert
IME_NONCONVERT      - IME Non-Convert
IME_ACCEPT          - IME Accept
IME_MODECHANGE      - IME Mode Change
IME_PROCESS         - IME Process


------------------------------------------------------
12. SPECIAL / LEGACY KEYS
------------------------------------------------------

PACKET          - Unicode Packet Input
ATTN            - Attention Key
CRSEL           - Cursor Select
EXSEL           - Extend Selection
EREOF           - Erase EOF
PLAY            - Play Key
ZOOM            - Zoom Key
PA1             - PA1 Key

======================================================
]]
