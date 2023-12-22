// SPDX-License-Identifier: MIT
import "./IGToken.sol";

pragma solidity 0.8.17;

interface IGTokenLockedDepositNftDesign{
    function buildTokenURI(
        uint tokenId,
        IGToken.LockedDeposit memory lockedDeposit,
        string memory gTokenSymbol,
        string memory assetSymbol,
        uint8 numberInputDecimals,
        uint8 numberOutputDecimals
    ) external pure returns (string memory);
}
