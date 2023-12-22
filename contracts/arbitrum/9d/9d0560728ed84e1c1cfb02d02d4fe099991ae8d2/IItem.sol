// SPDX-License-Identifier: MIT LICENSE

pragma solidity ^0.8.0;
import "./IERC1155Upgradeable.sol";

interface IItem is IERC1155Upgradeable {
    struct ItemConfig {
        uint8 itemType;
        uint32 itemId;
        uint32 value;
        uint256 price;
        string name;
        string des;
    }

    function getConfig(uint256 _itemId) external view returns(ItemConfig memory);
    function burn(address _account, uint256 _itemId, uint256 _amount) external;
}
