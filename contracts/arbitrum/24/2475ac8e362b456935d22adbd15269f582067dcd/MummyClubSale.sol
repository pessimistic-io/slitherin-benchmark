// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import "./SafeERC20.sol";


import "./ReentrancyGuard.sol";
import "./Ownable.sol";
import "./IVester.sol";
import "./MummyClubNFT.sol";

contract MummyClubSale is Ownable, ReentrancyGuard {

    uint256 public constant MAX_MMC_PURCHASE = 20; // max purchase per txn
    uint256 public constant MAX_MMC = 5000; // max of 5000

    // State variables
    address public communityFund;
    address public mmyVester;
    address public esMMY;
    MummyClubNFT public mummyClubNFT;

    string public MMC_PROVENANCE = "";
    uint256 public mmcPrice = 75000000000000000 ; // 0.075 ETH
    uint256 public mmcPower = 5000; // 5000 power
    uint256 public esMMYBonus = 40e18; // 40 esMMY
    uint256 public totalVolume;
    uint256 public totalPower;
    uint256 public totalBonus;

    uint256 public stepEsMMY = 10000; // 1.00
    uint256 public stepPrice = 10000; // 1.00
    uint256 public stepPower = 9900; // 0.99
    uint256 public step = 100; //

    bool public saleIsActive = false; // determines whether sales is active

    event AssetMinted(address account, uint256 tokenId, uint256 power, uint256 bonus);

    constructor(address _communityFund, address _esMMY, address _mmyVester) {
        mummyClubNFT = new MummyClubNFT(address(this));
        communityFund = _communityFund;
        esMMY = _esMMY;
        mmyVester = _mmyVester;
        mummyClubNFT.transferOwnership(msg.sender);
    }


    // get current price and power
    function getCurrentPP() public view returns (uint256 _mccPrice, uint256 _mccPower, uint256 _esMMYBonus) {
        _mccPrice = mmcPrice;
        _mccPower = mmcPower;
        _esMMYBonus = esMMYBonus;
        uint256 _totalSupply = mummyClubNFT.totalSupply();
        uint256 modulus = mummyClubNFT.totalSupply() % step;
        if (modulus == 0 && _totalSupply != 0) {
            _mccPrice = (mmcPrice * stepPrice) / 10000;
            _mccPower = (mmcPower * stepPower) / 10000;
            _esMMYBonus = (esMMYBonus * stepEsMMY) / 10000;
        }
    }

    /* ========== External public sales functions ========== */

    // @dev mints meerkat for the general public
    function mintMummyClub(uint256 numberOfTokens) external payable nonReentrant returns (uint256 _totalPrice, uint256 _totalPower, uint256 _totalBonus) {
        require(saleIsActive, 'Sale Is Not Active');
        // Sale must be active
        require(numberOfTokens <= MAX_MMC_PURCHASE, 'Exceed Purchase');
        // Max mint of 1
        require(mummyClubNFT.totalSupply() + numberOfTokens <= MAX_MMC);
        for (uint i = 0; i < numberOfTokens; i++) {
            if (mummyClubNFT.totalSupply() < MAX_MMC) {
                (mmcPrice, mmcPower, esMMYBonus) = this.getCurrentPP();
                _totalPrice = _totalPrice + mmcPrice;
                uint256 id = mummyClubNFT.mint(mmcPower, msg.sender);
                emit AssetMinted(msg.sender, id, mmcPower, esMMYBonus);
                IERC20(esMMY).transfer(msg.sender, esMMYBonus);
                IVester vester = IVester(mmyVester);
                vester.setBonusRewards(msg.sender, vester.bonusRewards(msg.sender) + esMMYBonus);
                _totalPower += mmcPower;
                _totalBonus += esMMYBonus;
            }
        }
        require(_totalPrice <= msg.value);
        if (msg.value > _totalPrice) {
            payable(msg.sender).transfer(msg.value - _totalPrice);
        }
        payable(communityFund).transfer(_totalPrice);
        totalVolume += _totalPrice;
        totalBonus += _totalBonus;
        totalPower += _totalPower;
    }

    function estimateAmount(uint256 numberOfTokens) external view returns (uint256 _totalPrice, uint256 _totalPower, uint256 _totalBonus) {
        uint256 _price = mmcPrice;
        uint256 _power = mmcPower;
        uint256 _bonus = esMMYBonus;
        uint256 _totalSupply = mummyClubNFT.totalSupply();
        for (uint i = 0; i < numberOfTokens; i++) {
            if (_totalSupply < MAX_MMC) {
                if (_totalSupply % step == 0 && _totalSupply != 0) {
                    _price = (_price * stepPrice) / 10000;
                    _power = (_power * stepPower) / 10000;
                    _bonus = (_bonus * stepEsMMY) / 10000;
                }
                _totalPrice += _price;
                _totalPower += _power;
                _totalBonus += _bonus;
                _totalSupply = _totalSupply + 1;
            } else {
                break;
            }
        }
    }


    // @dev withdraw funds
    function withdraw() external onlyOwner {
        uint balance = address(this).balance;
        payable(msg.sender).transfer(balance);
    }

    // @dev withdraw funds
    function withdrawERC20(address token) external onlyOwner {
        uint balance = IERC20(token).balanceOf(address(this));
        IERC20(token).transfer(msg.sender, balance);
    }

    // @dev flips the state for sales
    function flipSaleState() external onlyOwner {
        saleIsActive = !saleIsActive;
    }


    // @dev set insurance fund contract address
    function setCommunityFund(address _communityFund) public onlyOwner {
        communityFund = _communityFund;
    }
    // @dev set esMMY contract address
    function setEsMMY(address _esMMY) public onlyOwner {
        esMMY = _esMMY;
    }
    // @dev set mmyVester contract address
    function setMmyVester(address _mmyVester) public onlyOwner {
        mmyVester = _mmyVester;
    }

    // @dev sets sale info (price + power)
    function setSaleInfo(uint256 _price, uint256 _power, uint256 _esMMYBonus) external onlyOwner {
        mmcPrice = _price;
        mmcPower = _power;
        esMMYBonus = _esMMYBonus;
    }

    // @dev set increate Price And Power
    function setIncreaseInfo(uint256 _stepPrice, uint256 _stepPower, uint256 _step, uint256 _stepEsMMY) public onlyOwner {
        stepPrice = _stepPrice;
        stepPower = _stepPower;
        step = _step;
        stepEsMMY = _stepEsMMY;
    }


    // @dev set provenance once it's calculated
    function setProvenanceHash(string memory provenanceHash) public onlyOwner {
        MMC_PROVENANCE = provenanceHash;
    }
}
