// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC1155Upgradeable.sol";

interface IBalancerCrystal is IERC1155Upgradeable {

    function mint(address _to, uint256 _id, uint256 _amount) external;

    function adminSafeTransferFrom(
        address _from,
        address _to,
        uint256 _id,
        uint256 _amount)
    external;

    function adminSafeBatchTransferFrom(
        address _from,
        address _to,
        uint256[] calldata _ids,
        uint256[] calldata _amounts)
    external;
}
