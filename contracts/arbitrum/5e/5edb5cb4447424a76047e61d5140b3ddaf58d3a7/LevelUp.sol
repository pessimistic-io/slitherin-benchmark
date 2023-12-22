// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./IERC20.sol";
import "./ERC721_IERC721.sol";
import "./IMetaX.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./SafeMath.sol";

contract LevelUp is Ownable, ReentrancyGuard {
    using SafeMath for uint256;

/** Smart Contracts Preset **/
    /* $MetaX */
    address public MetaX_Addr;
    IERC20 public MX;

    function setMetaX(address _MetaX_Addr) public onlyOwner {
        MetaX_Addr = _MetaX_Addr;
        MX = IERC20(_MetaX_Addr);
    }

    /* Vault */
    address public Vault;

    function setVault(address _Vault) public onlyOwner {
        Vault = _Vault;
    }

    /* PlanetMan */
    address public PlanetMan_Addr;
    IERC721 public PM;

    function setPlanetMan(address _PlanetMan_Addr) public onlyOwner {
        PlanetMan_Addr = _PlanetMan_Addr;
        PM = IERC721(_PlanetMan_Addr);
    }

    /* XPower */
    address public XPower_Addr;
    IMetaX public XP;

    function setXPower(address _XPower_Addr) public onlyOwner {
        XPower_Addr = _XPower_Addr;
        XP = IMetaX(_XPower_Addr);
    }

    /* BlackHole SBT */
    address public BlackHole_Addr;
    IMetaX public BH;

    function setBlackHole(address _BlackHole_Addr) public onlyOwner {
        BlackHole_Addr = _BlackHole_Addr;
        BH = IMetaX(_BlackHole_Addr);
    }

    /* Excess Claimable User */
    address public ExcessClaimableUser;
    IMetaX public ECU;

    function setExcessClaimableUser(address _ExcessClaimableUser) public onlyOwner {
        ExcessClaimableUser = _ExcessClaimableUser;
        ECU = IMetaX(_ExcessClaimableUser);
    }

    /* Excess Claimable Builder */
    address public ExcessClaimableBuilder;
    IMetaX public ECB;

    function setExcessClaimableBuilder(address _ExcessClaimableBuilder) public onlyOwner {
        ExcessClaimableBuilder = _ExcessClaimableBuilder;
        ECB = IMetaX(_ExcessClaimableBuilder);
    }

/** Price in $MetaX **/
    uint256[] public consume = [
         10000 ether, 
         25000 ether, 
         45000 ether, 
         65000 ether, 
        100000 ether, 
        200000 ether, 
        300000 ether, 
        400000 ether, 
        500000 ether
    ];

    uint256 public T0 = 1676332800; /* Genesis time @Feb 14th 2023 */

    function Halve() public onlyOwner {
        require(block.timestamp >= T0 + 730 days, "Level Up: Halving every 2 years.");
        for (uint256 i=0; i<consume.length; i++) {
            consume[i] = consume[i].div(2);
        }
        T0 += 730 days;
    }

/** Level Up PlanetMan **/
    /* Level up requirement in POSW for PlanetMan */
    uint256[] public level_PM = [
          3000, 
         10000, 
         20000, 
         30000, 
         50000, 
         80000, 
        150000, 
        300000, 
        500000
    ];

    function levelUp_PM(uint256 _tokenId) public payable nonReentrant {
        require(PM.ownerOf(_tokenId) == msg.sender, "LevelUp: You are not the owner of this PlanetMan NFT.");
        uint256 _level = XP.getLevel(_tokenId);
        uint256 _POSW = XP.getPOSW(_tokenId);
        uint256 _consume = consume[_level];
        uint256 _excess = ECU.getExcess(msg.sender);
        require(_level < 9, "LevelUp: You have reached the highest level.");
        require(_POSW >= level_PM[_level], "LevelUp: You are not qualified for level up.");
        require(MX.balanceOf(msg.sender) + _excess >= _consume, "LevelUp: You don't have enough $MetaX to finish the level up.");

        if (_excess >= _consume) {
            ECU.consumeExcess(msg.sender, _consume);
        } else {
            uint256 _Consume = _consume - _excess;
            ECU.consumeExcess(msg.sender, _excess);
            MX.transferFrom(msg.sender, Vault, _Consume);
        }
        
        XP.levelUp(_tokenId);
        emit levelUpRecord_PM(msg.sender, _tokenId, _level+1, block.timestamp);
    }

    event levelUpRecord_PM (address user, uint256 _tokenId, uint256 newLevel, uint256 time);

/** Level Up BlackHole **/
    /* Level up requirement in POSW of BlackHole */
    uint256[] public level_BH = [
          300000, 
         1000000, 
         2000000, 
         3000000, 
         5000000, 
         8000000, 
        15000000, 
        30000000, 
        50000000
    ];

    function levelUp_BH(uint256 _tokenId) public payable nonReentrant {
        uint256 _level = BH.getLevel(_tokenId);
        uint256 _POSW = BH.getPOSW_Builder(_tokenId);
        uint256 _consume = consume[_level];
        uint256 _excess = ECB._getExcess(_tokenId);
        require(IERC721(BlackHole_Addr).ownerOf(_tokenId) == msg.sender, "BlackHole: You are not the owner of this BlackHole SBT.");
        require(_level < 9, "BlackHole: You have reached the highest level.");
        require(_POSW >= level_BH[_level], "BlackHole: You are not qualified for level up.");

        require(MX.balanceOf(msg.sender) + _excess >= _consume, "BlackHole: You don't have enough $MetaX to finish the level up.");

        if (_excess >= _consume) {
            ECB._consumeExcess(_tokenId, _consume);
        } else {
            uint256 _Consume = _consume - _excess;
            ECB._consumeExcess(_tokenId, _excess);
            MX.transferFrom(msg.sender, Vault, _Consume);
        }

        BH.levelUp(_tokenId);
        emit levelUpRecord_BH(msg.sender, _tokenId, _level+1, block.timestamp);
    }

    event levelUpRecord_BH (address user, uint256 _tokenId, uint256 newLevel, uint256 time);
}
