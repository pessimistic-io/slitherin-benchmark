// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "./IERC721Enumerable.sol";

interface IFiat24Account is IERC721Enumerable {
    function historicOwnership(address) external view returns(uint256);
    function nickNames(uint256) external view returns(string memory);
    function isMerchant(uint256) external view returns(bool);
    function merchantRate(uint256) external view returns(uint256);
    function status(uint256) external view returns(uint256);
}
