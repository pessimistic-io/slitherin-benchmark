// SPDX-License-Identifier: MIT

pragma solidity =0.8.17;
pragma experimental ABIEncoderV2;
import "./ERC721_IERC721.sol";

interface IVoucher is IERC721{
    function burn(uint256) external;
    function info(uint256) external view returns(address, uint256);
    function mint(address, uint256, uint256, bytes memory) external;
    function remove(uint256, address) external;
}
