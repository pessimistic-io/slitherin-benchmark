pragma solidity ^0.5.16;

import "./DToken.sol";
import "./PriceOracle.sol";

contract UnitrollerAdminStorage {
    /**
    * @notice Administrator for this contract
    */
    address public admin;

    /**
    * @notice Pending administrator for this contract
    */
    address public pendingAdmin;

    /**
    * @notice Active brains of Unitroller
    */
    address public danktrollerImplementation;

    /**
    * @notice Pending brains of Unitroller
    */
    address public pendingDanktrollerImplementation;
}

contract DanktrollerV1Storage is UnitrollerAdminStorage {

    /**
     * @notice Oracle which gives the price of any given asset
     */
    PriceOracle public oracle;

    /**
     * @notice Multiplier used to calculate the maximum repayAmount when liquidating a borrow
     */
    uint public closeFactorMantissa;

    /**
     * @notice Multiplier representing the discount on collateral that a liquidator receives
     */
    uint public liquidationIncentiveMantissa;

    /**
     * @notice Max number of assets a single account can participate in (borrow or use as collateral)
     */
    uint public maxAssets;

    /**
     * @notice Per-account mapping of "assets you are in", capped by maxAssets
     */
    mapping(address => DToken[]) public accountAssets;

}

contract DanktrollerV2Storage is DanktrollerV1Storage {
    struct Market {
        /// @notice Whether or not this market is listed
        bool isListed;

        /**
         * @notice Multiplier representing the most one can borrow against their collateral in this market.
         *  For instance, 0.9 to allow borrowing 90% of collateral value.
         *  Must be between 0 and 1, and stored as a mantissa.
         */
        uint collateralFactorMantissa;

        /// @notice Per-market mapping of "accounts in this asset"
        mapping(address => bool) accountMembership;

        /// @notice Whether or not this market receives DANK
        bool isDanked;
    }

    /**
     * @notice Official mapping of dTokens -> Market metadata
     * @dev Used e.g. to determine if a market is supported
     */
    mapping(address => Market) public markets;


    /**
     * @notice The Pause Guardian can pause certain actions as a safety mechanism.
     *  Actions which allow users to remove their own assets cannot be paused.
     *  Liquidation / seizing / transfer can only be paused globally, not by market.
     */
    address public pauseGuardian;
    bool public _mintGuardianPaused;
    bool public _borrowGuardianPaused;
    bool public transferGuardianPaused;
    bool public seizeGuardianPaused;
    mapping(address => bool) public mintGuardianPaused;
    mapping(address => bool) public borrowGuardianPaused;
}

contract DanktrollerV3Storage is DanktrollerV2Storage {
    struct DankMarketState {
        /// @notice The market's last updated dankBorrowIndex or dankSupplyIndex
        uint224 index;

        /// @notice The block number the index was last updated at
        uint32 block;
    }

    /// @notice A list of all markets
    DToken[] public allMarkets;

    /// @notice The rate at which the flywheel distributes DANK, per block
    uint public dankRate;

    /// @notice The portion of dankRate that each market currently receives
    mapping(address => uint) public dankSpeeds;

    /// @notice The DANK market supply state for each market
    mapping(address => DankMarketState) public dankSupplyState;

    /// @notice The DANK market borrow state for each market
    mapping(address => DankMarketState) public dankBorrowState;

    /// @notice The DANK borrow index for each market for each supplier as of the last time they accrued DANK
    mapping(address => mapping(address => uint)) public dankSupplierIndex;

    /// @notice The DANK borrow index for each market for each borrower as of the last time they accrued DANK
    mapping(address => mapping(address => uint)) public dankBorrowerIndex;

    /// @notice The DANK accrued but not yet transferred to each user
    mapping(address => uint) public dankAccrued;
}


contract DanktrollerV4Storage is DanktrollerV3Storage {
    // @notice The borrowCapGuardian can set borrowCaps to any number for any market. Lowering the borrow cap could disable borrowing on the given market.
    address public borrowCapGuardian;

    // @notice Borrow caps enforced by borrowAllowed for each dToken address. Defaults to zero which corresponds to unlimited borrowing.
    mapping(address => uint) public borrowCaps;
}

contract DanktrollerV5Storage is DanktrollerV4Storage {
    /// @notice The portion of DANK that each contributor receives per block
    mapping(address => uint) public dankContributorSpeeds;

    /// @notice Last block at which a contributor's DANK rewards have been allocated
    mapping(address => uint) public lastContributorBlock;
}
