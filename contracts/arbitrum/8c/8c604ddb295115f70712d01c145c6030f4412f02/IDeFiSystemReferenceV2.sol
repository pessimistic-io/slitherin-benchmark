// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

interface IDeFiSystemReferenceV2 {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function increaseAllowance(address spender, uint256 addedValue) external returns (bool);
    function decreaseAllowance(address spender, uint256 subtractedValue) external returns (bool);
    function accountShareBalance(address account) external view returns (uint256);
    function burn(uint256 amount) external;
    function mintD2(uint256 timeAmount) external payable;
    function obtainRandomWalletAddress(uint256 someNumber) external view returns (address);
    function queryD2AmountExternalLP(uint256 amountNative) external view returns (uint256);
    function queryD2AmountInternalLP(uint256 amountNative) external view returns (uint256);
    function queryD2AmountOptimal(uint256 amountNative) external view returns (uint256);
    function queryNativeAmount(uint256 d2Amount) external view returns (uint256);
    function queryNativeFromTimeAmount(uint256 timeAmount) external view returns (uint256);
    function queryPoolAddress() external view returns (address);
    function queryPriceNative(uint256 amountNative) external view returns (uint256);
    function queryPriceInverse(uint256 d2Amount) external view returns (uint256);
    function queryRate() external view returns (uint256);
    function queryPublicReward() external view returns (uint256);
    function returnNativeWithoutSharing() external payable returns (bool);
    function splitSharesDinamicallyWithReward() external;
    function tryPoBet(uint256 someNumber) external;
    function buyD2() external payable returns (bool success);
    function sellD2(uint256 d2Amount) external returns (bool success);
    function flashMint(uint256 d2AmountToBorrow, bytes calldata data) external;
    function payFlashMintFee() external payable;
    function poolBalance() external returns (uint256);
}

