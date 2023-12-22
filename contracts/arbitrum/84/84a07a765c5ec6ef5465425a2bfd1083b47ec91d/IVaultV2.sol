// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import {VaultBond} from "./Structs.sol";

interface IVaultV2 {
    function stakeAmounts(address _token) external view returns (uint256);
    function poolAmounts(address _token) external view returns (uint256);
    function increasePoolAmount(address _indexToken, uint256 _amount) external;
    function decreasePoolAmount(address _indexToken, uint256 _amount) external;

    function reservedAmounts(address _token) external view returns (uint256);
    function increaseReservedAmount(address _token, uint256 _amount) external;
    function decreaseReservedAmount(address _token, uint256 _amount) external;

    function guaranteedAmounts(address _token) external view returns (uint256);
    function increaseGuaranteedAmount(address _indexToken, uint256 _amount) external;
    function decreaseGuaranteedAmount(address _indexToken, uint256 _amount) external;

    function distributeFee(
        bytes32 _key, 
        address _account, 
        uint256 _fee
    ) external;

    function takeAssetIn(
        address _account, 
        uint256 _amount, 
        address _token,
        bytes32 _key,
        uint256 _txType
    ) external;

    function takeAssetOut(
        bytes32 _key,
        address _account, 
        uint256 _fee, 
        uint256 _usdOut, 
        address _token, 
        uint256 _tokenPrice
    ) external;

    function takeAssetBack(
        address _account, 
        bytes32 _key,
        uint256 _txType
    ) external;

    function decreaseBond(bytes32 _key, address _account, uint256 _txType) external;

    function transferBounty(address _account, uint256 _amount) external;

    function ROLP() external view returns(address);

    function RUSD() external view returns(address);

    function totalROLP() external view returns(uint256);

    function updateBalance(address _token) external;

    //function updateBalances() external;

    function getTokenBalance(address _token) external view returns (uint256);

    //function getTokenBalances() external view returns (address[] memory, uint256[] memory);

    function stake(address _account, address _token, uint256 _amount) external;

    function unstake(address _tokenOut, uint256 _rolpAmount, address _receiver) external;

    function getBond(bytes32 _key, uint256 _txType) external view returns (VaultBond memory);

    // function getBondOwner(bytes32 _key, uint256 _txType) external view returns (address);

    // function getBondToken(bytes32 _key, uint256 _txType) external view returns (address);

    // function getBondAmount(bytes32 _key, uint256 _txType) external view returns (uint256);

    function getTotalUSD() external view returns (uint256);

    // function convertRUSD(
    //     address _account,
    //     address _recipient, 
    //     address _tokenOut, 
    //     uint256 _amount
    // ) external;
}
