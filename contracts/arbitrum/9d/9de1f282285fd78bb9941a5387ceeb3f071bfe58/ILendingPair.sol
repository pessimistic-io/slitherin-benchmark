// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.19;

interface ILendingPair {
    function tokenA() external view returns (address);

    function tokenB() external view returns (address);

    function lpToken(address _token) external view returns (address);

    function transferLp(
        address _token,
        address _from,
        address _to,
        uint256 _amount
    ) external;

    function supplySharesOf(
        address _token,
        address _account
    ) external view returns (uint256);

    function totalSupplyShares(address _token) external view returns (uint256);

    function totalSupplyAmount(address _token) external view returns (uint256);

    function totalDebtShares(address _token) external view returns (uint256);

    function totalDebtAmount(address _token) external view returns (uint256);

    function debtOf(
        address _token,
        address _account
    ) external view returns (uint256);

    function supplyOf(
        address _token,
        address _account
    ) external view returns (uint256);

    function pendingSystemFees(address _token) external view returns (uint256);

    function supplyBalanceConverted(
        address _account,
        address _suppliedToken,
        address _returnToken
    ) external view returns (uint256);

    function initialize(
        address _lpTokenMaster,
        address _lendingController,
        address _feeRecipient,
        address _tokenA,
        address _tokenB
    ) external;
}

