//SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "./IERC1155Upgradeable.sol";

interface IOSB1155 is IERC1155Upgradeable {
    function mint(address _to, uint256 _amount) external returns (uint256);
    function mintWithRoyalty(address _to, uint256 _amount, address _receiverRoyaltyFee, uint96 _percentageRoyaltyFee) external returns (uint256);
    function mintBatch(uint256[] memory _amounts) external returns (uint256[] memory);
    function setBaseURI(string memory _newUri) external;
    function setController(address _account, bool _allow) external;
    function royaltyInfo(uint256 _tokenId, uint256 _salePrice) external view returns (address, uint256);
}
