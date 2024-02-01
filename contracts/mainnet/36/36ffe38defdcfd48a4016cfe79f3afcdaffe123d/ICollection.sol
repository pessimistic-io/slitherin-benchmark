// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./IERC721Upgradeable.sol";

interface ICollection is IERC721Upgradeable {
    function buy(address _buyer, uint256 _quantity) external payable;

    function price() external view returns (uint256);
}
