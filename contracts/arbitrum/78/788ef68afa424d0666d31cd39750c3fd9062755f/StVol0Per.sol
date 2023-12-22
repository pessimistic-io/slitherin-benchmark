// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "./StVol.sol";

/**
 * @title StVol0Per
 */
contract StVol0Per is StVol {
    constructor(
        address _token,
        address _oracleAddress,
        address _adminAddress,
        address _operatorAddress,
        address _operatorVaultAddress,
        uint256 _commissionfee,
        bytes32 _priceId
    ) 
    StVol(
        _token,
        _oracleAddress,
        _adminAddress,
        _operatorAddress,
        _operatorVaultAddress,
        _commissionfee,
        0, // 0
        StVol.StrategyType.None, // None: Up & Down
        _priceId
    ) {}
}

