// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.19;

import {IUniswapV3Pool} from "./IUniswapV3Pool.sol";
import {ISwapRouter} from "./ISwapRouter.sol";
import {LiquidityAmounts} from "./LiquidityAmounts.sol";
import {TickMath} from "./TickMath.sol";
import {OracleLibrary} from "./OracleLibrary.sol";

import {IERC20} from "./IERC20.sol";
import {IERC1155Receiver} from "./ERC1155Receiver.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {EnumerableSet} from "./EnumerableSet.sol";
import {SafeCast} from "./SafeCast.sol";
import {AccessControlEnumerable} from "./AccessControlEnumerable.sol";
import {ERC20} from "./ERC20.sol";
import {FixedPointMathLib} from "./FixedPointMathLib.sol";

import {IUniswapV3SingleTickLiquidityHandler} from "./IUniswapV3SingleTickLiquidityHandler.sol";
import {UniswapV3SingleTickLiquidityLib} from "./UniswapV3SingleTickLiquidityLib.sol";
import {UniswapV3PoolLib} from "./UniswapV3PoolLib.sol";
import {IDopexV2PositionManager} from "./IDopexV2PositionManager.sol";

interface IMulticallProvider {
    function multicall(bytes[] calldata data) external returns (bytes[] memory results);
}

interface IERC20Decimals {
    function decimals() external view returns (uint8);
}

contract Automator is ERC20, AccessControlEnumerable, IERC1155Receiver {
    using FixedPointMathLib for uint256;
    using SafeERC20 for IERC20;
    using SafeCast for uint256;
    using EnumerableSet for EnumerableSet.UintSet;
    using TickMath for int24;
    using UniswapV3PoolLib for IUniswapV3Pool;
    using UniswapV3SingleTickLiquidityLib for IUniswapV3SingleTickLiquidityHandler;

    struct LockedDopexShares {
        uint256 tokenId;
        uint256 shares;
    }

    struct RebalanceSwapParams {
        uint256 assetsShortage;
        uint256 counterAssetsShortage;
        uint256 maxCounterAssetsUseForSwap;
        uint256 maxAssetsUseForSwap;
    }

    struct RebalanceMintParams {
        int24 tick;
        uint128 liquidity;
    }

    struct RebalanceBurnParams {
        int24 tick;
        uint128 shares;
    }

    bytes32 public constant STRATEGIST_ROLE = keccak256("STRATEGIST_ROLE");

    IDopexV2PositionManager public immutable manager;
    IUniswapV3SingleTickLiquidityHandler public immutable handler;

    IUniswapV3Pool public immutable pool;
    ISwapRouter public immutable router;

    IERC20 public immutable asset;
    IERC20 public immutable counterAsset;

    int24 public immutable poolTickSpacing;

    uint256 public immutable minDepositAssets;
    uint256 public depositCap;

    EnumerableSet.UintSet activeTicks;

    error AmountZero();
    error LengthMismatch();
    error InvalidRebalanceParams();
    error MinAssetsRequired(uint256 minAssets, uint256 actualAssets);
    error TokenAddressMismatch();
    error DepositTooSmall();
    error DepositCapExceeded();
    error SharesTooSmall();
    error InvalidPositionConstruction();

    constructor(
        address admin,
        IDopexV2PositionManager manager_,
        IUniswapV3SingleTickLiquidityHandler handler_,
        ISwapRouter router_,
        IUniswapV3Pool pool_,
        IERC20 asset_,
        uint256 minDepositAssets_
    )
        // TODO: change name and symbol
        ERC20("Automator", "AUTO", 18)
    {
        if (asset_ != IERC20(pool_.token0()) && asset_ != IERC20(pool_.token1())) revert TokenAddressMismatch();

        manager = manager_;
        handler = handler_;
        router = router_;
        pool = pool_;
        asset = asset_;
        counterAsset = pool_.token0() == address(asset_) ? IERC20(pool_.token1()) : IERC20(pool_.token0());
        poolTickSpacing = pool_.tickSpacing();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);

        minDepositAssets = minDepositAssets_;

        asset_.safeApprove(address(manager_), type(uint256).max);
        asset_.safeApprove(address(router_), type(uint256).max);

        counterAsset.safeApprove(address(manager_), type(uint256).max);
        counterAsset.safeApprove(address(router_), type(uint256).max);
    }

    /*///////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                    ERC1155 RECEIVER INTERFACE
    ///////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata
    ) external pure returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }

    /*///////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                    ADMIN FUNCTIONS
    ///////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function setDepositCap(uint256 _depositCap) external onlyRole(DEFAULT_ADMIN_ROLE) {
        depositCap = _depositCap;
    }

    /*///////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                    VAULT STATE DERIVATION FUNCTIONS
    ///////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function totalAssets() public view returns (uint256) {
        // 1. calculate the total assets in Dopex pools
        uint256 _length = activeTicks.length();
        uint256 _tid;
        uint128 _liquidity;
        (int24 _lt, int24 _ut) = (0, 0);
        (uint256 _sum0, uint256 _sum1) = (0, 0);
        (uint256 _a0, uint256 _a1) = (0, 0);

        (uint160 _sqrtRatioX96, , , , , , ) = pool.slot0();

        for (uint256 i = 0; i < _length; ) {
            _lt = int24(uint24(activeTicks.at(i)));
            _ut = _lt + poolTickSpacing;
            _tid = handler.tokenId(address(pool), _lt, _ut);

            _liquidity = handler.convertToAssets((handler.balanceOf(address(this), _tid)).toUint128(), _tid);

            (_a0, _a1) = LiquidityAmounts.getAmountsForLiquidity(
                _sqrtRatioX96,
                _lt.getSqrtRatioAtTick(),
                _ut.getSqrtRatioAtTick(),
                _liquidity
            );

            _sum0 += _a0;
            _sum1 += _a1;

            unchecked {
                i++;
            }
        }

        // 2. merge into the total assets in the automator
        (uint256 _base, uint256 _quote) = (counterAsset.balanceOf(address(this)), asset.balanceOf(address(this)));

        if (address(asset) == pool.token0()) {
            _base += _sum1;
            _quote += _sum0;
        } else {
            _base += _sum0;
            _quote += _sum1;
        }

        return
            _quote +
            OracleLibrary.getQuoteAtTick(pool.currentTick(), _base.toUint128(), address(counterAsset), address(asset));
    }

    // TODO: implement
    // function previewRedeem() public view returns (uint256 assets, LockedDopexShares[] memory lockedDopexShares) {}

    function convertToShares(uint256 assets) public view returns (uint256) {
        uint256 _supply = totalSupply;

        return _supply == 0 ? assets : assets.mulDivDown(_supply, totalAssets());
    }

    function convertToAssets(uint256 shares) public view returns (uint256) {
        uint256 _supply = totalSupply;

        return _supply == 0 ? shares : shares.mulDivDown(totalAssets(), _supply);
    }

    function calculateRebalanceSwapParamsInRebalance(
        UniswapV3PoolLib.Position[] memory mintPositions,
        UniswapV3PoolLib.Position[] memory burnPositions
    ) external view returns (RebalanceSwapParams memory) {
        uint256 _mintAssets;
        uint256 _mintCAssets;
        uint256 _burnAssets;
        uint256 _burnCAssets;

        if (pool.token0() == address(asset)) {
            (_mintAssets, _mintCAssets) = pool.estimateTotalTokensFromPositions(mintPositions);
            (_burnAssets, _burnCAssets) = pool.estimateTotalTokensFromPositions(burnPositions);
        } else {
            (_mintCAssets, _mintAssets) = pool.estimateTotalTokensFromPositions(mintPositions);
            (_burnCAssets, _burnAssets) = pool.estimateTotalTokensFromPositions(burnPositions);
        }

        uint256 _freeAssets = _burnAssets + asset.balanceOf(address(this));
        uint256 _freeCAssets = _burnCAssets + counterAsset.balanceOf(address(this));

        uint256 _assetsShortage;
        if (_mintAssets > _freeAssets) _assetsShortage = _mintAssets - _freeAssets;

        uint256 _counterAssetsShortage;
        if (_mintCAssets > _freeCAssets) _counterAssetsShortage = _mintCAssets - _freeCAssets;

        if (_assetsShortage > 0 && _counterAssetsShortage > 0) revert InvalidPositionConstruction();

        uint256 _maxCounterAssetsUseForSwap;
        if (_assetsShortage > 0) {
            _maxCounterAssetsUseForSwap = _freeCAssets - _mintCAssets;
        }

        uint256 _maxAssetsUseForSwap;
        if (_counterAssetsShortage > 0) {
            _maxAssetsUseForSwap = _freeAssets - _mintAssets;
        }

        return
            RebalanceSwapParams({
                assetsShortage: _assetsShortage,
                counterAssetsShortage: _counterAssetsShortage,
                maxCounterAssetsUseForSwap: _maxCounterAssetsUseForSwap,
                maxAssetsUseForSwap: _maxAssetsUseForSwap
            });
    }

    /*///////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                    USER ACTIONS
    ///////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function deposit(uint256 assets) external returns (uint256 shares) {
        if (assets == 0) revert AmountZero();
        if (assets < minDepositAssets) revert DepositTooSmall();
        if (assets > depositCap) revert DepositCapExceeded();

        if (totalSupply == 0) {
            uint256 _dead = 10 ** decimals / 1000;

            unchecked {
                shares = assets - _dead;
            }
            _mint(address(0), _dead);
            _mint(msg.sender, shares);
        } else {
            shares = convertToShares(assets);

            _mint(msg.sender, shares);
        }

        asset.safeTransferFrom(msg.sender, address(this), assets);
    }

    function redeem(
        uint256 shares,
        uint256 minAssets // use sqrtPriceLimitX96 instead ?
    ) external returns (uint256 assets, LockedDopexShares[] memory lockedDopexShares) {
        if (shares == 0) revert AmountZero();

        assets = convertToAssets(shares);

        // avoid rounding to 0
        if (assets == 0) revert SharesTooSmall();

        uint256 _length = activeTicks.length();
        int24 _lt;
        uint256 _tid;
        uint256 _shareLocked;
        uint256 _shareRedeemable;
        uint256 j;

        uint256 _preBase = counterAsset.balanceOf(address(this));
        uint256 _preQuote = asset.balanceOf(address(this));

        for (uint256 i = 0; i < _length; i++) {
            _lt = int24(uint24(activeTicks.at(i)));
            _tid = handler.tokenId(address(pool), _lt, _lt + poolTickSpacing);
            _shareRedeemable = uint256(
                handler.convertToShares(handler.redeemableLiquidity(address(this), _tid).toUint128(), _tid)
            ).mulDivDown(shares, totalSupply);
            _shareLocked = uint256(
                handler.convertToShares(handler.lockedLiquidity(address(this), _tid).toUint128(), _tid)
            ).mulDivDown(shares, totalSupply);

            // locked share is transferred to the user
            if (_shareLocked > 0) {
                unchecked {
                    lockedDopexShares[j++] = LockedDopexShares({tokenId: _tid, shares: _shareLocked});
                }

                handler.safeTransferFrom(address(this), msg.sender, _tid, _shareLocked, "");
            }

            // redeemable share is burned
            if (_shareRedeemable > 0) {
                manager.burnPosition(
                    handler,
                    abi.encode(
                        IUniswapV3SingleTickLiquidityHandler.BurnPositionParams({
                            pool: address(pool),
                            tickLower: _lt,
                            tickUpper: _lt + poolTickSpacing,
                            shares: _shareRedeemable.toUint128()
                        })
                    )
                );
            }
        }

        uint256 _payBase = counterAsset.balanceOf(address(this)) - _preBase;

        if (_payBase > 0)
            router.exactInputSingle(
                ISwapRouter.ExactInputSingleParams({
                    tokenIn: address(counterAsset),
                    tokenOut: address(asset),
                    fee: pool.fee(),
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountIn: _payBase,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: 0
                })
            );

        if ((assets += (asset.balanceOf(address(this)) - _preQuote)) < minAssets)
            revert MinAssetsRequired(minAssets, assets);

        _burn(msg.sender, shares);

        asset.safeTransfer(msg.sender, assets);
    }

    /*///////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                    STRATEGIST ACTIONS
    ///////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /**
     * @dev should be called by strategist when creating rebalance params.
     * @dev this is a hack to avoid mint error in a Dopex UniV3 Handler.
     * the handler will revert when accumulated fees are less than 10.
     * this is because the liquidity calculation is rounded down to 0 against the accumulated fees, then mint for 0 will revert.
     */
    function checkMintValidity(int24 lowerTick, int24 upperTick) external view returns (bool) {
        (, , , uint128 _owed0, uint128 _owed1) = pool.positions(
            keccak256(abi.encodePacked(address(handler), lowerTick, upperTick))
        );

        if (_owed0 > 0 && _owed0 < 10) return false;

        if (_owed1 > 0 && _owed1 < 10) return false;

        return true;
    }

    function rebalance(
        RebalanceMintParams[] calldata mintParams,
        RebalanceBurnParams[] calldata burnParams,
        RebalanceSwapParams calldata swapParams
    ) external onlyRole(STRATEGIST_ROLE) {
        _swapBeforeRebalance(swapParams);

        uint256 _mintLength = mintParams.length;
        uint256 _burnLength = burnParams.length;

        bytes[] memory _mintCalldataBatch = new bytes[](_mintLength);
        int24 _lt;
        int24 _ut;
        uint256 _posId;
        for (uint256 i = 0; i < _mintLength; i++) {
            _lt = mintParams[i].tick;
            _ut = _lt + poolTickSpacing;

            _mintCalldataBatch[i] = _createMintCalldata(_lt, _ut, mintParams[i].liquidity);

            // If the position is not active, push it to the active ticks
            _posId = uint256(keccak256(abi.encode(handler, pool, _lt, _ut)));
            if (handler.balanceOf(address(this), _posId) == 0) activeTicks.add(uint256(uint24(_lt)));
        }

        bytes[] memory _burnCalldataBatch = new bytes[](_burnLength);
        for (uint256 i = 0; i < _burnLength; i++) {
            _lt = burnParams[i].tick;
            _ut = _lt + poolTickSpacing;

            _burnCalldataBatch[i] = _createBurnCalldata(_lt, _ut, burnParams[i].shares);

            // if all shares will be burned, pop the active tick
            _posId = uint256(keccak256(abi.encode(handler, pool, _lt, _ut)));
            if (handler.balanceOf(address(this), _posId) - burnParams[i].shares == 0)
                activeTicks.remove(uint256(uint24(_lt)));
        }

        if (_mintLength > 0) IMulticallProvider(address(manager)).multicall(_mintCalldataBatch);
        if (_burnLength > 0) IMulticallProvider(address(manager)).multicall(_burnCalldataBatch);
    }

    function _swapBeforeRebalance(RebalanceSwapParams calldata swapParams) internal {
        if (swapParams.assetsShortage > 0) {
            router.exactOutputSingle(
                ISwapRouter.ExactOutputSingleParams({
                    tokenIn: address(counterAsset),
                    tokenOut: address(asset),
                    fee: pool.fee(),
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountOut: swapParams.assetsShortage,
                    amountInMaximum: swapParams.maxCounterAssetsUseForSwap,
                    sqrtPriceLimitX96: 0
                })
            );
        }

        if (swapParams.counterAssetsShortage > 0) {
            router.exactOutputSingle(
                ISwapRouter.ExactOutputSingleParams({
                    tokenIn: address(asset),
                    tokenOut: address(counterAsset),
                    fee: pool.fee(),
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountOut: swapParams.counterAssetsShortage,
                    amountInMaximum: swapParams.maxAssetsUseForSwap,
                    sqrtPriceLimitX96: 0
                })
            );
        }
    }

    function _createMintCalldata(int24 lt, int24 ut, uint128 liq) internal view returns (bytes memory) {
        return
            abi.encodeWithSelector(
                IDopexV2PositionManager.mintPosition.selector,
                handler,
                abi.encode(
                    IUniswapV3SingleTickLiquidityHandler.MintPositionParams({
                        pool: address(pool),
                        tickLower: lt,
                        tickUpper: ut,
                        liquidity: liq
                    })
                )
            );
    }

    function _createBurnCalldata(int24 lt, int24 ut, uint128 shares) internal view returns (bytes memory) {
        return
            abi.encodeWithSelector(
                IDopexV2PositionManager.burnPosition.selector,
                handler,
                abi.encode(
                    IUniswapV3SingleTickLiquidityHandler.BurnPositionParams({
                        pool: address(pool),
                        tickLower: lt,
                        tickUpper: ut,
                        shares: shares
                    })
                )
            );
    }

    // TODO: delete
    /// @dev this is a testing only function to make debug easier
    function inefficientRebalance(
        RebalanceMintParams[] calldata mintParams,
        RebalanceBurnParams[] calldata burnParams,
        RebalanceSwapParams calldata swapParams
    ) external onlyRole(STRATEGIST_ROLE) {
        _swapBeforeRebalance(swapParams);

        uint256 _mintLength = mintParams.length;
        uint256 _burnLength = burnParams.length;

        int24 _lt;
        int24 _ut;
        uint256 _posId;
        for (uint256 i = 0; i < _mintLength; i++) {
            _lt = mintParams[i].tick;
            _ut = _lt + poolTickSpacing;

            // If the position is not active, push it to the active ticks
            _posId = uint256(keccak256(abi.encode(handler, pool, _lt, _ut)));
            if (handler.balanceOf(address(this), _posId) == 0) activeTicks.add(uint256(uint24(_lt)));

            _mintPosition(_lt, _ut, mintParams[i].liquidity);
        }

        for (uint256 i = 0; i < _burnLength; i++) {
            _lt = burnParams[i].tick;
            _ut = _lt + poolTickSpacing;

            // if all shares will be burned, pop the active tick
            _posId = uint256(keccak256(abi.encode(handler, pool, _lt, _ut)));
            if (handler.balanceOf(address(this), _posId) - burnParams[i].shares == 0)
                activeTicks.remove(uint256(uint24(_lt)));

            _burnPosition(_lt, _ut, burnParams[i].shares);
        }
    }

    function _mintPosition(int24 lowerTick, int24 upperTick, uint128 liquidity) internal {
        manager.mintPosition(
            handler,
            abi.encode(
                IUniswapV3SingleTickLiquidityHandler.MintPositionParams({
                    pool: address(pool),
                    tickLower: lowerTick,
                    tickUpper: upperTick,
                    liquidity: liquidity
                })
            )
        );
    }

    function _burnPosition(int24 lowerTick, int24 upperTick, uint128 shares) internal {
        manager.burnPosition(
            handler,
            abi.encode(
                IUniswapV3SingleTickLiquidityHandler.BurnPositionParams({
                    pool: address(pool),
                    tickLower: lowerTick,
                    tickUpper: upperTick,
                    shares: shares
                })
            )
        );
    }

    function _swapToRedeemAssets(uint256 counterAssetsIn) internal {
        router.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: address(counterAsset),
                tokenOut: address(asset),
                fee: pool.fee(),
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: counterAssetsIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );
    }
}

