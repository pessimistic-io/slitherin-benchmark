// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IAlpManager {
    function ALP() external view returns (address);

    function coolingDuration() external view returns (uint256);

    function setCoolingDuration(uint256 coolingDuration_) external;

    function mintAlp(address tokenIn, uint256 amount, uint256 minAlp, bool stake) external;

    function mintAlpBNB(uint256 minAlp, bool stake) external payable;

    function burnAlp(address tokenOut, uint256 alpAmount, uint256 minOut, address receiver) external;

    function burnAlpBNB(uint256 alpAmount, uint256 minOut, address payable receiver) external;

    function alpPrice() external view returns (uint256);

    function lastMintedTimestamp(address account) external view returns (uint256);
}
