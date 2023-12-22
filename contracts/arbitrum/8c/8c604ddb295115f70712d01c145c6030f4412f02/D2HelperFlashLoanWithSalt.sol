// SPDX-License-Identifier: MIT
pragma solidity >=0.8.10;

import "./FlashLoanSimpleReceiverBase.sol";
import "./IPoolAddressesProvider.sol";
import "./D2HelperWithSalt.sol";

contract D2HelperFlashLoanWithSalt is D2HelperWithSalt, FlashLoanSimpleReceiverBase {
    using Math for uint256;

    constructor(
        address _addressProvider,
        address _exchangeRouterAddress,
        address _d2TokenAddress,
        address _timeTokenAddress,
        address _rsdTokenAddress,
        address _sdrTokenAddress,
        bool _hasAlternativeSwap,
        address _owner
    )
        D2HelperWithSalt(
            _addressProvider,
            _exchangeRouterAddress,
            _d2TokenAddress,
            _timeTokenAddress,
            _rsdTokenAddress,
            _sdrTokenAddress,
            _hasAlternativeSwap,
            _owner
        )
        FlashLoanSimpleReceiverBase(IPoolAddressesProvider(_addressProvider))
    { }

    function _calculateFee(uint256 amount) internal virtual override returns (uint256) {
        if (!hasAlternativeSwap) {
            return amount + amount.mulDiv(POOL.FLASHLOAN_PREMIUM_TOTAL(), 10_000);
        } else {
            return amount + amount.mulDiv(SWAP_FEE, 10_000);
        }
    }

    function _startTraditionalSwap(address asset, uint256 amount) internal virtual override returns (bool) {
        address receiver = address(this);
        bytes memory params = "";
        uint16 referralCode = 0;

        try POOL.flashLoanSimple(receiver, asset, amount, params, referralCode) {
            return true;
        } catch {
            return false;
        }
    }

    function executeOperation(address asset, uint256 amount, uint256 premium, address initiator, bytes calldata params)
        external
        override
        internalOnly
        returns (bool)
    {
        IERC20 assetToBorrow = IERC20(asset);
        uint256 totalAmount = amount + premium;
        if (_performOperation(asset, amount)) {
            uint256 finalBalance = assetToBorrow.balanceOf(address(this));
            IWETH(asset).withdraw(finalBalance - totalAmount);
            payable(address(d2)).call{ value: finalBalance - totalAmount }("");
        }
        assetToBorrow.approve(address(POOL), totalAmount);
        return true;
    }

    function queryPoolAddress() external view virtual override returns (address) {
        return address(POOL);
    }
}

