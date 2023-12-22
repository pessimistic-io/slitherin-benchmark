// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./Address.sol";
import "./IERC20.sol";
import "./IERC20Metadata.sol";

import "./Denominations.sol";
import "./ERC20Helpers.sol";

import "./IFeeClaimer.sol";

contract FeeClaimerMock is IFeeClaimer {
    bool public fail;

    receive() external payable {
        // solhint-disable-previous-line no-empty-blocks
    }

    function mockFail(bool _fail) external {
        fail = _fail;
    }

    function augustusSwapper() external pure override returns (address) {
        return address(0);
    }

    function getBalance(address token, address) external view override returns (uint256) {
        return ERC20Helpers.balanceOf(token, address(this));
    }

    function registerFee(address, address, uint256) external override {
        // solhint-disable-previous-line no-empty-blocks
    }

    function withdrawAllERC20(address token, address recipient) external override returns (bool) {
        uint256 balance = ERC20Helpers.balanceOf(token, address(this));
        if (balance > 0) ERC20Helpers.transfer(token, recipient, balance);
        return !fail;
    }
}

