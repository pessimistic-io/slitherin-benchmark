// SPDX-License-Identifier: None
pragma solidity ^0.8.0;
import "./IERC721.sol";

interface IArvinDegenNFT is IERC721 {
    function getRefundRatio(address user) external view returns (uint256);
}

