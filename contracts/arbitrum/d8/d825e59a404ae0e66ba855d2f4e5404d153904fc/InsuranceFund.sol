// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.7.6;

import { AddressUpgradeable } from "./AddressUpgradeable.sol";
import { SignedSafeMathUpgradeable } from "./SignedSafeMathUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "./ReentrancyGuardUpgradeable.sol";
import { IERC20Upgradeable } from "./IERC20Upgradeable.sol";
import { PerpMath } from "./PerpMath.sol";
import { PerpSafeCast } from "./PerpSafeCast.sol";
import { InsuranceFundStorageV1 } from "./InsuranceFundStorage.sol";
import { PerpSafeCast } from "./PerpSafeCast.sol";
import { InsuranceFundStorageV2 } from "./InsuranceFundStorage.sol";
import { OwnerPausable } from "./OwnerPausable.sol";
import { IInsuranceFund } from "./IInsuranceFund.sol";
import { IVault } from "./IVault.sol";

// never inherit any new stateful contract. never change the orders of parent stateful contracts
contract InsuranceFund is IInsuranceFund, ReentrancyGuardUpgradeable, OwnerPausable, InsuranceFundStorageV2 {
    using AddressUpgradeable for address;
    using SignedSafeMathUpgradeable for int256;
    using PerpMath for int256;
    using PerpSafeCast for int256;
    using PerpSafeCast for uint256;

    //
    // MODIFIER
    //

    function _requireOnlyClearingHouse() internal view {
        // only AccountBalance
        require(_msgSender() == _clearingHouse, "RF_OCH");
    }

    function initialize(address tokenArg) external initializer {
        // token address is not contract
        require(tokenArg.isContract(), "IF_TNC");

        __ReentrancyGuard_init();
        __OwnerPausable_init();

        _token = tokenArg;
    }

    function setVault(address vaultArg) external onlyOwner {
        // vault is not a contract
        require(vaultArg.isContract(), "IF_VNC");
        _vault = vaultArg;
        emit VaultChanged(vaultArg);
    }

    function setClearingHouse(address clearingHouseArg) external {
        _clearingHouse = clearingHouseArg;
        emit ClearingHouseChanged(clearingHouseArg);
    }

    //
    // EXTERNAL VIEW
    //

    /// @inheritdoc IInsuranceFund
    function getToken() external view override returns (address) {
        return _token;
    }

    /// @inheritdoc IInsuranceFund
    function getVault() external view override returns (address) {
        return _vault;
    }

    function getClearingHouse() external view override returns (address) {
        return _clearingHouse;
    }

    //
    // PUBLIC VIEW
    //

    /// @inheritdoc IInsuranceFund
    function getInsuranceFundCapacity() public view override returns (int256) {
        address vault = _vault;
        address token = _token;

        int256 insuranceFundSettlementTokenValueX10_S = IVault(vault).getSettlementTokenValue(address(this));
        int256 insuranceFundWalletBalanceX10_S = IERC20Upgradeable(token).balanceOf(address(this)).toInt256();
        return insuranceFundSettlementTokenValueX10_S.add(insuranceFundWalletBalanceX10_S);
    }

    //
    function getRepegAccumulatedFund() external view override returns (int256) {
        return _accumulatedRepegFund;
    }

    function getRepegDistributedFund() external view override returns (int256) {
        return _distributedRepegFund;
    }

    // internal function

    function _addRepegFund(uint256 fund) internal {
        _accumulatedRepegFund = _accumulatedRepegFund.add(fund.toInt256());
    }

    function _distributeRepegFund(int256 fund) internal {
        _distributedRepegFund = _distributedRepegFund.add(fund);
        // RF_LF: limit fund
        require(_distributedRepegFund <= _accumulatedRepegFund, "RF_LF");
    }

    // external function

    function addRepegFund(uint256 fund) external override {
        _requireOnlyClearingHouse();
        _addRepegFund(fund);
    }

    function repegFund(int256 fund) external override {
        _requireOnlyClearingHouse();
        _distributeRepegFund(fund);
    }
}

