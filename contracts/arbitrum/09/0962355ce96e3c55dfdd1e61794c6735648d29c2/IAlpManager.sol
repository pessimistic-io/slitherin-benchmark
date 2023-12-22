// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IAlpManager {

    event MintAlp(address indexed account, address indexed tokenIn, uint256 amountIn, uint256 alpOut);
    event BurnAlp(address indexed account, address indexed receiver, address indexed tokenOut, uint256 alpAmount, uint256 amountOut);
    event MintFee(
        address indexed account, address indexed tokenIn, uint256 amountIn,
        uint256 tokenInPrice, uint256 mintFeeUsd, uint256 alpAmount
    );
    event BurnFee(
        address indexed account, address indexed tokenOut, uint256 amountOut,
        uint256 tokenOutPrice, uint256 burnFeeUsd, uint256 alpAmount
    );
    event SupportedFreeBurn(address indexed account, bool supported);

    function ALP() external view returns (address);

    function coolingDuration() external view returns (uint256);

    function setCoolingDuration(uint256 coolingDuration_) external;

    function mintAlp(address tokenIn, uint256 amount, uint256 minAlp, bool stake) external;

    function mintAlpBNB(uint256 minAlp, bool stake) external payable;

    function burnAlp(address tokenOut, uint256 alpAmount, uint256 minOut, address receiver) external;

    function burnAlpBNB(uint256 alpAmount, uint256 minOut, address payable receiver) external;

    function addFreeBurnWhitelist(address account) external;

    function removeFreeBurnWhitelist(address account) external;

    function isFreeBurn(address account) external view returns (bool);

    function alpPrice() external view returns (uint256);

    function lastMintedTimestamp(address account) external view returns (uint256);
}

