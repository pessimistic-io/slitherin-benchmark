// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

interface IPTokenBAKC {
    function flashLoan(address receipient, uint256[] calldata nftIds, bytes memory data) external;
}
