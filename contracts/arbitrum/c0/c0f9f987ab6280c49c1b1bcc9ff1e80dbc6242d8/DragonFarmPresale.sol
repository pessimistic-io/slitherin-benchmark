// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";
import "./Ownable.sol";
import "./PaymentSplitter.sol";
import "./SafeMath.sol";
import "./FixedPointMathLib.sol";

contract DragonFarmPresale is ReentrancyGuard, Ownable, PaymentSplitter {

    using FixedPointMathLib for uint256;
    using SafeERC20 for IERC20;

    address public PresaleWallet;
    IERC20 public dragonFarmToken;

    uint256 public totalBought;
    uint256 public maxSale;

    bool public open = false;

    enum Tiers {
        FIRST,
        SECOND,
        THIRD
    }

    struct TiersInfo {
        uint256 price;
        uint256 currentSale;
        uint256 maxSale;
        uint256 minBuy;
        uint256 maxBuy;
    }

    mapping(Tiers => TiersInfo) public tiersInfo;

    modifier WhenOpen () {
        require(open, "Presale SALE CLOSES");
        _;
    }

    event PresaleOpen();
    event EnterPresale(address who, uint256 alloc);

    constructor (
        address _dragonFarm, 
        address _PresaleWallet,
        uint256 _maxSale,
        address[] memory payees,
        uint256[] memory shares
    )   PaymentSplitter (payees, shares) 
    {
        
        require(_dragonFarm != address(0));
        require(_PresaleWallet != address(0));

        dragonFarmToken = IERC20(_dragonFarm);
        PresaleWallet = _PresaleWallet;
        maxSale = _maxSale;

    }


    function getActiveTier() public view returns (Tiers) {
        Tiers activeTier;
        if (totalBought < tiersInfo[Tiers.FIRST].maxSale) {
            activeTier = Tiers.FIRST;
        }
        else {
            if (totalBought >= tiersInfo[Tiers.FIRST].maxSale 
            && totalBought < tiersInfo[Tiers.SECOND].maxSale ) {
                activeTier = Tiers.SECOND;
            }
            else {
                activeTier = Tiers.THIRD;
            }
        }
        return activeTier;
    }

    function getActiveTierInfos() public view returns(TiersInfo memory) {
        Tiers activeTier = getActiveTier();
        return tiersInfo[activeTier];
    }

    function enterPresale (uint256 amount) public payable 
    WhenOpen
    nonReentrant {

        Tiers tier = getActiveTier();

        require (totalBought + amount <= maxSale, "SOLD OUT");
        require (amount <= tiersInfo[tier].maxBuy, "INCORRECT AMOUNT");

        uint256 price = amount.fmul(tiersInfo[tier].price, FixedPointMathLib.WAD);

        require (msg.value >= price, "WRONG PRICE");

        totalBought += amount;
        tiersInfo[tier].currentSale += amount;

        dragonFarmToken.safeTransferFrom(PresaleWallet, _msgSender(), amount);
        emit EnterPresale(_msgSender(), amount);
    }

    function startPresale() external onlyOwner {
        open = true;
        emit PresaleOpen();
    }

    function updateTier(
        Tiers tier,
        uint256 _price,
        uint256 _maxSale,
        uint256 _minBuy,
        uint256 _maxBuy
    ) external onlyOwner {
        tiersInfo[tier].price = _price;
        tiersInfo[tier].maxSale = _maxSale;
        tiersInfo[tier].minBuy = _minBuy;
        tiersInfo[tier].maxBuy = _maxBuy;
    }
    
}
