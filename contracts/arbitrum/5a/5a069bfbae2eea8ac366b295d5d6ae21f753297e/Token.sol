// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./Ownable.sol";
import "./SupportToken.sol";

contract NetDexToken is ERC20, SupportToken {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    constructor() ERC20("NEX Token", "NEX") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        _mint(msg.sender, 10000000000e18);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        if (enableWhiteListBot) {
            if (isContract(from) && !whiteListAddressBot[from]) {
                revert("ERC20: contract from is not whitelist");
            }
            if (isContract(to) && !whiteListAddressBot[to]) {
                revert("ERC20: contract to is not whitelist");
            }
        }
        require(amount > 0, "ERC20: require amount greater than 0");
        require(
            blackListWallet[from] == false,
            "ERC20: address from is blacklist"
        );
        require(blackListWallet[to] == false, "ERC20: address to is blacklist");
        if (!enableSell && isContract(to) && !enableSellAddress[to]) {
            revert("ERC20: can not transfer token");
        }
        if (isEnable == true && from != address(0)) {
            uint256 amountLock = checkTransfer(from);
            if (balanceOf(from) < amountLock + amount) {
                revert(
                    "ERC20: Some available balance has been unlock gradually"
                );
            }
        }
        super._beforeTokenTransfer(from, to, amount);
    }
}

