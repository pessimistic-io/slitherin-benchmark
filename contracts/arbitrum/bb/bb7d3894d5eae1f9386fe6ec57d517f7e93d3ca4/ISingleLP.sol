// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "./IMintableERC20.sol";
import "./ILP.sol";

interface ISingleLP is ILP,IMintableERC20{
    function tokenReserve() external returns(uint256);
    function token() external view returns(address);
    function withdraw(address to, uint256 amount) external;

    function getSupplyWithPnl(address _dipxStorage, bool _includeProfit, bool _includeLoss) external view returns(uint256);
    function getPrice(address _dipxStorage,bool _includeProfit, bool _includeLoss) external view returns(uint256);
}

