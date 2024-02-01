//SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "./IERC721Upgradeable.sol";

interface IOSB721 is IERC721Upgradeable {
    function mint(address _to) external returns (uint256);
    function mintWithRoyalty(address _to, address _receiverRoyaltyFee, uint96 _percentageRoyaltyFee) external returns (uint256);
    function setBaseURI(string memory _newUri) external;
    function setController(address _account, bool _allow) external;
    function royaltyInfo(uint256 _tokenId, uint256 _salePrice) external view returns (address, uint256);
}
