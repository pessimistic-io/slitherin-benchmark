// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

import "./OwnableUpgradeable.sol";
import "./IRaribleRoyalties.sol";
import "./IERC2981.sol";

/**
 * @title Royalties Contract
 * Royalties spec via IERC2981
 */
abstract contract OwnableRoyalties is
    OwnableUpgradeable,
    IRaribleRoyalties,
    IERC2981
{
    // Superplastic is the owner/recipeint of royalties
    address payable private _recipeint;

    // Royality fee BPS (1/100ths of a percent, eg 1000 = 10%)
    uint16 private _feeBps;

    function __OwnableRoyalties_init() internal onlyInitializing {
        __OwnableRoyalties_init_unchained();
    }

    function __OwnableRoyalties_init_unchained() internal onlyInitializing {
        __Ownable_init();
        _recipeint = payable(msg.sender);
        _feeBps = 750;
    }

    function setRoyaltyOwner(address payable _royal) public onlyOwner {
        require(
            owner() == _msgSender(),
            "You are not the owner and can't set the royalties"
        );
        _recipeint = _royal;
    }

    // rarible royalties
    function getFeeRecipients(uint256 tokenId)
        public
        view
        override
        returns (address payable[] memory)
    {
        address payable[] memory ret = new address payable[](1);
        ret[0] = payable(_recipeint);
        return ret;
    }

    // rarible royalties
    function getFeeBps(uint256 tokenId)
        public
        view
        override
        returns (uint256[] memory)
    {
        uint256[] memory ret = new uint256[](1);
        ret[0] = uint256(_feeBps);
        return ret;
    }

    // ---
    // More royalities (mintable?) / EIP-2981
    // ---
    function royaltyInfo(uint256 tokenId)
        external
        view
        override
        returns (address receiver, uint256 amount)
    {
        return (_recipeint, uint256(_feeBps) * 100);
    }
}

