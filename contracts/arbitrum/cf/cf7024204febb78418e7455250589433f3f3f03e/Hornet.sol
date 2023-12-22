// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ERC20Upgradeable} from "./ERC20Upgradeable.sol";
import {Initializable} from "./Initializable.sol";
import {OwnableUpgradeable} from "./OwnableUpgradeable.sol";


contract Hornet is ERC20Upgradeable, OwnableUpgradeable {
    /// @notice Total max supply : 450k $HRT
    uint256 public constant MAX_SUPPLY = 450e21;
    /// @notice Transfers are not allowed if closed. 
    /// Trading will be opened when liquidity is added by the team
    bool public tradingIsOpen;
    /// @notice timestamp when trading will open
    uint256 public openDate;

    mapping(address => bool) public authorized;

    event TradingOpen(uint256 when);
    event AuthorizedAddress(address who);

    function initialize (
            address[] memory wallets,
            uint256[] memory shares
        ) public initializer 
    {

        __ERC20_init("HORNET", "HRT");
        __Ownable_init();
        /// safety check, the number of wallet must match the number of shares
        require(wallets.length == shares.length, "HORNET : Wrong size");
        /// authorize and mint tokens to wallets
        for (uint i; i<wallets.length; i++) {
            authorizeAddress(wallets[i]);
            _mint(wallets[i], shares[i]);
        }
        /// safety check, total mint must be equal to supply
        require(totalSupply() == MAX_SUPPLY,  "HORNET : Wrong supply");

    }

    function _beforeTokenTransfer (
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        if (!tradingIsOpen) require (authorized[from] || authorized[to], "HORNET : Trading is currently closed");
    }

    /** ONLY OWNER **/

    function openTrading() external onlyOwner {
        /// safety check
        require(!tradingIsOpen, "HORNET : trafing already open");

        tradingIsOpen = true;
        openDate = block.timestamp;

        emit TradingOpen(openDate);
    }

    function authorizeAddress(address who) public onlyOwner {
        /// safety check
        require(!authorized[who], "HORNET : address already authorized");
        
        authorized[who] = true;

        emit AuthorizedAddress(who);
    }

}
