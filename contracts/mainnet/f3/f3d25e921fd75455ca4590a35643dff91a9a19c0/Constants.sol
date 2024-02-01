pragma solidity ^0.5.17;

import "./Decimal.sol";
import "./Require.sol";

library Constants {
    /* Chain */
    uint256 private constant CHAIN_ID = 1; // Mainnet

    /* Bootstrapping */
    uint256 private constant BOOTSTRAPPING_PERIOD = 504; // 21 days
    uint256 private constant BOOTSTRAPPING_PRICE = 1078280614764947472; // Should be 0.1 difference between peg

    /* Oracle */
    address private constant CRV3 =
        address(0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490); // Anywhere the term CRV3 is refernenced, consider that as "peg", really
    uint256 private constant ORACLE_RESERVE_MINIMUM = 1e22; // 10,000 T

    /* Bonding */
    uint256 private constant INITIAL_STAKE_MULTIPLE = 1e6; // 100 T -> 100M TS

    /* Epoch */
    struct EpochStrategy {
        uint256 offset;
        uint256 start;
        uint256 period;
    }

    uint256 private constant CURRENT_EPOCH_OFFSET = 0;
    uint256 private constant CURRENT_EPOCH_START = 1669687200;
    uint256 private constant CURRENT_EPOCH_PERIOD = 3600; // 1 hour

    /* Forge */
    uint256 private constant ADVANCE_INCENTIVE_IN_3CRV = 75 * 10**18; // 75 3CRV
    uint256 private constant ADVANCE_INCENTIVE_IN_T_MAX = 5000 * 10**18; // 5000 T

    uint256 private constant FORGE_EXIT_LOCKUP_EPOCHS = 144; // 6 days
    uint256 private constant FORGE_EXIT_LOCKUP_SECONDS = FORGE_EXIT_LOCKUP_EPOCHS * CURRENT_EPOCH_PERIOD;

    /* Pool */
    uint256 private constant POOL_EXIT_LOCKUP_EPOCHS = 72; // 3 days
    uint256 private constant POOL_EXIT_LOCKUP_SECONDS = POOL_EXIT_LOCKUP_EPOCHS * CURRENT_EPOCH_PERIOD;

    /* Market */
    uint256 private constant COUPON_EXPIRATION = 4320; // 180 days
    uint256 private constant DEBT_RATIO_CAP = 20e16; // 20%

    /* Regulator */
    uint256 private constant SUPPLY_CHANGE_LIMIT = 1e16; // 1%
    uint256 private constant COUPON_SUPPLY_CHANGE_LIMIT = 2e16; // 2%
    uint256 private constant ORACLE_POOL_RATIO = 50; // 50%
    uint256 private constant TREASURY_RATIO = 0; // 0%

    /* Deployed */
    address private constant TREASURY_ADDRESS =
        address(0x0000000000000000000000000000000000000000);

    /**
     * Getters
     */

    function getCrv3Address() internal pure returns (address) {
        return CRV3;
    }

    function getOracleReserveMinimum() internal pure returns (uint256) {
        return ORACLE_RESERVE_MINIMUM;
    }

    function getCurrentEpochStrategy()
        internal
        pure
        returns (EpochStrategy memory)
    {
        return
            EpochStrategy({
                offset: CURRENT_EPOCH_OFFSET,
                start: CURRENT_EPOCH_START,
                period: CURRENT_EPOCH_PERIOD
            });
    }

    function getInitialStakeMultiple() internal pure returns (uint256) {
        return INITIAL_STAKE_MULTIPLE;
    }

    function getBootstrappingPeriod() internal pure returns (uint256) {
        return BOOTSTRAPPING_PERIOD;
    }

    function getBootstrappingPrice()
        internal
        pure
        returns (Decimal.D256 memory)
    {
        return Decimal.D256({value: BOOTSTRAPPING_PRICE});
    }

    function getAdvanceIncentive() internal pure returns (uint256) {
        return ADVANCE_INCENTIVE_IN_3CRV;
    }

    function getMaxAdvanceTIncentive() internal pure returns (uint256) {
        return ADVANCE_INCENTIVE_IN_T_MAX;
    }

    function getForgeExitLockupEpochs() internal pure returns (uint256) {
        return FORGE_EXIT_LOCKUP_EPOCHS;
    }

    function getForgeExitLockupSeconds() internal pure returns (uint256) {
        return FORGE_EXIT_LOCKUP_SECONDS;
    }

    function getPoolExitLockupEpochs() internal pure returns (uint256) {
        return POOL_EXIT_LOCKUP_EPOCHS;
    }

    function getPoolExitLockupSeconds() internal pure returns (uint256) {
        return POOL_EXIT_LOCKUP_SECONDS;
    }

    function getCouponExpiration() internal pure returns (uint256) {
        return COUPON_EXPIRATION;
    }

    function getDebtRatioCap() internal pure returns (Decimal.D256 memory) {
        return Decimal.D256({value: DEBT_RATIO_CAP});
    }

    function getSupplyChangeLimit()
        internal
        pure
        returns (Decimal.D256 memory)
    {
        return Decimal.D256({value: SUPPLY_CHANGE_LIMIT});
    }

    function getCouponSupplyChangeLimit()
        internal
        pure
        returns (Decimal.D256 memory)
    {
        return Decimal.D256({value: COUPON_SUPPLY_CHANGE_LIMIT});
    }

    function getOraclePoolRatio() internal pure returns (uint256) {
        return ORACLE_POOL_RATIO;
    }

    function getTreasuryRatio() internal pure returns (uint256) {
        return TREASURY_RATIO;
    }

    function getChainId() internal pure returns (uint256) {
        return CHAIN_ID;
    }

    function getTreasuryAddress() internal pure returns (address) {
        return TREASURY_ADDRESS;
    }
}
