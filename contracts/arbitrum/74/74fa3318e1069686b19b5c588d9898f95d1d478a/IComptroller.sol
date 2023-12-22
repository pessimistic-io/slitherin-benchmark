// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;
pragma abicoder v2;

interface IComptroller {
    event MintToken(
        uint256 tokenRate,
        uint256 amountMinted,
        address indexed token
    );

    event BurnToken(uint256 amountBurned, address indexed token);

    function mintWithEth(
        uint256 tokenAmountDesired,
        address fxToken,
        uint256 deadline,
        address referral
    ) external payable;

    function mint(
        uint256 amountDesired,
        address fxToken,
        address collateralToken,
        uint256 collateralAmount,
        uint256 deadline,
        address referral
    ) external;

    function mintWithoutCollateral(
        uint256 tokenAmountDesired,
        address token,
        uint256 deadline,
        address referral
    ) external;

    function burn(
        uint256 amount,
        address token,
        uint256 deadline
    ) external;

    function setMinimumMintingAmount(uint256 amount) external;

    function minimumMintingAmount() external view returns (uint256);
}

