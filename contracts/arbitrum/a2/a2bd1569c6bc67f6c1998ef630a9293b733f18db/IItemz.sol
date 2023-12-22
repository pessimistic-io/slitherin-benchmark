// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC1155Upgradeable.sol";

interface IItemz is IERC1155Upgradeable {

    function mint(address _to, uint256 _id, uint256 _amount) external;

    function mintBatch(address _to, uint256[] calldata _ids, uint256[] calldata _amounts) external;

    function burn(address _from, uint256 _id, uint256 _amount) external;
}
