// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./Constants.sol";
import "./LiquidityAmounts.sol";
import "./TickMath.sol";
import "./IFarmEvent.sol";
import "./IStrategy.sol";
import "./IStrategyInfo.sol";
import "./INonfungiblePositionManager.sol";
import "./IUniswapV3Pool.sol";
import "./SafeMath.sol";

/// @dev verified, public contract
contract Farm is IFarmEvent {
    using SafeMath for uint256;

    /// @dev deposit liquidity with one of the pair token
    /// @notice if isETH == true, user needs to transfer ETH to farm contract
    /// @notice if isETH == false, user needs to approve token to strategy contract
    function depositLiquidity(
        address _strategyContract,
        bool _isETH,
        address _inputToken,
        uint256 _inputAmount,
        uint256 _swapInAmount,
        uint256 _minimumSwapOutAmount
    ) public payable {
        uint256 shareBeforeDeposit = IStrategyInfo(_strategyContract).userShare(
            msg.sender
        );

        uint256 increasedToken0Amount;
        uint256 increasedToken1Amount;
        uint256 sendBackToken0Amount;
        uint256 sendBackToken1Amount;
        if (_isETH) {
            require(msg.value == _inputAmount, "msg.value != _inputAmount");
            (
                increasedToken0Amount,
                increasedToken1Amount,
                sendBackToken0Amount,
                sendBackToken1Amount
            ) = IStrategy(_strategyContract).depositLiquidity{
                value: _inputAmount
            }(
                _isETH,
                msg.sender,
                _inputToken,
                _inputAmount,
                _swapInAmount,
                _minimumSwapOutAmount
            );
        } else {
            (
                increasedToken0Amount,
                increasedToken1Amount,
                sendBackToken0Amount,
                sendBackToken1Amount
            ) = IStrategy(_strategyContract).depositLiquidity(
                _isETH,
                msg.sender,
                _inputToken,
                _inputAmount,
                _swapInAmount,
                _minimumSwapOutAmount
            );
        }
        uint256 shareAfterDeposit = IStrategyInfo(_strategyContract).userShare(
            msg.sender
        );

        emit DepositLiquidity(
            _strategyContract,
            msg.sender,
            IStrategyInfo(_strategyContract).liquidityNftId(),
            _isETH,
            _inputToken,
            _inputAmount,
            shareAfterDeposit.sub(shareBeforeDeposit),
            shareAfterDeposit,
            increasedToken0Amount,
            increasedToken1Amount,
            sendBackToken0Amount,
            sendBackToken1Amount
        );
    }

    /// @dev withdraw liquidity
    /// @notice user needs to approve tracker token to strategy contract in withdrawShares amount
    function withdrawLiquidity(
        address _strategyContract,
        uint256 _withdrawShares
    ) public {
        (
            uint256 userReceivedToken0Amount,
            uint256 userReceivedToken1Amount
        ) = IStrategy(_strategyContract).withdrawLiquidity(
                msg.sender,
                _withdrawShares
            );

        emit WithdrawLiquidity(
            _strategyContract,
            msg.sender,
            IStrategyInfo(_strategyContract).liquidityNftId(),
            _withdrawShares,
            IStrategyInfo(_strategyContract).userShare(msg.sender),
            userReceivedToken0Amount,
            userReceivedToken1Amount
        );
    }

    /// @dev claim usdt reward
    function claimReward(address _strategyContract) public {
        uint256 claimedRewardAmount = IStrategyInfo(_strategyContract)
            .userUsdtReward(msg.sender);
        IStrategy(_strategyContract).claimReward(msg.sender);

        emit ClaimReward(
            _strategyContract,
            msg.sender,
            IStrategyInfo(_strategyContract).liquidityNftId(),
            claimedRewardAmount
        );
    }

    /// @dev get estimate deposit used amount
    function getEstimatedUsedDepositToken(
        address _strategyContract,
        uint256 _depositAmount0,
        uint256 _depositAmount1
    )
        public
        view
        returns (uint256 estimatedUsedAmount0, uint256 estimatedUsedAmount1)
    {
        // get tick, tickUpper, tickLower sprt price
        (
            uint160 sqrtPriceX96,
            uint160 sqrtRatioAX96,
            uint160 sqrtRatioBX96
        ) = getSqrtPriceInfo(_strategyContract);

        uint128 estimatedLiquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            sqrtRatioAX96,
            sqrtRatioBX96,
            _depositAmount0,
            _depositAmount1
        );

        (estimatedUsedAmount0, estimatedUsedAmount1) = LiquidityAmounts
            .getAmountsForLiquidity(
                sqrtPriceX96,
                sqrtRatioAX96,
                sqrtRatioBX96,
                estimatedLiquidity
            );
    }

    function getSqrtPriceInfo(
        address _strategyContract
    )
        internal
        view
        returns (
            uint160 sqrtPriceX96,
            uint160 sqrtRatioAX96,
            uint160 sqrtRatioBX96
        )
    {
        // get poolAddress
        address poolAddress = IStrategyInfo(_strategyContract).poolAddress();

        // get tick
        (, int24 tick, , , , , ) = IUniswapV3Pool(poolAddress).slot0();

        // get tickUpper & tickLower
        uint256 liquidityNftId = IStrategyInfo(_strategyContract)
            .liquidityNftId();

        require(
            liquidityNftId != 0,
            "not allow calling when liquidityNftId is 0"
        );

        (
            ,
            ,
            ,
            ,
            ,
            int24 tickLower,
            int24 tickUpper,
            ,
            ,
            ,
            ,

        ) = INonfungiblePositionManager(
                Constants.NONFUNGIBLE_POSITION_MANAGER_ADDRESS
            ).positions(liquidityNftId);

        // calculate sqrtPrice
        sqrtPriceX96 = TickMath.getSqrtRatioAtTick(tick);
        sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(tickLower);
        sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(tickUpper);
    }

    function getUserShare(
        address _strategyContract,
        address _userAddress
    ) public view returns (uint256 userShare) {
        return IStrategyInfo(_strategyContract).userShare(_userAddress);
    }
}

