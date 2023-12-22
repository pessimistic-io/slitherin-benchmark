// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "./YToken.sol";

contract XCYBER is YToken {
    uint256 public constant MAX_TOTAL_SUPPLY = 30_000_000 * 1e18;

    constructor(
        string memory _name,
        string memory _symbol,
        address _daoFund,
        address _devFund,
        address _treasuryFund,
        address _reserve
    ) YToken(_name, _symbol) {
        _mint(msg.sender, 20 * 1e18);
        _mint(_daoFund, 3_000_000 * 1e18); // 10%
        _mint(_devFund, 3_000_000 * 1e18); // 10%
        _mint(_treasuryFund, 3_000_000 * 1e18); // 10%
        _mint(_reserve, MAX_TOTAL_SUPPLY - 9_000_020 * 1e18);
    }

    // ===== OVERRIDEN =============

    function maxTotalSupply() internal pure override returns (uint256) {
        return MAX_TOTAL_SUPPLY;
    }
}

