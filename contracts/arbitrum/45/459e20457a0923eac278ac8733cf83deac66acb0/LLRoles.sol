/* SPDX-License-Identifier: MIT */

/**
 *   @title LL
 */

pragma solidity =0.7.6;

import "./Ownable.sol";

contract LLRoles is Ownable {
    address private _trader;

    constructor(address _admin, address _initialTrader) {
        _trader = _initialTrader;
        transferOwnership(_admin);
    }

    function trader() public view virtual returns (address) {
        return _trader;
    }

    function setTrader(address newTrader) public virtual onlyOwner {
        _trader = newTrader;
    }

    modifier onlyOwnerOrTrader() {
        require(
            trader() == _msgSender() || owner() == _msgSender(),
            "Caller is not the trader or the owner"
        );
        _;
    }
}

