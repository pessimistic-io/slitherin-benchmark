// SPDX-License-Identifier: MIT

pragma solidity >=0.5.0;

import "./IERC165.sol";
import { CreateParams } from "./ERC721Structs.sol";

/**
 * @dev Interface of the IOmniseaUniversalONFT: Universal ONFT Core through delegation
 */
interface IOmniseaERC721Psi is IERC165 {
    function initialize(CreateParams memory params, address _owner, address _dropsManagerAddress, address _scheduler, address _universalONFT) external;
    function mint(address _minter, uint24 _quantity, bytes32[] memory _merkleProof, uint8 _phaseId) external;
    function mintPrice(uint8 _phaseId) external view returns (uint256);
    function exists(uint256 tokenId) external view returns (bool);
    function owner() external view returns (address);
    function dropsManager() external view returns (address);
}

