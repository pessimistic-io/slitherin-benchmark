// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./IPriceOracle.sol";
import "./PoolStorage.sol";

abstract contract IPool {

    function enterCollateral(address _collateral) external virtual;
    function exitCollateral(address _collateral) external virtual;

    function deposit(address _collateral, uint _amount, address _account) external virtual;
    function depositWithPermit(
        address _collateral, 
        uint _amount,
        address _account,
        uint _approval,
        uint _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external virtual;
    function depositETH(address _account) external virtual payable;
    function withdraw(address _collateral, uint _amount, bool unwrap) external virtual;

    /* -------------------------------------------------------------------------- */
    /*                               Admin Functions                              */
    /* -------------------------------------------------------------------------- */
    function updateSynth(address _synth, DataTypes.Synth memory _params) external virtual;
    function updateCollateral(address _collateral, DataTypes.Collateral memory _params) external virtual;
    function removeSynth(address _synth) external virtual;
    function addSynth(address _synth, DataTypes.Synth memory _params) external virtual;

    /* -------------------------------------------------------------------------- */
    /*                               View Functions                               */
    /* -------------------------------------------------------------------------- */
    function getAccountLiquidity(address _account) external virtual view returns(DataTypes.AccountLiquidity memory liq);
    function getTotalDebtUSD() external virtual view returns(uint totalDebt);
    function getUserDebtUSD(address _account) external virtual view returns(uint);
    function supportsInterface(bytes4 interfaceId) external virtual view returns (bool);

    /* -------------------------------------------------------------------------- */
    /*                              Internal Functions                            */
    /* -------------------------------------------------------------------------- */
    function mint(address _synth, uint _amount, address _to) external virtual returns(uint);
    function burn(address _synth, uint _amount) external virtual returns(uint);
    function swap(address _synthIn, uint _amount, address _synthOut, DataTypes.SwapKind _kind, address _to) external virtual returns(uint[2] memory);
    function liquidate(address _synthIn, address _account, uint _amountIn, address _outAsset) external virtual;

    /* -------------------------------------------------------------------------- */
    /*                                 Events                                     */
    /* -------------------------------------------------------------------------- */
    event IssuerAllocUpdated(uint issuerAlloc);
    event PriceOracleUpdated(address indexed priceOracle);
    event FeeTokenUpdated(address indexed feeToken);
}
