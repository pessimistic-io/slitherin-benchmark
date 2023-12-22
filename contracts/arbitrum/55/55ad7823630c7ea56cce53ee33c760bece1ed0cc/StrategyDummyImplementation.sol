// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "./IERC20.sol";

contract StrategyDummyImplementation {
    // basic & ReadModule
    function WETH_ADDR() external view returns (address) {}

    function WSTETH_ADDR() external view returns (address) {}

    function owner() external view returns (address) {}

    function lendingLogic() external view returns (address) {}

    function flashloanHelper() external view returns (address) {}

    function executor() external view returns (address) {}

    function vault() external view returns (address) {}

    function feeReceiver() external view returns (address) {}

    function safeAggregatedRatio() external view returns (uint256) {}

    function safeProtocolRatio(uint8 _protocolId) external view returns (uint256) {}

    function permissibleLimit() external view returns (uint256) {}

    function updateGasCompensation() external view returns (uint256) {}

    function leverageGasCompensation() external view returns (uint256) {}

    function exchangePrice() external view returns (uint256) {}

    function revenueExchangePriceInETH() external view returns (uint256) {}

    function revenue() external view returns (uint256) {}

    function revenueRate() external view returns (uint256) {}

    function availableProtocol(uint8 _protocolId) external view returns (bool) {}

    function rebalancer(address _rebalancer) external view returns (bool) {}

    function getETHByWstETH(uint256 _wstethAmount) public view returns (uint256) {}

    function getWstETHByETH(uint256 _ethAmount) public view returns (uint256) {}

    function getAvailableBorrowsETH(uint8 _protocolId) public view returns (uint256) {}

    function getAvailableWithdrawsWstETH(uint8 _protocolId) public view returns (uint256) {}

    function getProtocolAccountData(uint8 _protocolId)
        external
        view
        returns (uint256 wstEthAmount_, uint256 debtWstEthAmount_)
    {}

    function getNetAssetsInfo() public view returns (uint256, uint256, uint256, uint256) {}

    function getNetAssets() public view returns (uint256) {}

    function getNetAssetsInETH() public view returns (uint256) {}

    function getExchangePriceInETH() public view returns (uint256) {}

    function getCurrentExchangePriceInETH() public view returns (uint256) {}

    function getProtocolNetAssets(uint8 _protocolId) public view returns (uint256) {}

    function getProtocolRatio(uint8 _protocolId) public view returns (uint256) {}

    function getProtocolCollateralRatio(uint8 _protocolId) public view returns (uint256 protocolRatio_, bool isOK_) {}

    function getProtocolLeverageAmount(uint8 _protocolId, bool _isDepositOrWithdraw, uint256 _depositOrWithdraw)
        public
        view
        returns (bool isLeverage_, uint256 amount_)
    {}

    function getCurrentExchangePrice() public view returns (uint256 newExchangePrice_, uint256 newRevenue_) {}

    function getVersion() public pure returns (string memory) {}

    // AdminModule
    function initialize(
        uint256 _revenueRate,
        uint256 _safeAggregatedRatio,
        uint256 _permissibleLimit,
        uint256[] memory _safeProtocolRatio,
        address[] memory _rebalancers,
        address _flashloanHelper,
        address _lendingLogic,
        address _feeReceiver
    ) external {}

    function setVault(address _vault) external {}

    function enterProtocol(uint8 _protocolId) external {}

    function exitProtocol(uint8 _protocolId) external {}

    function updateFeeReceiver(address _newFeeReceiver) public {}

    function updateLendingLogic(address _newLendingLogic) external {}

    function updateFlashloanHelper(address _newLendingLogic) external {}

    function updateRebalancer(address[] calldata _rebalancers, bool[] calldata _isAllowed) external {}

    function updateRevenueRate(uint256 _newRevenueRate) external {}

    function updateSafeAggregatedRatio(uint256 _newSafeAggregatedRatio) external {}

    function updatePermissibleLimit(uint256 _newPermissibleLimit) external {}

    function updateGasAmount(uint256 _newUpdateGasCompensation, uint256 _newLeverageGasCompensation) external {}

    function updateSafeProtocolRatio(uint8[] calldata _protocolId, uint256[] calldata _safeProtocolRatio) external {}

    function collectRevenue() external {}

    // LeverageModule
    function leverage(
        uint8 _protocolId,
        uint256 _deposit,
        uint256 _debtAmount,
        bytes calldata _swapData,
        uint256 _swapGetMin,
        uint256 _flashloanSelector
    ) external {}

    function deleverage(
        uint8 _protocolId,
        uint256 _withdraw,
        uint256 _debtAmount,
        bytes calldata _swapData,
        uint256 _swapGetMin,
        uint256 _flashloanSelector
    ) external {}

    function deleverageAndWithdraw(
        uint8 _protocolId,
        uint256 _withdrawWst,
        bytes calldata _swapData,
        uint256 _swapGetMin,
        bool _isETH,
        uint256 _flashloanSelector
    ) external returns (uint256 withdrawGet_) {}

    function onFlashLoanOne(address _initiator, address _token, uint256 _amount, uint256 _fee, bytes calldata _params)
        external
        returns (bytes32)
    {}

    function updateExchangePrice() external returns (uint256 newExchangePrice_, uint256 newRevenue_) {}

    function getDeleverageAmount(uint256 _WstETHAmount, uint8 _protocolId) public view returns (uint256) {}

    // UserModule
    function deposit(uint256 _wstAmount) external returns (uint256 operateExchangePrice_) {}

    function withdraw(uint256 _shareFactor) external returns (uint256 userWstGet_) {}
}

