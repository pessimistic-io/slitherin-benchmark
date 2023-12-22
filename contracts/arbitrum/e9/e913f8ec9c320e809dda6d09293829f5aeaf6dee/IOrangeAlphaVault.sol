// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

interface IOrangeAlphaVault {
    /* ========== STRUCTS ========== */
    struct DepositType {
        uint256 assets;
        uint40 timestamp;
    }

    ///@dev this struct only used in memory
    struct Ticks {
        uint160 sqrtRatioX96;
        int24 currentTick;
        int24 lowerTick;
        int24 upperTick;
    }

    ///@dev this struct only used in memory and interfaces
    struct UnderlyingAssets {
        uint256 amount0Current;
        uint256 amount1Current;
        uint256 accruedFees0;
        uint256 accruedFees1;
        uint256 amount0Balance;
        uint256 amount1Balance;
    }

    /* ========== EVENTS ========== */
    event UpdateTicks(
        int24 lowerTick,
        int24 upperTick,
        int24 stoplossLowerTick,
        int24 stoplossUpperTick
    );

    // event UpdateDepositCap(uint256 depositCap, uint256 totalDepositCap);
    // event UpdateSlippage(uint16 slippageBPS, uint24 tickSlippageBPS);
    // event UpdateMaxLtv(uint32 maxLtv);

    event MerkleRootUpdated(bool enabled, bytes32 merkleRoot);

    event BurnAndCollectFees(
        uint256 burn0,
        uint256 burn1,
        uint256 fee0,
        uint256 fee1
    );

    /**
     * @notice actionTypes
     * 0. executed manually
     * 1. deposit
     * 2. redeem
     * 3. rebalance
     * 4. stoploss
     */
    event Action(
        uint8 indexed actionType,
        address indexed caller,
        uint256 totalAssets,
        uint256 totalSupply
    );

    /* ========== VIEW FUNCTIONS ========== */

    /**
     * @notice get total assets
     * @return totalManagedAssets
     */
    function totalAssets() external view returns (uint256 totalManagedAssets);

    /**
     * @notice convert assets to shares(shares is the amount of vault token)
     * @param assets amount of assets
     * @return shares
     */
    function convertToShares(uint256 assets)
        external
        view
        returns (uint256 shares);

    /**
     * @notice convert shares to assets
     * @param shares amount of vault token
     * @return assets
     */
    function convertToAssets(uint256 shares)
        external
        view
        returns (uint256 assets);

    /**
     * @notice compute new liquidity if rebalance
     * @param _newLowerTick new lower tick
     * @param _newUpperTick new upper tick
     * @param _newStoplossLowerTick new stoploss lower tick
     * @param _newStoplossUpperTick new stoploss upper tick
     * @return liquidity
     */
    function computeNewLiquidity(
        int24 _newLowerTick,
        int24 _newUpperTick,
        int24 _newStoplossLowerTick,
        int24 _newStoplossUpperTick
    ) external view returns (uint128 liquidity);

    /**
     * @notice get deposited amount and timestamp
     * @param account depositer address
     * @return assets
     * @return timestamp
     */
    function deposits(address account)
        external
        view
        returns (uint256 assets, uint40 timestamp);

    /**
     * @notice get total deposited amount
     * @return assets
     */
    function totalDeposits() external view returns (uint256 assets);

    /**
     * @notice get indivisuals deposit cap
     * @param account redeemer address
     * @return depositCap
     */
    function depositCap(address account)
        external
        view
        returns (uint256 depositCap);

    /**
     * @notice get total deposit cap
     * @return totalDepositCap
     */
    function totalDepositCap() external view returns (uint256 totalDepositCap);

    /* ========== EXTERNAL FUNCTIONS ========== */

    /**
     * @notice deposit assets and get vault token
     * @param assets amount of assets
     * @param receiver receiver address
     * @param minShares minimum amount of returned vault token
     * @param merkleProof merkle proof
     * @return shares
     */
    function deposit(
        uint256 assets,
        address receiver,
        uint256 minShares,
        bytes32[] calldata merkleProof
    ) external returns (uint256 shares);

    /**
     * @notice redeem vault token to assets
     * @param shares amount of vault token
     * @param receiver receiver address
     * @param owner owner address
     * @param minAssets minimum amount of returned assets
     * @return assets
     */
    function redeem(
        uint256 shares,
        address receiver,
        address owner,
        uint256 minAssets
    ) external returns (uint256 assets);

    /**
     * @notice emit action event
     */
    function emitAction() external;

    /**
     * @notice Change the range of underlying UniswapV3 position
     * @param newLowerTick The new lower bound of the position's range
     * @param newUpperTick The new upper bound of the position's range
     * @param _newStoplossLowerTick The new lower bound of the stoploss range
     * @param _newStoplossUpperTick The new upper bound of the stoploss range
     * @param minNewLiquidity minimum liqidiity
     */
    function rebalance(
        int24 newLowerTick,
        int24 newUpperTick,
        int24 _newStoplossLowerTick,
        int24 _newStoplossUpperTick,
        uint128 minNewLiquidity
    ) external;

    /**
     * @notice Remove all positions only when current price is out of range
     * @param inputTick Input tick for slippage checking
     */
    function stoploss(int24 inputTick) external;

    /**
     * @notice Remove all positions
     * @param inputTick Input tick for slippage checking
     */
    function removeAllPosition(int24 inputTick) external;
}

