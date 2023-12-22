// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

//openzepplin
import "./ReentrancyGuard.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./Math.sol";
import "./libraries_SafeCast.sol";

//Uniswap Core
import "./IUniswapV3Pool.sol";
import "./IUniswapV3MintCallback.sol";
import "./FullMath.sol";

//Enigma interfaces
import "./IEnigmaFactory.sol";
import {     Range, Rebalance, WithdrawParams, PositionLiquidity, DepositParams, BurnParams } from "./EnigmaStructs.sol";

import "./EnigmaStorage.sol";
import {UniswapLiquidityManagement} from "./UniswapLiquidityManagement.sol";

/// @title Enigma vault contracts
/// @notice Next generation liquidity management protocol ontop of Uniswap v3
/// @author by SteakHut Labs © 2023
contract Enigma is EnigmaStorage, IUniswapV3MintCallback, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeCast for uint256;
    using FullMath for uint256;

    IEnigmaFactory private immutable _factory;

    /// -----------------------------------------------------------
    /// Uniswap Mint Callback
    /// -----------------------------------------------------------

    /// @notice implement the Uniswap V3 callback fn, called when minting uniswap LP position
    function uniswapV3MintCallback(uint256 amount0, uint256 amount1, bytes calldata /*data*/ ) external override {
        if (amount0 > 0) token0.safeTransfer(msg.sender, amount0);
        if (amount1 > 0) token1.safeTransfer(msg.sender, amount1);
    }

    /// -----------------------------------------------------------
    /// Events
    /// -----------------------------------------------------------

    ///@notice events shall be contained in the IEnigma.sol

    /// -----------------------------------------------------------
    /// Constructor / Initialize (contained in storage)
    /// -----------------------------------------------------------

    /// @dev Constructor for the Enigma Pool contract that sets the Enigma Factory
    /// @param factory_ The Enigma Factory Contract
    constructor(IEnigmaFactory factory_) {
        _factory = factory_;

        // Disable the initialize function
        _parameters = bytes32(uint256(1));
    }

    /// -----------------------------------------------------------
    /// External Functions
    /// -----------------------------------------------------------

    /// @notice Primary entry point into the pool
    /// @param params despoit parameters
    /// @return shares The amount of shares provided to the recipient
    /// @return amount0 amount of token0 actually deposited
    /// @return amount1 amount of token1 actually deposited
    /// @dev should have a reentrancy gaurd applied!
    function deposit(DepositParams calldata params)
        external
        payable
        virtual
        override
        nonReentrant
        returns (uint256 shares, uint256 amount0, uint256 amount1)
    {
        require(params.recipient != address(0) && params.recipient != address(this), "to");
        require(params.amount0Desired > 0 || params.amount1Desired > 0, "deposits must be nonzero");
        require(
            params.amount0Desired <= deposit0Max && params.amount1Desired <= deposit1Max,
            "deposits must be less than maximum amounts"
        );
        require(!isPrivate || privateList[msg.sender], "must be on the list");

        //calculate the amount of shares to mint the user
        (uint256 total0, uint256 total1) = getTotalAmounts();

        (uint256 _shares, uint256 amount0Actual, uint256 amount1Actual) = UniswapLiquidityManagement
            .calcSharesAndAmounts(totalSupply(), total0, total1, params.amount0Desired, params.amount1Desired);

        //transfer the required amounts into this contract from sender
        if (params.amount0Desired > 0) {
            token0.safeTransferFrom(params.from, address(this), amount0Actual);
        }
        if (params.amount1Desired > 0) {
            token1.safeTransferFrom(params.from, address(this), amount1Actual);
        }

        //loop over the ranges in the strategy and add these too the pool
        for (uint256 index; index < ranges.length; index++) {
            Range memory _range = ranges[index];
            uint256 _amount0 = token0.balanceOf(address(this)).mulDiv(_range.distribution, PRECISION);
            uint256 _amount1 = token1.balanceOf(address(this)).mulDiv(_range.distribution, PRECISION);

            //get the applicable uniswap pool (safe as pool is checked when adding ranges)
            address _pool = factory.getPool(address(token0), address(token1), uint24(_range.feeTier));

            //compute liquidity amounts to deposit
            (uint128 _liquidity) = UniswapLiquidityManagement._liquidityForAmounts(
                _pool, _range.tickLower, _range.tickUpper, _amount0, _amount1
            );

            if (_liquidity == 0) continue;
            //mint liquidity, we should also try and handle multiple fee tiers, lets see what we can do here.
            (uint256 amount0_, uint256 amount1_) = _mintLiquidity(_pool, _range.tickLower, _range.tickUpper, _liquidity);

            //update the total amounts supplied
            amount0 += amount0_;
            amount1 += amount1_;
        }

        //mint the underlying receipt tokens
        _mint(params.recipient, _shares);
        shares = _shares;

        /// Check total supply cap not exceeded. A value of 0 means no limit.
        require(maxTotalSupply == 0 || totalSupply() <= maxTotalSupply, "maxTotalSupply");

        emit Log_Deposit(params.recipient, shares, amount0, amount1);
    }

    /// @param shares Number of liquidity tokens to redeem as pool assets
    /// @param from Address from which shares receipt tokens are burnt
    /// @param to Address to which redeemed pool assets are sent
    /// @return amount0 Amount of token0 redeemed by the submitted liquidity tokens
    /// @return amount1 Amount of token1 redeemed by the submitted liquidity tokens
    function withdraw(uint256 shares, address from, address to)
        external
        nonReentrant
        returns (uint256 amount0, uint256 amount1)
    {
        require(shares > 0, "shares");
        require(to != address(0), "to");

        uint256 totalSupply = totalSupply();

        uint256 fee0Accumulator;
        uint256 fee1Accumulator;
        //loop over the ranges in the strategy and remove the required amounts
        for (uint256 index; index < ranges.length; index++) {
            Range memory _range = ranges[index];
            //fetch the required uni pool
            address _pool = factory.getPool(address(token0), address(token1), uint24(_range.feeTier));
            //liquidity from position @ index
            (uint256 liquidity,,) = UniswapLiquidityManagement._position(_pool, _range.tickLower, _range.tickUpper);

            //attributableLiquidity to the amount of shares being removed
            uint256 attributableLiquidity = FullMath.mulDiv(shares, liquidity, totalSupply);

            //burn liquidity from the pools as required.
            BurnParams memory _params = BurnParams(
                _pool, _range.tickLower, _range.tickUpper, attributableLiquidity.toUint128(), address(this), true
            );
            (WithdrawParams memory payload) = _burnLiquidity(_params);

            //update the totals
            amount0 += payload.burn0;
            amount1 += payload.burn1;
            fee0Accumulator += payload.fee0;
            fee1Accumulator += payload.fee1;
        }

        //calculate and distribute the required fees
        _applyFeesDistribute(fee0Accumulator, fee1Accumulator);

        // distribute the unused tokens to address(to);
        // Push tokens proportional to unused balances (i.e liquidity idle in strategy)
        // currently liquidity is pushed back here and then distributed as unusedliquidity
        uint256 unusedAmount0 = FullMath.mulDiv(token0.balanceOf(address(this)), shares, totalSupply);
        uint256 unusedAmount1 = FullMath.mulDiv(token1.balanceOf(address(this)), shares, totalSupply);

        if (unusedAmount0 > 0) token0.safeTransfer(to, unusedAmount0);
        if (unusedAmount1 > 0) token1.safeTransfer(to, unusedAmount1);

        //burn share tokens
        _burn(from, shares);

        //emit event
        emit Log_CollectFees(fee0Accumulator, fee1Accumulator);
        emit Log_Withdraw(to, shares, amount0, amount1);
    }

    /// -----------------------------------------------------------
    /// Operator Functions
    /// -----------------------------------------------------------

    /// @notice rebalance Enigma's UniswapV3 positions
    /// removes liquidity from rebalanceparams, swaps and then adds liquidity
    /// @dev only Manager contract can call this function.
    function rebalance(Rebalance calldata rebalanceData) external onlyOperator nonReentrant {
        ////////////////////////////////////////////////////////////////////////////////
        //remove all the required liquidty
        ////////////////////////////////////////////////////////////////////////////////
        uint256 burn0Amount;
        uint256 burn1Amount;
        uint256 fee0Accumulator;
        uint256 fee1Accumulator;

        for (uint256 index; index < rebalanceData.burns.length; index++) {
            //burn the required liquidities
            PositionLiquidity memory _burn = rebalanceData.burns[index];

            //fetch the required uni pool

            address _pool = factory.getPool(address(token0), address(token1), uint24(_burn.range.feeTier));

            (uint256 liquidity,,) =
                UniswapLiquidityManagement._position(_pool, _burn.range.tickLower, _burn.range.tickUpper);

            //skip if no liquidity in the range
            if (liquidity == 0) continue;

            uint256 liquidityToRemove;
            if (_burn.liquidity == type(uint128).max) {
                liquidityToRemove = liquidity;
            } else {
                liquidityToRemove = _burn.liquidity;
            }

            //burn the required liquidity
            BurnParams memory _params = BurnParams(
                _pool, _burn.range.tickLower, _burn.range.tickUpper, liquidityToRemove.toUint128(), address(this), true
            );

            //burn liquidity from the pools as required.
            (WithdrawParams memory payload) = _burnLiquidity(_params);

            burn0Amount += payload.burn0;
            burn1Amount += payload.burn1;
            fee0Accumulator += payload.fee0;
            fee1Accumulator += payload.fee1;

            //if we remove all the liquidity we should also remove the range from storage
            if (liquidityToRemove >= liquidity) {
                ranges[index] = ranges[ranges.length - 1];
                ranges.pop();
            }
        }

        //take the required fees (gas saving)
        if (fee0Accumulator > 0 || fee1Accumulator > 0) {
            _applyFeesDistribute(fee0Accumulator, fee1Accumulator);
        }

        //perform final checks on burn amounts
        require(burn0Amount >= rebalanceData.minBurn0, "B0");
        require(burn0Amount >= rebalanceData.minBurn1, "B1");

        //emit events
        emit Log_CollectFees(fee0Accumulator, fee1Accumulator);

        ////////////////////////////////////////////////////////////////////////////////
        //Perform swaps if required
        ////////////////////////////////////////////////////////////////////////////////

        if (rebalanceData.swap.amountIn > 0) {
            //a swap has been commissioned by the rebalance function
            uint256 balance0Before = token0.balanceOf(address(this));
            uint256 balance1Before = token1.balanceOf(address(this));

            //grant approvals for token to the router
            token0.safeApprove(address(rebalanceData.swap.router), balance0Before);
            token1.safeApprove(address(rebalanceData.swap.router), balance1Before);

            //perform the swap
            (bool success,) = rebalanceData.swap.router.call(rebalanceData.swap.payload);
            require(success, "Enigma: Swap Reverted");

            //perform swap checks
            uint256 balance0After = token0.balanceOf(address(this));
            uint256 balance1After = token1.balanceOf(address(this));

            //check that we have recevied at least the expected amounts
            if (rebalanceData.swap.zeroForOne) {
                require(balance1After >= balance1Before + rebalanceData.swap.expectedMinReturn);
                require(balance0After >= balance0Before - rebalanceData.swap.amountIn);
            } else {
                require(balance0After >= balance0Before + rebalanceData.swap.expectedMinReturn);
                require(balance1After >= balance1Before - rebalanceData.swap.amountIn);
            }
            emit Log_Rebalance(rebalanceData, balance0After, balance1After);
        } else {
            emit Log_Rebalance(rebalanceData, 0, 0);
        }

        ////////////////////////////////////////////////////////////////////////////////
        //Add liquidity to new ranges
        ////////////////////////////////////////////////////////////////////////////////

        uint256 mint0Amount;
        uint256 mint1Amount;
        for (uint256 i; i < rebalanceData.mints.length; i++) {
            //we should do a security check that the new range actually exists

            //add the liquidity in the strategy to the new ranges
            PositionLiquidity memory position = rebalanceData.mints[i];
            uint256 amount0 = token0.balanceOf(address(this)).mulDiv(position.range.distribution, PRECISION);
            uint256 amount1 = token1.balanceOf(address(this)).mulDiv(position.range.distribution, PRECISION);

            //check if the range exists already and if not add it to the array
            Range memory range_ = Range(
                position.range.tickLower, position.range.tickUpper, position.range.feeTier, position.range.distribution
            );

            (bool exists,) = UniswapLiquidityManagement.rangeExists(ranges, range_);
            if (!exists) ranges.push(range_);

            //fetch the required uni pool
            address _pool = factory.getPool(address(token0), address(token1), uint24(position.range.feeTier));
            require(_pool != address(0), "Enigma: not a valid uniswap pool");

            (uint128 _liquidity) = UniswapLiquidityManagement._liquidityForAmounts(
                _pool, position.range.tickLower, position.range.tickUpper, amount0, amount1
            );

            if (_liquidity == 0) continue;
            //mint liquidity, we should also try and handle multiple fee tiers, lets see
            (uint256 amount0Minted, uint256 amount1Minted) =
                _mintLiquidity(_pool, position.range.tickLower, position.range.tickUpper, _liquidity);

            mint0Amount += amount0Minted;
            mint1Amount += amount1Minted;
        }
        require(mint0Amount >= rebalanceData.minDeposit0, "D0");
        require(mint1Amount >= rebalanceData.minDeposit1, "D1");
    }

    /// -----------------------------------------------------------
    /// Internal Functions
    /// -----------------------------------------------------------

    /// @notice Adds the liquidity for the given position
    /// @param tickLower The lower tick of the position in which to add liquidity
    /// @param tickUpper The upper tick of the position in which to add liquidity
    /// @param liquidity The amount of liquidity to mint
    /// @return amount0 The amount of token0 that was paid to mint the given amount of liquidity
    /// @return amount1 The amount of token1 that was paid to mint the given amount of liquidity
    function _mintLiquidity(address _pool, int24 tickLower, int24 tickUpper, uint128 liquidity)
        internal
        returns (uint256 amount0, uint256 amount1)
    {
        if (liquidity > 0) {
            (amount0, amount1) = IUniswapV3Pool(_pool).mint(address(this), tickLower, tickUpper, liquidity, "");
        }
    }

    /// @notice Burn liquidity from the sender and collect tokens owed for the liquidity
    function _burnLiquidity(BurnParams memory _burnParams) internal returns (WithdrawParams memory withdrawPayload) {
        if (_burnParams.liquidity > 0) {
            /// Burn liquidity

            (withdrawPayload.burn0, withdrawPayload.burn1) = IUniswapV3Pool(_burnParams._pool).burn(
                _burnParams.tickLower, _burnParams.tickUpper, _burnParams.liquidity
            );

            /// Collect pending amounts owed to the EnigmaPool
            uint128 _collect0 = _burnParams.collectAll ? type(uint128).max : uint128(withdrawPayload.burn0);
            uint128 _collect1 = _burnParams.collectAll ? type(uint128).max : uint128(withdrawPayload.burn1);

            //if we are collecting swap fees
            if (_collect0 > 0 || _collect1 > 0) {
                ///@dev check this logic below
                (uint256 collect0, uint256 collect1) = IUniswapV3Pool(_burnParams._pool).collect(
                    _burnParams.to, _burnParams.tickLower, _burnParams.tickUpper, _collect0, _collect1
                );

                //apply manager fees
                if (collect0 > 0 || collect1 > 0) {
                    //fee is the difference between collect what was burnt.
                    withdrawPayload.fee0 = collect0 - withdrawPayload.burn0;
                    withdrawPayload.fee1 = collect1 - withdrawPayload.burn1;
                }
            }
        }
    }

    function _applyFeesDistribute(uint256 fee0_, uint256 fee1_) internal returns (uint256 fee0, uint256 fee1) {
        fee0 = (fee0_ * SELECTED_FEE) / FEE_LIMIT;
        fee1 = (fee1_ * SELECTED_FEE) / FEE_LIMIT;

        if (fee0_ > 0 || fee1_ > 0) {
            (address enigmaFeeRecipient) = _factory.enigmaTreasury();

            //enigmaShare
            uint256 enigmaFee0 = FullMath.mulDiv(fee0_, ENIGMA_TREASURY_FEE, SELECTED_FEE);
            uint256 enigmaFee1 = FullMath.mulDiv(fee1_, ENIGMA_TREASURY_FEE, SELECTED_FEE);
            //operatorShare
            uint256 operatorFee0 = fee0_ - enigmaFee0;
            uint256 operatorFee1 = fee1_ - enigmaFee1;

            //transfer amounts
            if (fee0_ > 0) {
                //transfer 0 to reward receivers
                token0.safeTransfer(enigmaFeeRecipient, enigmaFee0);
                token0.safeTransfer(operatorAddress, operatorFee0);
            }
            if (fee1_ > 0) {
                //transfer 1 to reward receivers
                token1.safeTransfer(enigmaFeeRecipient, enigmaFee1);
                token1.safeTransfer(operatorAddress, operatorFee1);
            }

            emit Log_DistributeFees(operatorFee0, operatorFee1, enigmaFee0, enigmaFee1);
        }
    }

    /// -----------------------------------------------------------
    /// View Functions
    /// -----------------------------------------------------------

    /// @dev Calculates the largest possible `amount0` and `amount1` such that
    /// they're in the same proportion as total amounts, but not greater than
    /// `amount0Desired` and `amount1Desired` respectively.
    function getFactory() public view returns (address factory_) {
        factory_ = address(_factory);
    }

    /// @notice Calculates the vault's total holdings of token0 and token1 - in
    /// other words, how much of each token the vault would hold if it withdrew
    /// all its liquidity from Uniswap.
    function getTotalAmounts() public view returns (uint256 total0, uint256 total1) {
        //add any currently unused values contained in this contract
        total0 = token0.balanceOf(address(this));
        total1 = token1.balanceOf(address(this));

        //loop over the ranges in the strategy and add these too the pool
        for (uint256 index; index < ranges.length; index++) {
            Range memory _range = ranges[index];

            //get the applicable uniswap pool (safe as fee tier is checked when adding)
            address _pool = factory.getPool(address(token0), address(token1), uint24(_range.feeTier));

            (uint128 liquidity,,) = UniswapLiquidityManagement._position(_pool, _range.tickLower, _range.tickUpper);

            (uint256 amount0, uint256 amount1) =
                UniswapLiquidityManagement._amountsForLiquidity(_pool, _range.tickLower, _range.tickUpper, liquidity);

            if (amount0 == 0 && amount1 == 0) continue;
            total0 += amount0;
            total1 += amount1;
        }
    }

    /// -----------------------------------------------------------
    /// END Enigma by SteakHut Labs
    /// -----------------------------------------------------------
}

