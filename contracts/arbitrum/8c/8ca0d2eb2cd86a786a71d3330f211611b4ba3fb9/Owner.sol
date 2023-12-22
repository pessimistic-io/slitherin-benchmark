// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "./Payments.sol";

import "./Ownable.sol";

contract Owner is Ownable, Payments {
    /// @notice Proxy contract constructor, sets permit2 and weth addresses
    /// @param _permit2 Permit2 contract address
    /// @param _weth WETH9 contract address
    constructor(Permit2 _permit2, IWETH9 _weth) Payments(_permit2, _weth) {}

    /// @notice Withdraws fees and transfers them to owner
    /// @param _recipient Address of the destination receiving the fees
    function withdrawAdmin(address _recipient) public onlyOwner {
        require(address(this).balance > 0);

        _sendETH(_recipient, address(this).balance);
    }
}

