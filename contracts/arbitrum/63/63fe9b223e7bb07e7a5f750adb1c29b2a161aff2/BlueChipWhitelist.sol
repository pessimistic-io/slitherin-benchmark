// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import "./Ownable.sol";

import "./IHuntGameValidator.sol";
import "./IBlueChipWhitelist.sol";

contract BlueChipWhitelist is Ownable, IHuntGameValidator, IBlueChipWhitelist {
    /// chainId=>nft=>price in eth
    mapping(uint64 => mapping(address => uint256)) public override getBlueChipFloorPrice;

    /// user => game=> bullets bought by asset manager
    mapping(address => mapping(address => uint64)) public override bulletBought;

    uint8 public override toleratePriceRate = 20; //max 120% of floor price
    uint8 public override tolerateBulletRate = 30; //max 30% of total bullet in game

    function supportsInterface(bytes4 interfaceId) public pure returns (bool) {
        return
            interfaceId == IHuntGameValidator.isHuntGamePermitted.selector ||
            interfaceId == IHuntGameValidator.validateGame.selector ||
            interfaceId == IERC165.supportsInterface.selector;
    }

    function validateGame(IHuntGame _huntGame, address _sender, address hunter, uint64 _bullet) public {
        require(isHuntGamePermitted(_huntGame, _sender, hunter, _bullet), "VALIDATION_FAILED");
        bulletBought[hunter][address(_huntGame)] += _bullet;
    }

    function isHuntGamePermitted(
        IHuntGame _huntGame,
        address,
        address hunter,
        uint64 _bullet
    ) public view returns (bool) {
        uint256 soldPrice = _huntGame.bulletPrice() * _bullet;
        return
            _huntGame.getPayment() == address(0) &&
            bulletBought[hunter][address(_huntGame)] + _bullet <=
            (_huntGame.totalBullets() * tolerateBulletRate) / 100 &&
            soldPrice <=
            (getBlueChipFloorPrice[_huntGame.originChain()][_huntGame.nftContract()] * (100 + toleratePriceRate)) / 100;
    }

    /// dao
    function setBlueChipFloorPrice(uint64 originChain, address nft, uint256 price) public onlyOwner {
        getBlueChipFloorPrice[originChain][nft] = price;
    }

    function setToleratePriceRate(uint8 rate) public onlyOwner {
        toleratePriceRate = rate;
    }

    function setTolerateBulletRate(uint8 rate) public onlyOwner {
        tolerateBulletRate = rate;
    }
}

