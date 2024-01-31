// MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMWWWWMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM
// MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMW    WMMMMMMMMMMMMMMMMMMMMMMMWWWWWWW          WMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM
// MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMW  WWW  WMMMMMMMMMMMMMMMMMMMW                  WMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMW WMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM
// MMMMMMMWWWWWWWWMMMMMMMMMMMMMMMMMW MMMW  WMMMMW MMMMMMMMMMMMMWWWWWWMMW  WMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMW  MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM
// MMMMW            WMMMMMMMMMMMMMMW WMMW  WMMMM  WMMW  WMMMMMMMMMMMMMMW  WMMMMMW     WWMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMW  WMMMMMMMMMMMMMMMMMMMMMMMMMMMMMWMMMMMMMMMMMM
// MMW   WMMMMMMMMW  WMMMMMMMMMMMMMW WW   WMMMMM  WMMW K WMMMMMMMMMMMMMW  WMMMW           WWMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMW   WWWWWWMMMMMMMMMMMMMMMMMMMMMMW  MMMMMMMMW M
// MWW WMMMMMMMMMMW  WMMMMMMWWWMMMMW      WWWMMM  WMMW   WMMMMMMMMMMMMMW  WMMW  WMMMWWW     WMMMMMMMMMMMMW  WMWWWWMMMMMMMMMMWWWW          WWMMMMMMMMMMMMMMMMMMMMMW  WMMMMMMM  M
// MMW WMMMMMMMMMMW  MMMW         WW WMMMMMW  MM  WMMMMMMWWWW    WMMMMMW  WMMW  WMMMMMMW    WMMMMMMMMMMWWW         MMMMMMMMWWWWWW    WWMMMMMMMMMMMMMMMMMMMMMMMMMMW   WMMMMMW  M
// MMW  WMMMMMMMWW   WMW  WMMMMMW     MMMMMMW WM  WMMMMWW     WW  WMMMMW  WMM   WMMMMMM    WMWWWMMMWWMMW W    WWW   MMMMMMMMMMMMMW   MMMMMMW     WMMMMWMMMMMMMW WW    WMMMM K M
// MMMW   WWWWWW  W  WM  WMMMMMMMM    WMMMMMW WMW WMMMW W   WMMMW  WMMMW  WMMW   WMMMMW    MMW WMMW  MMW W    MMMM  WMMMMMMMMMMMMW   WMMMW    WWW  WMWWWMWWWMMW WM WM  WMMW  WM
// MMMMMWW     WWWM  WW  WMMMMMMMW WW WMMMMM  WMW WMMW  MW  MMMMM  WMMMW  WMMMW         WMMMMW WMMW  MM  W   WMMMMW WMMMMMMMMMMMMM   WMMM   WMMMMW  WW WM  WMM  WM  MW  WMW  WM
// MWMMMMMMMMMMMMMM  WMW  WMMMW  WWMW WMMMW   MMW WMMW  MW  WMMMM   MMMW  WMMMMWWW  WWWMMMMMMW  MW   WW  W   WMMMMW  MMMMMMMMMMMMMW  WMMW   MMMMMW  WW WM  WMM  WM  MMW  W   MM
// M  MMMMMMMMMMMMW  WMMWWW   WWWMMMM  WWW  WMMMW WMMW  MW  WMMMMW WMMMW  WMMMMMMMMMMMMMMMMMMW         K W   WMMMMW  WMMMWWWWMMMMMW  WMMW   WMMWW   WM  W   WW  WM  MMMW    WMM
// MW  MMMMMMMMMMW   WMMMMMMMMMMMMMMW    WMMMMMMW WMMW WMW   MMMMWWMMMMW  WMMMMMMMMMMMMMMMMMMMMWWWWMMW  WW   WMMMMMWWMMMW K  MMMMMW  WMMMW         WMMW        WMM  WMMM    WMM
// MMW  WMMMMMMMM  WWMMMMMMMMMMMMMMMMMMMMMMMMMMMW WMMMWMMMWWWMMMMMMMMMMM  MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMWWMMMMMMMMMMMMW   WMMMMMW   WMMMMW     WWMMMMMWWMMWWWMMM  WMMMMWWWMMM
// MMMW  WWWWWW  WWMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMW    WMMMMMMMMMMMMMMMMMMMMMMMMMMWWMMMMMMMMMM
// MMMMM      WWMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMWWWWMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM
// MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMWWWWMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM

// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "./ERC721A.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./Signer.sol";

contract GoblintownTownNFT is ERC721A, Ownable, ReentrancyGuard, Signer {
    bool public explorable = false;
    uint256 public explorableTown = 9999;
    uint256 public meeneth = 5000000000000000;
    uint256 public maxPerMeen = 5;
    mapping(address => uint256) public goblins;

    constructor() ERC721A("Goblintown.Town", "gOblIntOwn.TOWN") {}

    function _baseURI() internal view virtual override returns (string memory) {
        return "ipfs://Qme81tb5B9KazFJEymMCsmP4DWG68V25q5ic2cvhrzF98K/";
    }

    function meen(uint256 meenAmount) external payable nonReentrant {
        uint256 allTown = totalSupply();
        require(meenAmount > 0, "nOt mEEntIng");
        require(meenAmount <= maxPerMeen, "dOn bE grEEdy");
        require(explorable, "bE pAtIEnt");
        require(allTown + 1 <= explorableTown, "sOwEE All mEEned");
        require(msg.sender == tx.origin, "nOt gOblIn");

        uint256 ethNeed = meenAmount * meeneth;
        if (goblins[msg.sender] < 1) {
            ethNeed -= meeneth;
            goblins[msg.sender] += 1;
        }
        require(msg.value >= ethNeed, "mOrEth");

        reeFundXtraa(msg.value);
        _safeMint(msg.sender, meenAmount);
    }

    function meenMany(address townOwner, uint256 _exploringTown)
        public
        onlyOwner
    {
        uint256 allTown = totalSupply();
        require(allTown + _exploringTown <= explorableTown);
        _safeMint(townOwner, _exploringTown);
    }

    function changeMaxPerMeen(uint256 _maxPerMeen) external onlyOwner {
        maxPerMeen = _maxPerMeen;
    }

    function makeExplorable(bool _explore) external onlyOwner {
        explorable = _explore;
    }

    function reeFundXtraa(uint256 _senderValue) private {
        uint256 _exceededValue = _senderValue - meeneth;

        if (_exceededValue > 0) {
            (bool success, ) = payable(msg.sender).call{value: _exceededValue}(
                ""
            );
            require(success, "Transfer failed");
        }
    }

    function reedimFund() public payable onlyOwner {
        (bool success, ) = payable(msg.sender).call{
            value: address(this).balance
        }("");
        require(success, "Transfer failed");
    }
}

