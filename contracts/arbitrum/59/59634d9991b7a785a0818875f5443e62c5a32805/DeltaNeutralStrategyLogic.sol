// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IPoolAddressesProvider} from "./IPool.sol";
import {IPool} from "./IPool.sol";
import {IVariableDebtToken} from "./IVariableDebtToken.sol";
import {IAToken} from "./IAToken.sol";

import {IUniswapV3Factory} from "./IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "./IUniswapV3Pool.sol";
import {INonfungiblePositionManager} from "./INonfungiblePositionManager.sol";
import {FullMath} from "./FullMath.sol";
import {LiquidityAmounts} from "./LiquidityAmounts.sol";
import {TickMath} from "./TickMath.sol";

import {IWETH9} from "./IWETH9.sol";
import {IV3SwapRouter} from "./IV3SwapRouter.sol";
import {IAaveCheckerLogic} from "./IAaveCheckerLogic.sol";
import {IDeltaNeutralStrategyLogic} from "./IDeltaNeutralStrategyLogic.sol";

import {TransferHelper} from "./TransferHelper.sol";
import {BaseContract, Constants} from "./BaseContract.sol";

import {DexLogicLib} from "./DexLogicLib.sol";
import {AaveLogicLib} from "./AaveLogicLib.sol";

/// @title Delta Neutral Strategy Logic for DeFi protocols Uniswap and Aave.
/// @dev Contract to implement delta neutral strategy using Aave and Uniswap V3.
contract DeltaNeutralStrategyLogic is IDeltaNeutralStrategyLogic, BaseContract {
    // =========================
    // Constructor and constants
    // =========================

    IPoolAddressesProvider private immutable aavePoolAddressesProvider;

    IUniswapV3Factory private immutable dexFactory;
    IV3SwapRouter private immutable dexRouter;
    INonfungiblePositionManager internal immutable dexNftPositionManager;

    IWETH9 private immutable wrappedNative;

    uint128 private constant E18 = 1e18;
    uint128 private constant E14 = 1e14;
    uint32 private constant PERIOD = 60;

    /// @notice Initialize immutable variables in the contract.
    /// @param _poolAddressesProvider The Aave pool addresses provider.
    /// @param _dexFactory The Uniswap V3 factory.
    /// @param _dexNftPositionManager The position manager for Uniswap V3 NFTs.
    /// @param _wrappedNative The wrapped native token used for wrapping/unwrapping.
    /// @param _dexRouter The Uniswap V3 router.
    constructor(
        IPoolAddressesProvider _poolAddressesProvider,
        IUniswapV3Factory _dexFactory,
        INonfungiblePositionManager _dexNftPositionManager,
        IWETH9 _wrappedNative,
        IV3SwapRouter _dexRouter
    ) {
        aavePoolAddressesProvider = _poolAddressesProvider;

        dexFactory = _dexFactory;
        dexRouter = _dexRouter;
        dexNftPositionManager = _dexNftPositionManager;

        wrappedNative = _wrappedNative;
    }

    // =========================
    // Storage
    // =========================

    /// @dev Storage position for the DNS, to avoid collisions in storage.
    /// @dev Uses the "magic" constant to find a unique storage slot.
    bytes32 private immutable DNS_COMMON_STORAGE =
        keccak256("vault.dns.common.storage");

    /// @dev Common storage structure used to check initialization status.
    /// @dev One strategy per one vault.
    struct DeltaNeutralStrategyCommonStorage {
        bool initialized;
    }

    /// @dev Fetches the common storage for the delta neutral strategy.
    /// @dev Uses inline assembly to point to the specific storage slot.
    /// @return s The storage slot for CommonStorage structure.
    function _getCommonStorage()
        internal
        view
        returns (DeltaNeutralStrategyCommonStorage storage s)
    {
        bytes32 pointer = DNS_COMMON_STORAGE;
        assembly ("memory-safe") {
            s.slot := pointer
        }
    }

    /// @dev Fetches the delta neutral strategy storage without initialization check.
    /// @dev Uses inline assembly to point to the specific storage slot.
    /// Be cautious while using this.
    /// @param pointer Pointer to the strategy's storage location.
    /// @return s The storage slot for strategyStorage structure.
    function _getStorageUnsafe(
        bytes32 pointer
    ) internal pure returns (DeltaNeutralStrategyStorage storage s) {
        assembly ("memory-safe") {
            s.slot := pointer
        }
    }

    /// @dev Fetches the delta neutral strategy storage after checking initialization.
    /// @dev Reverts if the strategy is not initialized.
    /// @param pointer Pointer to the strategy's storage location.
    /// @return s The storage slot for DeltaNeutralStrategyStorage structure.
    function _getStorage(
        bytes32 pointer
    ) internal view returns (DeltaNeutralStrategyStorage storage s) {
        s = _getStorageUnsafe(pointer);

        if (!s.initialized) {
            revert DeltaNeutralStrategy_NotInitialized();
        }
    }

    // =========================
    // Initializer
    // =========================

    /// @inheritdoc IDeltaNeutralStrategyLogic
    function initialize(
        uint256 uniswapV3NftId,
        uint256 targetHealthFactor_e18,
        address supplyToken,
        address debtToken,
        bytes32 pointerToAaveChecker,
        bytes32 pointer
    ) external onlyVaultItself {
        DeltaNeutralStrategyStorage storage s = _getStorageUnsafe(pointer);

        _checkInitialize(s);
        _validateAaveCheckerPointer(pointerToAaveChecker);

        _setNewTargetHF(targetHealthFactor_e18, pointerToAaveChecker, s);

        _validateTokens(uniswapV3NftId, supplyToken, debtToken);
        s.uniswapV3NftId = uniswapV3NftId;

        IPool aavePool = IPool(aavePoolAddressesProvider.getPool());

        // set storage
        s.supplyTokenAave = IAToken(
            AaveLogicLib.aSupplyTokenAddress(supplyToken, aavePool)
        );
        s.debtTokenAave = IVariableDebtToken(
            AaveLogicLib.aDebtTokenAddress(debtToken, aavePool)
        );
        s.pointerToAaveChecker = pointerToAaveChecker;

        emit DeltaNeutralStrategyInitialize();
    }

    /// @inheritdoc IDeltaNeutralStrategyLogic
    function initializeWithMint(
        InitializeWithMintParams memory p,
        bytes32 pointer
    ) external onlyVaultItself {
        DeltaNeutralStrategyStorage storage s = _getStorageUnsafe(pointer);

        _checkInitialize(s);
        _validateAaveCheckerPointer(p.pointerToAaveChecker);

        _setNewTargetHF(p.targetHealthFactor_e18, p.pointerToAaveChecker, s);

        // validate balances for mint
        DexLogicLib.validateTokenBalance(p.supplyToken, p.supplyTokenAmount);
        DexLogicLib.validateTokenBalance(p.debtToken, p.debtTokenAmount);

        IPool aavePool = IPool(aavePoolAddressesProvider.getPool());

        // set storage
        s.supplyTokenAave = IAToken(
            AaveLogicLib.aSupplyTokenAddress(p.supplyToken, aavePool)
        );
        s.debtTokenAave = IVariableDebtToken(
            AaveLogicLib.aDebtTokenAddress(p.debtToken, aavePool)
        );

        s.pointerToAaveChecker = p.pointerToAaveChecker;

        if (p.minTick > p.maxTick) {
            (p.minTick, p.maxTick) = (p.maxTick, p.minTick);
        }

        s.uniswapV3NftId = DexLogicLib.mintNftMEVUnsafe(
            p.supplyTokenAmount,
            p.debtTokenAmount,
            p.minTick,
            p.maxTick,
            p.supplyToken,
            p.debtToken,
            p.poolFee,
            dexNftPositionManager
        );

        emit DeltaNeutralStrategyInitialize();
    }

    // =========================
    // Getters
    // =========================

    /// @inheritdoc IDeltaNeutralStrategyLogic
    function healthFactorsAndNft(
        bytes32 pointer
    )
        external
        view
        returns (uint256 targetHF, uint256 currentHF, uint256 uniswapV3NftId)
    {
        DeltaNeutralStrategyStorage storage s = _getStorageUnsafe(pointer);

        if (!s.initialized) {
            return (0, 0, 0);
        }

        targetHF = s.targetHealthFactor_e18;
        currentHF = AaveLogicLib.getCurrentHF(
            address(this),
            aavePoolAddressesProvider
        );
        uniswapV3NftId = s.uniswapV3NftId;
    }

    /// @inheritdoc IDeltaNeutralStrategyLogic
    function getTotalSupplyTokenBalance(
        bytes32 pointer
    ) external view returns (uint256) {
        DeltaNeutralStrategyStorage storage s = _getStorageUnsafe(pointer);

        if (!s.initialized) {
            return 0;
        }

        uint256 nftId = s.uniswapV3NftId;
        IAToken supplyTokenAave = s.supplyTokenAave;
        address supplyToken = supplyTokenAave.UNDERLYING_ASSET_ADDRESS();
        IVariableDebtToken debtTokenAave = s.debtTokenAave;
        address debtToken = debtTokenAave.UNDERLYING_ASSET_ADDRESS();

        (, , uint24 poolFee, , , ) = DexLogicLib.getNftData(
            nftId,
            dexNftPositionManager
        );

        IUniswapV3Pool dexPool = DexLogicLib.dexPool(
            supplyToken,
            debtToken,
            poolFee,
            dexFactory
        );

        return
            _getTotalSupplyTokenBalance(
                0,
                nftId,
                supplyTokenAave,
                supplyToken,
                debtTokenAave,
                debtToken,
                dexPool
            );
    }

    // =========================
    // Setters
    // =========================

    /// @inheritdoc IDeltaNeutralStrategyLogic
    function setNewTargetHF(
        uint256 newTargetHF,
        bytes32 pointer
    ) external onlyOwnerOrVaultItself {
        DeltaNeutralStrategyStorage storage s = _getStorage(pointer);

        _setNewTargetHF(newTargetHF, s.pointerToAaveChecker, s);
    }

    /// @inheritdoc IDeltaNeutralStrategyLogic
    function setNewNftId(
        uint256 newNftId,
        uint256 deviationThresholdE18,
        bytes32 pointer
    ) external onlyOwnerOrVaultItself {
        DeltaNeutralStrategyStorage storage s = _getStorage(pointer);

        IAToken supplyTokenAave = s.supplyTokenAave;
        address supplyToken = s.supplyTokenAave.UNDERLYING_ASSET_ADDRESS();

        _validateTokens(
            newNftId,
            supplyToken,
            s.debtTokenAave.UNDERLYING_ASSET_ADDRESS()
        );
        s.uniswapV3NftId = newNftId;

        _rebalance(supplyTokenAave, supplyToken, deviationThresholdE18, s);
    }

    // =========================
    // Main functions
    // =========================

    /// @inheritdoc IDeltaNeutralStrategyLogic
    function deposit(
        uint256 amountToDeposit,
        uint256 deviationThresholdE18,
        bytes32 pointer
    ) external onlyVaultItself {
        DeltaNeutralStrategyStorage storage s = _getStorage(pointer);

        if (amountToDeposit == 0) {
            revert DeltaNeutralStrategy_DepositZero();
        }

        IAToken supplyTokenAave = s.supplyTokenAave;
        address supplyToken = supplyTokenAave.UNDERLYING_ASSET_ADDRESS();

        DexLogicLib.validateTokenBalance(supplyToken, amountToDeposit);

        _strategyActions(
            amountToDeposit,
            0,
            deviationThresholdE18,
            s.uniswapV3NftId,
            supplyTokenAave,
            supplyToken,
            s
        );
        emit DeltaNeutralStrategyDeposit();
    }

    /// @inheritdoc IDeltaNeutralStrategyLogic
    function depositETH(
        uint256 amountToDeposit,
        uint256 deviationThresholdE18,
        bytes32 pointer
    ) external onlyVaultItself {
        if (amountToDeposit > address(this).balance) {
            revert DeltaNeutralStrategy_DepositZero();
        }

        DeltaNeutralStrategyStorage storage s = _getStorage(pointer);

        IAToken supplyTokenAave = s.supplyTokenAave;
        address supplyToken = supplyTokenAave.UNDERLYING_ASSET_ADDRESS();

        if (supplyToken != address(wrappedNative)) {
            revert DeltaNeutralStrategy_Token0IsNotWNative();
        }

        wrappedNative.deposit{value: amountToDeposit}();

        _strategyActions(
            amountToDeposit,
            0,
            deviationThresholdE18,
            s.uniswapV3NftId,
            supplyTokenAave,
            supplyToken,
            s
        );
        emit DeltaNeutralStrategyDeposit();
    }

    /// @inheritdoc IDeltaNeutralStrategyLogic
    function withdraw(
        uint256 shareE18,
        uint256 deviationThresholdE18,
        bytes32 pointer
    ) external onlyVaultItself {
        DeltaNeutralStrategyStorage storage s = _getStorage(pointer);

        IAToken supplyTokenAave = s.supplyTokenAave;
        address supplyToken = supplyTokenAave.UNDERLYING_ASSET_ADDRESS();

        _strategyActions(
            0,
            shareE18,
            deviationThresholdE18,
            s.uniswapV3NftId,
            supplyTokenAave,
            supplyToken,
            s
        );
        emit DeltaNeutralStrategyWithdraw();
    }

    /// @inheritdoc IDeltaNeutralStrategyLogic
    function rebalance(
        uint256 deviationThresholdE18,
        bytes32 pointer
    ) external onlyVaultItself {
        DeltaNeutralStrategyStorage storage s = _getStorage(pointer);

        IAToken supplyTokenAave = s.supplyTokenAave;
        address supplyToken = s.supplyTokenAave.UNDERLYING_ASSET_ADDRESS();

        _rebalance(supplyTokenAave, supplyToken, deviationThresholdE18, s);
    }

    // =========================
    // Internal functions
    // =========================

    function _rebalance(
        IAToken supplyTokenAave,
        address supplyToken,
        uint256 deviationThresholdE18,
        DeltaNeutralStrategyStorage storage s
    ) internal {
        _strategyActions(
            0,
            0,
            deviationThresholdE18,
            s.uniswapV3NftId,
            supplyTokenAave,
            supplyToken,
            s
        );

        emit DeltaNeutralStrategyRebalance();
    }

    /// @dev Internal function to set a new target health factor.
    /// @param newTargetHF The new target health factor to set.
    /// @param pointerToAaveChecker The pointer to the Aave checker.
    /// @param s Storage reference to the DeltaNeutralStrategyStorage.
    function _setNewTargetHF(
        uint256 newTargetHF,
        bytes32 pointerToAaveChecker,
        DeltaNeutralStrategyStorage storage s
    ) internal {
        (uint256 lowerHFBoundary, uint256 upperHFBoundary) = IAaveCheckerLogic(
            address(this)
        ).getHFBoundaries(pointerToAaveChecker);

        if (newTargetHF <= lowerHFBoundary || newTargetHF >= upperHFBoundary) {
            revert DeltaNeutralStrategy_HealthFactorOutOfRange();
        }

        s.targetHealthFactor_e18 = newTargetHF;
        emit DeltaNeutralStrategyNewHealthFactor(newTargetHF);
    }

    /// @dev Struct to cache data suring function execution.
    struct StrategyActionsCache {
        uint24 poolFee;
        IUniswapV3Pool dexPool;
        uint256 amountToDeposit;
        uint256 nftId;
    }

    /// @dev Handles actions such as supplying and borrowing tokens and depositing to uniswap.
    /// @param amountToDeposit Amount of tokens to deposit.
    /// @param shareE18 Percentage share to withdraw (1e18 represents 100%).
    /// @param deviationThresholdE18 Deviation threshold.
    /// @param nftId ID of the NFT.
    /// @param supplyTokenAave Reference to the Aave supply token.
    /// @param supplyToken Address of the supply token.
    /// @param s Storage reference to the DeltaNeutralStrategyStorage.
    function _strategyActions(
        uint256 amountToDeposit,
        uint256 shareE18,
        uint256 deviationThresholdE18,
        uint256 nftId,
        IAToken supplyTokenAave,
        address supplyToken,
        DeltaNeutralStrategyStorage storage s
    ) internal {
        IVariableDebtToken debtTokenAave = s.debtTokenAave;
        address debtToken = debtTokenAave.UNDERLYING_ASSET_ADDRESS();

        StrategyActionsCache memory aaveActionCache;

        {
            (, , uint24 poolFee, , , ) = DexLogicLib.getNftData(
                nftId,
                dexNftPositionManager
            );
            IUniswapV3Pool dexPool = DexLogicLib.dexPool(
                supplyToken,
                debtToken,
                poolFee,
                dexFactory
            );
            DexLogicLib.MEVCheck(deviationThresholdE18, dexPool, PERIOD);

            aaveActionCache.poolFee = poolFee;
            aaveActionCache.dexPool = dexPool;
            aaveActionCache.amountToDeposit = amountToDeposit;
            aaveActionCache.nftId = nftId;
        }

        uint256 totalToken0Balance = _getTotalSupplyTokenBalance(
            aaveActionCache.amountToDeposit,
            nftId,
            supplyTokenAave,
            supplyToken,
            debtTokenAave,
            debtToken,
            aaveActionCache.dexPool
        );

        if (shareE18 > 0) {
            if (shareE18 > E18) {
                shareE18 = E18;
            }
            unchecked {
                // remainder in supplyToken after withdraw
                totalToken0Balance =
                    (totalToken0Balance * (E18 - shareE18)) /
                    E18;
            }
        }

        // get target amounts for new value
        (
            uint256 amountToSupply,
            uint256 amountToBorrow
        ) = _getAmountToSupplyAndToBorrow(
                aaveActionCache.nftId,
                supplyToken,
                debtToken,
                s.targetHealthFactor_e18,
                s.pointerToAaveChecker,
                aaveActionCache.dexPool,
                totalToken0Balance
            );

        uint256 supplyBalanceBefore = TransferHelper.safeGetBalance(
            supplyToken,
            address(this)
        );
        uint256 debtBalanceBefore = TransferHelper.safeGetBalance(
            debtToken,
            address(this)
        );

        // bring to the target amounts
        _bringToTheAmounts(
            aaveActionCache.amountToDeposit,
            aaveActionCache.nftId,
            supplyTokenAave,
            supplyToken,
            debtTokenAave,
            debtToken,
            aaveActionCache.dexPool,
            amountToSupply,
            amountToBorrow
        );

        uint256 debtBalanceAfter = TransferHelper.safeGetBalance(
            debtToken,
            address(this)
        );

        if (shareE18 > 0) {
            if (debtBalanceAfter > debtBalanceBefore) {
                // convert debt token to supply token
                _convertAssetsToSupplyToken(
                    supplyToken,
                    debtToken,
                    aaveActionCache.poolFee,
                    debtBalanceAfter - debtBalanceBefore
                );
            }
        } else {
            uint256 supplyBalanceAfter = TransferHelper.safeGetBalance(
                supplyToken,
                address(this)
            );

            uint256 supplyAmountToUni;
            uint256 debtAmountToUni;

            if (supplyBalanceBefore >= supplyBalanceAfter) {
                unchecked {
                    supplyAmountToUni =
                        aaveActionCache.amountToDeposit -
                        (supplyBalanceBefore - supplyBalanceAfter);
                }
            } else {
                unchecked {
                    supplyAmountToUni =
                        supplyBalanceAfter -
                        supplyBalanceBefore;
                }
            }
            if (debtBalanceAfter > debtBalanceBefore) {
                unchecked {
                    debtAmountToUni = debtBalanceAfter - debtBalanceBefore;
                }
            }

            if (supplyAmountToUni > 0 || debtAmountToUni > 0) {
                // Deposit to uni
                _depositToUni(
                    aaveActionCache.dexPool,
                    supplyToken,
                    debtToken,
                    aaveActionCache.nftId,
                    aaveActionCache.poolFee,
                    supplyAmountToUni,
                    debtAmountToUni
                );
            }
        }
    }

    /// @dev Adjusts the supply and borrow amounts to reach the desired targets.
    /// @param amountToDeposit Amount of tokens to deposit.
    /// @param nftId ID of the NFT.
    /// @param supplyTokenAave Reference to the Aave supply token.
    /// @param supplyToken Address of the supply token.
    /// @param debtTokenAave Reference to the Aave debt token.
    /// @param debtToken Address of the debt token.
    /// @param dexPool Reference to the Uniswap V3 pool.
    /// @param amountToSupply Desired supply amount.
    /// @param amountToBorrow Desired borrow amount.
    function _bringToTheAmounts(
        uint256 amountToDeposit,
        uint256 nftId,
        IAToken supplyTokenAave,
        address supplyToken,
        IVariableDebtToken debtTokenAave,
        address debtToken,
        IUniswapV3Pool dexPool,
        uint256 amountToSupply,
        uint256 amountToBorrow
    ) internal {
        // checks to increase or decrease
        // our supply and borrow
        uint256 supplyTokenAaveBalance = TransferHelper.safeGetBalance(
            address(supplyTokenAave),
            address(this)
        );

        uint256 debtTokenAaveBalance = TransferHelper.safeGetBalance(
            address(debtTokenAave),
            address(this)
        );

        if (
            amountToSupply >= supplyTokenAaveBalance &&
            amountToBorrow >= debtTokenAaveBalance
        ) {
            // if we need to increase our supply and borrow
            // we increase supply first
            // and then borrow
            if (amountToSupply > 0) {
                _bringingToTargetSupplyAmount(
                    amountToDeposit,
                    nftId,
                    supplyTokenAave,
                    supplyToken,
                    debtToken,
                    dexPool,
                    amountToSupply
                );
            }
            if (amountToBorrow > 0) {
                _bringingToTargetBorrowAmount(
                    amountToDeposit > 0,
                    nftId,
                    supplyToken,
                    debtTokenAave,
                    debtToken,
                    dexPool,
                    amountToBorrow
                );
            }
        } else {
            // if we need to reduce our supply and borrow
            // we reduce borrow first
            // and then supply
            _bringingToTargetBorrowAmount(
                amountToDeposit > 0,
                nftId,
                supplyToken,
                debtTokenAave,
                debtToken,
                dexPool,
                amountToBorrow
            );
            _bringingToTargetSupplyAmount(
                amountToDeposit,
                nftId,
                supplyTokenAave,
                supplyToken,
                debtToken,
                dexPool,
                amountToSupply
            );
        }
    }

    /// @dev Struct to cache data suring function execution.
    struct DataCache {
        uint160 sqrtPriceX96;
        uint24 poolFee;
        int24 tickLower;
        int24 tickUpper;
        uint128 nftLiquidity;
    }

    /// @dev Bringing to the target amount for supplying on Aave.
    /// @param amountToDeposit The amount intended to be deposited.
    /// @param nftId The ID of the NFT.
    /// @param supplyTokenAave Aave's token for supplying.
    /// @param supplyToken The token intended to be supplied.
    /// @param debtToken The token to be swapped to achieve target supply.
    /// @param dexPool The Uniswap V3 pool instance.
    /// @param amountToSupply The target supply amount.
    function _bringingToTargetSupplyAmount(
        uint256 amountToDeposit,
        uint256 nftId,
        IAToken supplyTokenAave,
        address supplyToken,
        address debtToken,
        IUniswapV3Pool dexPool,
        uint256 amountToSupply
    ) internal {
        uint256 supplyTokenAaveBalance = TransferHelper.safeGetBalance(
            address(supplyTokenAave),
            address(this)
        );

        // checks if we need to increase or decrease supply
        if (amountToSupply > supplyTokenAaveBalance) {
            // if we got less supplyToken than we need to supply, we swap debtToken to supplyToken
            // and supply supplyToken to aave
            uint256 deltaToSupply = amountToSupply - supplyTokenAaveBalance;

            DataCache memory dataCache;

            (
                ,
                ,
                dataCache.poolFee,
                dataCache.tickLower,
                dataCache.tickUpper,
                dataCache.nftLiquidity
            ) = DexLogicLib.getNftData(nftId, dexNftPositionManager);

            if (amountToDeposit < deltaToSupply) {
                if (dataCache.nftLiquidity != 0) {
                    uint128 liquidityToWithdraw;
                    uint160 sqrtPriceX96 = DexLogicLib.getCurrentSqrtRatioX96(
                        dexPool
                    );

                    if (supplyToken > debtToken) {
                        liquidityToWithdraw = LiquidityAmounts
                            .getLiquidityForAmount1(
                                sqrtPriceX96,
                                TickMath.getSqrtRatioAtTick(
                                    dataCache.tickLower
                                ),
                                deltaToSupply - amountToDeposit
                            );
                    } else {
                        liquidityToWithdraw = LiquidityAmounts
                            .getLiquidityForAmount0(
                                sqrtPriceX96,
                                TickMath.getSqrtRatioAtTick(
                                    dataCache.tickUpper
                                ),
                                deltaToSupply - amountToDeposit
                            );
                    }

                    if (liquidityToWithdraw > dataCache.nftLiquidity) {
                        liquidityToWithdraw = dataCache.nftLiquidity;
                    }

                    // withdraw uni position for amount of supplyToken that we need
                    (
                        uint256 supplyWithdrawed,
                        uint256 debtWithdrawed
                    ) = DexLogicLib.withdrawPositionMEVUnsafe(
                            nftId,
                            liquidityToWithdraw,
                            dexNftPositionManager
                        );

                    if (supplyToken > debtToken) {
                        (supplyWithdrawed, debtWithdrawed) = (
                            debtWithdrawed,
                            supplyWithdrawed
                        );
                    }
                    unchecked {
                        amountToDeposit += supplyWithdrawed;
                    }

                    if (deltaToSupply > amountToDeposit && debtWithdrawed > 0) {
                        // swap debtToken to supplyToken
                        uint256 amountOut = DexLogicLib.swapExactInputMEVUnsafe(
                            debtToken,
                            supplyToken,
                            dataCache.poolFee,
                            debtWithdrawed,
                            dexRouter
                        );

                        unchecked {
                            amountToDeposit += amountOut;
                        }
                    }
                }
            }

            if (deltaToSupply > amountToDeposit) {
                deltaToSupply = amountToDeposit;
            }

            // supply supplyToken to aave
            AaveLogicLib.supplyAave(
                supplyToken,
                deltaToSupply,
                address(this),
                aavePoolAddressesProvider
            );
        } else {
            // if we got more supply than we need, we withdraw it
            AaveLogicLib.withdrawAave(
                supplyToken,
                supplyTokenAaveBalance - amountToSupply,
                address(this),
                aavePoolAddressesProvider
            );
        }
    }

    /// @dev Bringing to the target borrow amount on Aave.
    /// @param isDeposit Indicator if the operation is a deposit.
    /// @param nftId The ID of the NFT.
    /// @param supplyToken The token intended to be swapped for borrowing.
    /// @param debtTokenAave Aave's debt token.
    /// @param debtToken The token intended to be borrowed.
    /// @param dexPool The Uniswap V3 pool instance.
    /// @param amountToBorrow The target borrow amount.
    function _bringingToTargetBorrowAmount(
        bool isDeposit,
        uint256 nftId,
        address supplyToken,
        IVariableDebtToken debtTokenAave,
        address debtToken,
        IUniswapV3Pool dexPool,
        uint256 amountToBorrow
    ) internal {
        uint256 totalDebt = AaveLogicLib.getTotalDebt(
            address(debtTokenAave),
            address(this)
        );

        // checks if we need to increase or decrease borrow
        if (amountToBorrow > totalDebt) {
            // if we got less borrow than we need, we makes a borrow
            uint256 amount;
            unchecked {
                amount = amountToBorrow - totalDebt;
            }

            AaveLogicLib.borrowAave(
                debtToken,
                amount,
                address(this),
                aavePoolAddressesProvider
            );
        } else {
            // if we got more borrow than we need, swap supplyToken to debtToken
            // and repay aave
            uint256 deltaToRepay;
            unchecked {
                deltaToRepay = totalDebt - amountToBorrow;
            }

            DataCache memory dataCache;

            (
                ,
                ,
                dataCache.poolFee,
                dataCache.tickLower,
                dataCache.tickUpper,
                dataCache.nftLiquidity
            ) = DexLogicLib.getNftData(nftId, dexNftPositionManager);

            uint256 debtTokenBalance;
            if (isDeposit) {
                debtTokenBalance = TransferHelper.safeGetBalance(
                    debtToken,
                    address(this)
                );
            } else {
                debtTokenBalance = 0;
            }

            dataCache.sqrtPriceX96 = DexLogicLib.getCurrentSqrtRatioX96(
                dexPool
            );

            if (debtTokenBalance < deltaToRepay) {
                if (dataCache.nftLiquidity != 0) {
                    uint128 liquidityToWithdraw;

                    if (supplyToken > debtToken) {
                        liquidityToWithdraw = LiquidityAmounts
                            .getLiquidityForAmount0(
                                dataCache.sqrtPriceX96,
                                TickMath.getSqrtRatioAtTick(
                                    dataCache.tickUpper
                                ),
                                deltaToRepay - debtTokenBalance
                            );
                    } else {
                        liquidityToWithdraw = LiquidityAmounts
                            .getLiquidityForAmount1(
                                dataCache.sqrtPriceX96,
                                TickMath.getSqrtRatioAtTick(
                                    dataCache.tickLower
                                ),
                                deltaToRepay - debtTokenBalance
                            );
                    }

                    if (liquidityToWithdraw > dataCache.nftLiquidity) {
                        liquidityToWithdraw = dataCache.nftLiquidity;
                    }

                    // withdraw uni position for amount of supplyToken that we need
                    (
                        uint256 supplyWithdrawed,
                        uint256 debtWithdrawed
                    ) = DexLogicLib.withdrawPositionMEVUnsafe(
                            nftId,
                            liquidityToWithdraw,
                            dexNftPositionManager
                        );

                    if (supplyToken > debtToken) {
                        (supplyWithdrawed, debtWithdrawed) = (
                            debtWithdrawed,
                            supplyWithdrawed
                        );
                    }
                    unchecked {
                        debtTokenBalance += debtWithdrawed;
                    }

                    if (
                        deltaToRepay > debtTokenBalance && supplyWithdrawed > 0
                    ) {
                        // swap supplyToken to debtToken
                        uint256 amountOut = DexLogicLib.swapExactInputMEVUnsafe(
                            supplyToken,
                            debtToken,
                            dataCache.poolFee,
                            supplyWithdrawed,
                            dexRouter
                        );

                        unchecked {
                            debtTokenBalance += amountOut;
                        }
                    }
                }
            }

            if (deltaToRepay > debtTokenBalance) {
                uint256 token1Token0Quote;
                if (debtToken < supplyToken) {
                    token1Token0Quote = DexLogicLib.getAmount0InToken1(
                        dataCache.sqrtPriceX96,
                        deltaToRepay - debtTokenBalance
                    );
                } else {
                    token1Token0Quote = DexLogicLib.getAmount1InToken0(
                        dataCache.sqrtPriceX96,
                        deltaToRepay - debtTokenBalance
                    );
                }

                uint256 supplyTokenBalance = TransferHelper.safeGetBalance(
                    supplyToken,
                    address(this)
                );

                AaveLogicLib.withdrawAave(
                    supplyToken,
                    token1Token0Quote,
                    address(this),
                    aavePoolAddressesProvider
                );

                supplyTokenBalance =
                    TransferHelper.safeGetBalance(supplyToken, address(this)) -
                    supplyTokenBalance;

                // swap supplyToken to debtToken
                DexLogicLib.swapExactInputMEVUnsafe(
                    supplyToken,
                    debtToken,
                    dataCache.poolFee,
                    supplyTokenBalance,
                    dexRouter
                );
            }

            // we need to do "+1" because of aave bug
            unchecked {
                ++deltaToRepay;
            }

            // repay aave
            AaveLogicLib.repayAave(
                debtToken,
                deltaToRepay,
                address(this),
                aavePoolAddressesProvider
            );
        }
    }

    /// @dev Retrieves the total balance of the supply token, including deposits, debts
    /// and uniswap position.
    /// @param amountToDeposit The amount of the token that is intended to be deposited.
    /// @param nftId ID of the NFT in question.
    /// @param supplyTokenAave AAVE's supply token interface.
    /// @param supplyToken The supply token address.
    /// @param debtTokenAave AAVE's debt token interface.
    /// @param debtToken The debt token address.
    /// @param dexPool The decentralized exchange pool interface.
    /// @return Total balance of the supply token.
    function _getTotalSupplyTokenBalance(
        uint256 amountToDeposit,
        uint256 nftId,
        IAToken supplyTokenAave,
        address supplyToken,
        IVariableDebtToken debtTokenAave,
        address debtToken,
        IUniswapV3Pool dexPool
    ) internal view returns (uint256) {
        // gets amount of supplyToken and debtToken in nft
        uint256 amount0;
        uint256 amount1;

        uint256 liquidity = DexLogicLib.getLiquidity(
            nftId,
            dexNftPositionManager
        );
        if (liquidity != 0) {
            (amount0, amount1) = DexLogicLib.tvl(
                nftId,
                dexPool,
                dexNftPositionManager
            );

            // checks if our supplyToken is supplyToken in nft
            if (supplyToken > debtToken) {
                (amount0, amount1) = (amount1, amount0);
            }
        }

        // gets pure amount of supplyToken and debtToken in current aave position
        uint256 pureAmountSupplyToken = TransferHelper.safeGetBalance(
            address(supplyTokenAave),
            address(this)
        ) +
            amount0 +
            amountToDeposit;

        // gets debt amount
        uint256 totalDebt = AaveLogicLib.getTotalDebt(
            address(debtTokenAave),
            address(this)
        );

        uint160 sqrtPriceX96 = DexLogicLib.getCurrentSqrtRatioX96(dexPool);

        uint256 pureAmountDebtTokenInSupplyToken;
        uint256 totalDebtInSupplyToken;
        if (debtToken < supplyToken) {
            pureAmountDebtTokenInSupplyToken = DexLogicLib.getAmount0InToken1(
                sqrtPriceX96,
                amount1
            );

            totalDebtInSupplyToken = DexLogicLib.getAmount0InToken1(
                sqrtPriceX96,
                totalDebt
            );
        } else {
            pureAmountDebtTokenInSupplyToken = DexLogicLib.getAmount1InToken0(
                sqrtPriceX96,
                amount1
            );

            totalDebtInSupplyToken = DexLogicLib.getAmount1InToken0(
                sqrtPriceX96,
                totalDebt
            );
        }

        // returns total supplyToken balance
        return
            pureAmountSupplyToken +
            pureAmountDebtTokenInSupplyToken -
            totalDebtInSupplyToken;
    }

    /// @dev Calculates the amount to be supplied and borrowed.
    /// @param nftId ID of the NFT in question.
    /// @param supplyToken The supply token address.
    /// @param debtToken The debt token address.
    /// @param targetHealthFactor_e18 Target health factor.
    /// @param pointerToAaveChecker A pointer to the AAVE checker.
    /// @param dexPool The decentralized exchange pool interface.
    /// @param inputAmount The input amount.
    /// @return amountToSupply The amount that should be supplied.
    /// @return amountToBorrow The amount that should be borrowed.
    function _getAmountToSupplyAndToBorrow(
        uint256 nftId,
        address supplyToken,
        address debtToken,
        uint256 targetHealthFactor_e18,
        bytes32 pointerToAaveChecker,
        IUniswapV3Pool dexPool,
        uint256 inputAmount
    ) internal view returns (uint256 amountToSupply, uint256 amountToBorrow) {
        // get ticks
        (, , , int24 minTick, int24 maxTick, ) = DexLogicLib.getNftData(
            nftId,
            dexNftPositionManager
        );

        uint160 sqrtPriceX96 = DexLogicLib.getCurrentSqrtRatioX96(dexPool);

        uint256 currentHealthFactorForCalculation_1e18 = _getHFForCalculations(
            targetHealthFactor_e18,
            pointerToAaveChecker
        );

        // get current liquidation threshold
        uint256 currentLiquidationThreshold_1e4 = AaveLogicLib
            .getCurrentLiquidationThreshold(
                supplyToken,
                aavePoolAddressesProvider
            );

        uint256 R_e18 = DexLogicLib.getTargetRE18ForTickRange(
            minTick,
            maxTick,
            dexPool.liquidity(),
            sqrtPriceX96
        );

        amountToSupply =
            (currentHealthFactorForCalculation_1e18 *
                inputAmount *
                (E18 - R_e18)) /
            (currentHealthFactorForCalculation_1e18 *
                (E18 - R_e18) +
                R_e18 *
                currentLiquidationThreshold_1e4 *
                E14);

        uint256 borrowMultiplier = FullMath.mulDiv(
            amountToSupply * E14,
            currentLiquidationThreshold_1e4,
            currentHealthFactorForCalculation_1e18
        );
        // gets amount to borrow
        if (supplyToken < debtToken) {
            amountToBorrow = DexLogicLib.getAmount0InToken1(
                sqrtPriceX96,
                borrowMultiplier
            );
        } else {
            amountToBorrow = DexLogicLib.getAmount1InToken0(
                sqrtPriceX96,
                borrowMultiplier
            );
        }
    }

    /// @dev Retrieves the health factor for calculations.
    /// @dev If the currentHF is out of bounds, the targetHF is used.
    /// @param targetHealthFactor_e18 Target health factor.
    /// @param pointerToAaveChecker A pointer to the AAVE checker.
    /// @return currentHealthFactorForCalculation_1e18 The health factor used for calculations.
    function _getHFForCalculations(
        uint256 targetHealthFactor_e18,
        bytes32 pointerToAaveChecker
    ) internal view returns (uint256 currentHealthFactorForCalculation_1e18) {
        (uint256 lowerHFBoundary, uint256 upperHFBoundary) = IAaveCheckerLogic(
            address(this)
        ).getHFBoundaries(pointerToAaveChecker);

        uint256 currentHealthFactor = AaveLogicLib.getCurrentHF(
            address(this),
            aavePoolAddressesProvider
        );

        if (
            currentHealthFactor < lowerHFBoundary ||
            currentHealthFactor > upperHFBoundary
        ) {
            currentHealthFactorForCalculation_1e18 = targetHealthFactor_e18;
        } else {
            currentHealthFactorForCalculation_1e18 = currentHealthFactor;
        }
    }

    /// @dev Converts assets to the supply token.
    /// @param supplyToken The supply token address.
    /// @param debtToken The debt token address.
    /// @param poolFee The fee associated with the pool.
    /// @param debtTokenBalance The balance of the debt token.
    function _convertAssetsToSupplyToken(
        address supplyToken,
        address debtToken,
        uint24 poolFee,
        uint256 debtTokenBalance
    ) internal {
        DexLogicLib.swapExactInputMEVUnsafe(
            debtToken,
            supplyToken,
            poolFee,
            debtTokenBalance,
            dexRouter
        );
    }

    /// @dev Deposits tokens to Uniswap position.
    /// @param dexPool The decentralized exchange pool interface.
    /// @param supplyToken The supply token address.
    /// @param debtToken The debt token address.
    /// @param nftId ID of the NFT in question.
    /// @param poolFee The fee associated with the pool.
    /// @param supplyTokenAmount Amount of the supply token.
    /// @param debtTokenAmount Amount of the debt token.
    function _depositToUni(
        IUniswapV3Pool dexPool,
        address supplyToken,
        address debtToken,
        uint256 nftId,
        uint24 poolFee,
        uint256 supplyTokenAmount,
        uint256 debtTokenAmount
    ) internal {
        (, , , int24 tickLower, int24 tickUpper, ) = DexLogicLib.getNftData(
            nftId,
            dexNftPositionManager
        );

        if (supplyToken > debtToken) {
            (supplyTokenAmount, debtTokenAmount) = (
                debtTokenAmount,
                supplyTokenAmount
            );
            (supplyToken, debtToken) = (debtToken, supplyToken);
        }

        (supplyTokenAmount, debtTokenAmount) = DexLogicLib
            .swapToTargetRMEVUnsafe(
                tickLower,
                tickUpper,
                supplyTokenAmount,
                debtTokenAmount,
                dexPool,
                supplyToken,
                debtToken,
                poolFee,
                dexRouter
            );

        TransferHelper.safeApprove(
            supplyToken,
            address(dexNftPositionManager),
            supplyTokenAmount
        );
        TransferHelper.safeApprove(
            debtToken,
            address(dexNftPositionManager),
            debtTokenAmount
        );

        DexLogicLib.increaseLiquidityMEVUnsafe(
            nftId,
            supplyTokenAmount,
            debtTokenAmount,
            dexNftPositionManager
        );
    }

    /// @dev Validates that the tokens match with the provided NFT.
    /// @param nftId ID of the NFT in question.
    /// @param supplyToken The supply token address.
    /// @param debtToken The debt token address.
    function _validateTokens(
        uint256 nftId,
        address supplyToken,
        address debtToken
    ) internal view {
        (address token0, address token1, , , , ) = DexLogicLib.getNftData(
            nftId,
            dexNftPositionManager
        );

        if (supplyToken > debtToken) {
            (token0, token1) = (token1, token0);
        }

        if (token0 != supplyToken || token1 != debtToken) {
            revert DeltaNeutralStrategy_InvalidNFTTokens();
        }
    }

    /// @dev Ensures the contract is initialized only once.
    /// @param s Storage reference to the DeltaNeutralStrategyStorage.
    function _checkInitialize(DeltaNeutralStrategyStorage storage s) private {
        DeltaNeutralStrategyCommonStorage storage cs = _getCommonStorage();

        // init block
        if (s.initialized || cs.initialized) {
            revert DeltaNeutralStrategy_AlreadyInitialized();
        }

        s.initialized = true;
        cs.initialized = true;
    }

    /// @dev Validates that the provided AAVE checker pointer has been initialized.
    /// @param aaveCheckerPointer The pointer to the AAVE checker to validate.
    function _validateAaveCheckerPointer(
        bytes32 aaveCheckerPointer
    ) private view {
        (, , , bool initialized) = IAaveCheckerLogic(address(this))
            .getLocalAaveCheckerStorage(aaveCheckerPointer);

        if (!initialized) {
            revert DeltaNeutralStrategy_AaveCheckerNotInitialized();
        }
    }
}

