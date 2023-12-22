// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC721Upgradeable.sol";
import "./ToadTraitConstants.sol";
import "./IToadzMetadata.sol";

interface IToadz is IERC721Upgradeable {

    function mint(address _to, ToadTraits calldata _traits) external returns(uint256);

    function adminSafeTransferFrom(address _from, address _to, uint256 _tokenId) external;

    function burn(uint256 _tokenId) external;
}
