// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.17;

interface IPenpieDepositorHelper {
    function depositMarket(address _market,uint256 _amount) external;
    function balance(address _market, address _address) external view returns (uint256);
    function withdrawMarket(address _market, uint256 _amount) external;
}
