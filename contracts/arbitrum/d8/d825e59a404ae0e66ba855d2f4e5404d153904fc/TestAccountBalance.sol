// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.7.6;
pragma abicoder v2;

import "./AccountBalance.sol";

contract TestAccountBalance is AccountBalance {
    using AddressUpgradeable for address;

    uint256 private _testBlockTimestamp;

    // copy paste from AccountBalance.initialize to avoid it to be public
    function __TestAccountBalance_init(address clearingHouseConfigArg) external initializer {
        // ClearingHouseConfig address is not contract
        require(clearingHouseConfigArg.isContract(), "AB_ENC");

        __ClearingHouseCallee_init();

        _clearingHouseConfig = clearingHouseConfigArg;
    }

    function setBlockTimestamp(uint256 blockTimestamp) external {
        _testBlockTimestamp = blockTimestamp;
    }

    function getBlockTimestamp() external view returns (uint256) {
        return _testBlockTimestamp;
    }

    function _blockTimestamp() internal view override returns (uint256) {
        return _testBlockTimestamp;
    }

    function getNetQuoteBalanceAndPendingFee(
        address trader
    ) external view returns (int256 netQuoteBalance, uint256 pendingFee) {
        return _getNetQuoteBalanceAndPendingFee(trader);
    }

    function testModifyOwedRealizedPnl(address trader, int256 owedRealizedPnlDelta) external {
        _modifyOwedRealizedPnl(trader, owedRealizedPnlDelta);
    }

    function testMarketMultiplier(
        address baseToken,
        uint256 longMultiplierX10_18,
        uint256 shortMultiplierX10_18
    ) external {
        if (_marketMap[baseToken].longMultiplierX10_18 == 0) {
            _marketMap[baseToken].longMultiplierX10_18 = 1e18;
        }
        if (_marketMap[baseToken].shortMultiplierX10_18 == 0) {
            _marketMap[baseToken].shortMultiplierX10_18 = 1e18;
        }
        _marketMap[baseToken].longMultiplierX10_18 = longMultiplierX10_18;
        _marketMap[baseToken].shortMultiplierX10_18 = shortMultiplierX10_18;
    }
}

