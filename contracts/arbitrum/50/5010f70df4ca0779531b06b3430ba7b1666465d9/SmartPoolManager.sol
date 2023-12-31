// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./IConfigurableRightsPool.sol";
import "./IPool.sol";

import "./MayfairConstants.sol";
import "./MayfairSafeMath.sol";
import "./SafeApprove.sol";

/**
 * @author Mayfair (and Balancer Labs)
 *
 * @title Library for keeping CRP contract in a managable size
 *
 * @notice Factor out weight updates, pool joining, pool exiting and token compliance
 */
library SmartPoolManager {
    // paramaters for adding a new token to the pool
    struct NewTokenParams {
        bool isCommitted;
        address addr;
        uint commitBlock;
        uint denorm;
        uint balance;
    }

    // For blockwise, automated weight updates
    // Move weights linearly from startWeights to endWeights,
    // between startBlock and endBlock
    struct GradualUpdateParams {
        uint startBlock;
        uint endBlock;
        uint[] startWeights;
        uint[] endWeights;
    }

    // updateWeight and pokeWeights are unavoidably long
    /* solhint-disable function-max-lines */

    /**
     * @notice Update the weight of an existing token
     *
     * @dev Refactored to library to make CRPFactory deployable
     *
     * @param self - ConfigurableRightsPool instance calling the library
     * @param corePool - Core Pool the CRP is wrapping
     * @param token - Address of the token to be reweighted
     * @param newWeight - New weight of the token
     * @param minimumMay - Minimum amount of $MAY to be enforced
     * @param mayToken - $MAY address to be enforced
     */
    function updateWeight(
        IConfigurableRightsPool self,
        IPool corePool,
        address token,
        uint newWeight,
        uint minimumMay,
        address mayToken
    ) external {
        require(newWeight >= MayfairConstants.MIN_WEIGHT, "ERR_MIN_WEIGHT");
        require(newWeight <= MayfairConstants.MAX_WEIGHT, "ERR_MAX_WEIGHT");

        uint currentWeight = corePool.getDenormalizedWeight(token);
        // Save gas; return immediately on NOOP
        if (currentWeight == newWeight) {
            return;
        }

        uint currentBalance = corePool.getBalance(token);
        uint totalSupply = self.totalSupply();
        uint totalWeight = corePool.getTotalDenormalizedWeight();
        uint poolShares;
        uint deltaBalance;
        uint deltaWeight;
        address controller = self.getController();

        if (newWeight < currentWeight) {
            // This means the controller will withdraw tokens to keep price
            // So they need to redeem SPTokens
            deltaWeight = currentWeight - newWeight;

            // poolShares = totalSupply * (deltaWeight / totalWeight)
            poolShares = MayfairSafeMath.bmul(
                totalSupply,
                MayfairSafeMath.bdiv(deltaWeight, totalWeight)
            );

            // deltaBalance = currentBalance * (deltaWeight / currentWeight)
            deltaBalance = MayfairSafeMath.bmul(
                currentBalance,
                MayfairSafeMath.bdiv(deltaWeight, currentWeight)
            );

            // New balance cannot be lower than MIN_BALANCE
            uint newBalance = currentBalance - deltaBalance;

            require(
                newBalance >= MayfairConstants.MIN_BALANCE,
                "ERR_MIN_BALANCE"
            );

            // First get the tokens from this contract (Pool Controller) to msg.sender
            corePool.rebind(token, newBalance, newWeight);
            require(
                minimumMay <= corePool.getNormalizedWeight(mayToken),
                "ERR_MIN_MAY"
            );

            // Now with the tokens this contract can send them to controller
            bool xfer = IERC20(token).transfer(controller, deltaBalance);
            require(xfer, "ERR_ERC20_FALSE");

            self.pullPoolShareFromLib(controller, poolShares);
            self.burnPoolShareFromLib(poolShares);
        } else {
            // This means the controller will deposit tokens to keep the price.
            // They will be minted and given SPTokens
            deltaWeight = newWeight - currentWeight;

            require(
                (totalWeight + deltaWeight) <=
                    MayfairConstants.MAX_TOTAL_WEIGHT,
                "ERR_MAX_TOTAL_WEIGHT"
            );

            // poolShares = totalSupply * (deltaWeight / totalWeight)
            poolShares = MayfairSafeMath.bmul(
                totalSupply,
                MayfairSafeMath.bdiv(deltaWeight, totalWeight)
            );
            // deltaBalance = currentBalance * (deltaWeight / currentWeight)
            deltaBalance = MayfairSafeMath.bmul(
                currentBalance,
                MayfairSafeMath.bdiv(deltaWeight, currentWeight)
            );

            // First gets the tokens from controller to this contract (Pool Controller)
            bool xfer = IERC20(token).transferFrom(
                controller,
                address(this),
                deltaBalance
            );
            require(xfer, "ERR_ERC20_FALSE");

            // Now with the tokens this contract can bind them to the pool it controls
            corePool.rebind(token, currentBalance + deltaBalance, newWeight);
            require(
                minimumMay <= corePool.getNormalizedWeight(mayToken),
                "ERR_MIN_MAY"
            );

            self.mintPoolShareFromLib(poolShares);
            self.pushPoolShareFromLib(controller, poolShares);
        }
    }

    /**
     * @notice External function called to make the contract update weights according to plan
     *
     * @param corePool - Core Pool the CRP is wrapping
     * @param gradualUpdate - Gradual update parameters from the CRP
     */
    function pokeWeights(
        IPool corePool,
        GradualUpdateParams storage gradualUpdate
    ) external {
        // Do nothing if we call this when there is no update plan
        if (gradualUpdate.startBlock == 0) {
            return;
        }

        // Error to call it before the start of the plan
        require(block.number >= gradualUpdate.startBlock, "ERR_CANT_POKE_YET");
        // Proposed error message improvement
        // require(block.number >= startBlock, "ERR_NO_HOKEY_POKEY");

        // This allows for pokes after endBlock that get weights to endWeights
        // Get the current block (or the endBlock, if we're already past the end)
        uint currentBlock;
        if (block.number > gradualUpdate.endBlock) {
            currentBlock = gradualUpdate.endBlock;
        } else {
            currentBlock = block.number;
        }

        uint blockPeriod = gradualUpdate.endBlock - gradualUpdate.startBlock;
        uint blocksElapsed = currentBlock - gradualUpdate.startBlock;
        uint weightDelta;
        uint deltaPerBlock;
        uint newWeight;

        address[] memory tokens = corePool.getCurrentTokens();

        // This loop contains external calls
        // External calls are to math libraries or the underlying pool, so low risk
        for (uint i = 0; i < tokens.length; i++) {
            // Make sure it does nothing if the new and old weights are the same (saves gas)
            // It's a degenerate case if they're *all* the same, but you certainly could have
            // a plan where you only change some of the weights in the set
            if (gradualUpdate.startWeights[i] != gradualUpdate.endWeights[i]) {
                if (
                    gradualUpdate.endWeights[i] < gradualUpdate.startWeights[i]
                ) {
                    // We are decreasing the weight

                    // First get the total weight delta
                    weightDelta =
                        gradualUpdate.startWeights[i] -
                        gradualUpdate.endWeights[i];
                    // And the amount it should change per block = total change/number of blocks in the period
                    deltaPerBlock = MayfairSafeMath.bdiv(
                        weightDelta,
                        blockPeriod
                    );
                    //deltaPerBlock = bdivx(weightDelta, blockPeriod);

                    // newWeight = startWeight - (blocksElapsed * deltaPerBlock)
                    newWeight =
                        gradualUpdate.startWeights[i] -
                        MayfairSafeMath.bmul(blocksElapsed, deltaPerBlock);
                } else {
                    // We are increasing the weight

                    // First get the total weight delta
                    weightDelta =
                        gradualUpdate.endWeights[i] -
                        gradualUpdate.startWeights[i];
                    // And the amount it should change per block = total change/number of blocks in the period
                    deltaPerBlock = MayfairSafeMath.bdiv(
                        weightDelta,
                        blockPeriod
                    );
                    //deltaPerBlock = bdivx(weightDelta, blockPeriod);

                    // newWeight = startWeight + (blocksElapsed * deltaPerBlock)
                    newWeight =
                        gradualUpdate.startWeights[i] +
                        MayfairSafeMath.bmul(blocksElapsed, deltaPerBlock);
                }

                uint bal = corePool.getBalance(tokens[i]);

                corePool.rebind(tokens[i], bal, newWeight);
            }
        }

        // Reset to allow add/remove tokens, or manual weight updates
        if (block.number >= gradualUpdate.endBlock) {
            gradualUpdate.startBlock = 0;
        }
    }

    /* solhint-enable function-max-lines */

    /**
     * @notice Schedule (commit) a token to be added; must call applyAddToken after a fixed
     *         number of blocks to actually add the token
     *
     * @param corePool - Core Pool the CRP is wrapping
     * @param token - Address of the token to be added
     * @param balance - How much to be added
     * @param denormalizedWeight - The desired token denormalized weight
     * @param newToken - NewTokenParams struct used to hold the token data (in CRP storage)
     */
    function commitAddToken(
        IPool corePool,
        address token,
        uint balance,
        uint denormalizedWeight,
        NewTokenParams storage newToken
    ) external {
        verifyTokenComplianceInternal(token);

        require(!corePool.isBound(token), "ERR_IS_BOUND");
        require(
            denormalizedWeight <= MayfairConstants.MAX_WEIGHT,
            "ERR_WEIGHT_ABOVE_MAX"
        );
        require(
            denormalizedWeight >= MayfairConstants.MIN_WEIGHT,
            "ERR_WEIGHT_BELOW_MIN"
        );
        require(
            (corePool.getTotalDenormalizedWeight() + denormalizedWeight) <=
                MayfairConstants.MAX_TOTAL_WEIGHT,
            "ERR_MAX_TOTAL_WEIGHT"
        );
        require(
            balance >= MayfairConstants.MIN_BALANCE,
            "ERR_BALANCE_BELOW_MIN"
        );

        newToken.addr = token;
        newToken.balance = balance;
        newToken.denorm = denormalizedWeight;
        newToken.commitBlock = block.number;
        newToken.isCommitted = true;
    }

    /**
     * @notice Add the token previously committed (in commitAddToken) to the pool
     *
     * @param self - ConfigurableRightsPool instance calling the library
     * @param corePool - Core Pool the CRP is wrapping
     * @param addTokenTimeLockInBlocks - Wait time between committing and applying a new token
     * @param newToken - NewTokenParams struct used to hold the token data (in CRP storage)
     */
    function applyAddToken(
        IConfigurableRightsPool self,
        IPool corePool,
        uint addTokenTimeLockInBlocks,
        NewTokenParams storage newToken
    ) external {
        require(newToken.isCommitted, "ERR_NO_TOKEN_COMMIT");
        require(
            (block.number - newToken.commitBlock) >= addTokenTimeLockInBlocks,
            "ERR_TIMELOCK_STILL_COUNTING"
        );

        uint totalSupply = self.totalSupply();
        address controller = self.getController();

        // poolShares = totalSupply * newTokenWeight / totalWeight
        uint poolShares = MayfairSafeMath.bdiv(
            MayfairSafeMath.bmul(totalSupply, newToken.denorm),
            corePool.getTotalDenormalizedWeight()
        );

        // Clear this to allow adding more tokens
        newToken.isCommitted = false;

        // First gets the tokens from msg.sender to this contract (Pool Controller)
        bool returnValue = IERC20(newToken.addr).transferFrom(
            controller,
            address(self),
            newToken.balance
        );
        require(returnValue, "ERR_ERC20_FALSE");

        // Now with the tokens this contract can bind them to the pool it controls
        // Approves corePool to pull from this controller
        // Approve unlimited, same as when creating the pool, so they can join pools later
        returnValue = SafeApprove.safeApprove(
            IERC20(newToken.addr),
            address(corePool),
            MayfairConstants.MAX_UINT
        );
        require(returnValue, "ERR_ERC20_FALSE");

        corePool.bind(newToken.addr, newToken.balance, newToken.denorm);

        self.mintPoolShareFromLib(poolShares);
        self.pushPoolShareFromLib(controller, poolShares);
    }

    /**
     * @notice Remove a token from the pool
     *
     * @dev Logic in the CRP controls when this can be called. There are two related permissions:
     *      AddRemoveTokens - which allows removing down to the underlying Pool limit of two
     *      RemoveAllTokens - which allows completely draining the pool by removing all tokens
     *                        This can result in a non-viable pool with 0 or 1 tokens (by design),
     *                        meaning all swapping or binding operations would fail in this state
     *
     * @param self - ConfigurableRightsPool instance calling the library
     * @param corePool - Core Pool the CRP is wrapping
     * @param token - Address of the token to remove
     */
    function removeToken(
        IConfigurableRightsPool self,
        IPool corePool,
        address token
    ) external {
        uint totalSupply = self.totalSupply();
        address controller = self.getController();

        // poolShares = totalSupply * tokenWeight / totalWeight
        uint poolShares = MayfairSafeMath.bdiv(
            MayfairSafeMath.bmul(
                totalSupply,
                corePool.getDenormalizedWeight(token)
            ),
            corePool.getTotalDenormalizedWeight()
        );

        // this is what will be unbound from the pool
        // Have to get it before unbinding
        uint balance = corePool.getBalance(token);

        // Unbind and get the tokens out of the pool
        corePool.unbind(token);

        // Now with the tokens this contract can send them to msg.sender
        bool xfer = IERC20(token).transfer(controller, balance);
        require(xfer, "ERR_ERC20_FALSE");

        self.pullPoolShareFromLib(controller, poolShares);
        self.burnPoolShareFromLib(poolShares);
    }

    /**
     * @notice Non ERC20-conforming tokens are problematic; don't allow them in pools
     *
     * @dev Will revert if invalid
     *
     * @param token - The prospective token to verify
     */
    function verifyTokenCompliance(address token) external {
        verifyTokenComplianceInternal(token);
    }

    /**
     * @notice Non ERC20-conforming tokens are problematic; don't allow them in pools
     *
     * @dev Will revert if invalid - overloaded to save space in the main contract
     *
     * @param tokens - Array of addresses of prospective tokens to verify
     * @param tokenWeights - Array of denormalized weights of prospective tokens
     * @param minimumMay - Minimum amount of $MAY to be enforced
     * @param mayToken - $MAY address to be enforced
     */
    function verifyTokenCompliance(
        address[] calldata tokens,
        uint[] calldata tokenWeights,
        uint minimumMay,
        address mayToken
    ) external {
        uint totalWeight;
        uint mayWeight;

        for (uint i = 0; i < tokens.length; i++) {
            verifyTokenComplianceInternal(tokens[i]);
            totalWeight += tokenWeights[i];

            if (tokens[i] == mayToken) {
                mayWeight = tokenWeights[i];
            }
        }

        require(
            minimumMay <= MayfairSafeMath.bdiv(mayWeight, totalWeight),
            "ERR_MIN_MAY"
        );
    }

    /**
     * @notice Update weights in a predetermined way, between startBlock and endBlock,
     *         through external cals to pokeWeights
     *
     * @param corePool - Core Pool the CRP is wrapping
     * @param newWeights - Final weights we want to get to
     * @param startBlock - When weights should start to change
     * @param endBlock - When weights will be at their final values
     * @param minimumWeightChangeBlockPeriod - Needed to validate the block period
     * @param minimumMay - Minimum amount of $MAY to be enforced
     * @param mayToken - $MAY address to be enforced
     */
    function updateWeightsGradually(
        IPool corePool,
        GradualUpdateParams storage gradualUpdate,
        uint[] calldata newWeights,
        uint startBlock,
        uint endBlock,
        uint minimumWeightChangeBlockPeriod,
        uint minimumMay,
        address mayToken
    ) external {
        require(block.number < endBlock, "ERR_GRADUAL_UPDATE_TIME_TRAVEL");

        if (block.number > startBlock) {
            // This means the weight update should start ASAP
            // Moving the start block up prevents a big jump/discontinuity in the weights
            gradualUpdate.startBlock = block.number;
        } else {
            gradualUpdate.startBlock = startBlock;
        }

        // Enforce a minimum time over which to make the changes
        // The also prevents endBlock <= startBlock
        require(
            (endBlock - gradualUpdate.startBlock) >=
                minimumWeightChangeBlockPeriod,
            "ERR_WEIGHT_CHANGE_TIME_BELOW_MIN"
        );

        address[] memory tokens = corePool.getCurrentTokens();

        // Must specify weights for all tokens
        require(
            newWeights.length == tokens.length,
            "ERR_START_WEIGHTS_MISMATCH"
        );

        uint weightsSum = 0;
        uint mayDenorm = 0;
        gradualUpdate.startWeights = new uint[](tokens.length);

        // Check that endWeights are valid now to avoid reverting in a future pokeWeights call
        //
        // This loop contains external calls
        // External calls are to math libraries or the underlying pool, so low risk
        for (uint i = 0; i < tokens.length; i++) {
            require(
                newWeights[i] <= MayfairConstants.MAX_WEIGHT,
                "ERR_WEIGHT_ABOVE_MAX"
            );
            require(
                newWeights[i] >= MayfairConstants.MIN_WEIGHT,
                "ERR_WEIGHT_BELOW_MIN"
            );

            if (tokens[i] == mayToken) {
                mayDenorm = newWeights[i];
            }

            weightsSum += newWeights[i];
            gradualUpdate.startWeights[i] = corePool.getDenormalizedWeight(
                tokens[i]
            );
        }
        require(
            weightsSum <= MayfairConstants.MAX_TOTAL_WEIGHT,
            "ERR_MAX_TOTAL_WEIGHT"
        );
        require(
            minimumMay <= MayfairSafeMath.bdiv(mayDenorm, weightsSum),
            "ERR_MIN_MAY"
        );

        gradualUpdate.endBlock = endBlock;
        gradualUpdate.endWeights = newWeights;
    }

    /**
     * @notice Join a pool
     *
     * @param self - ConfigurableRightsPool instance calling the library
     * @param corePool - Core Pool the CRP is wrapping
     * @param poolAmountOut - Number of pool tokens to receive
     * @param maxAmountsIn - Max amount of asset tokens to spend
     *
     * @return actualAmountsIn - Calculated values of the tokens to pull in
     */
    function joinPool(
        IConfigurableRightsPool self,
        IPool corePool,
        uint poolAmountOut,
        uint[] calldata maxAmountsIn
    ) external view returns (uint[] memory actualAmountsIn) {
        address[] memory tokens = corePool.getCurrentTokens();

        require(maxAmountsIn.length == tokens.length, "ERR_AMOUNTS_MISMATCH");

        uint poolTotal = self.totalSupply();
        // Subtract  1 to ensure any rounding errors favor the pool
        uint ratio = MayfairSafeMath.bdiv(poolAmountOut, poolTotal - 1);

        require(ratio != 0, "ERR_MATH_APPROX");

        // We know the length of the array; initialize it, and fill it below
        // Cannot do "push" in memory
        actualAmountsIn = new uint[](tokens.length);

        // This loop contains external calls
        // External calls are to math libraries or the underlying pool, so low risk
        for (uint i = 0; i < tokens.length; i++) {
            address t = tokens[i];
            uint bal = corePool.getBalance(t);
            // Add 1 to ensure any rounding errors favor the pool
            uint tokenAmountIn = MayfairSafeMath.bmul(ratio, bal + 1);

            require(tokenAmountIn != 0, "ERR_MATH_APPROX");
            require(tokenAmountIn <= maxAmountsIn[i], "ERR_LIMIT_IN");

            actualAmountsIn[i] = tokenAmountIn;
        }
    }

    /**
     * @notice Exit a pool - redeem pool tokens for underlying assets
     *
     * @param self - ConfigurableRightsPool instance calling the library
     * @param corePool - Core Pool the CRP is wrapping
     * @param poolAmountIn - Amount of pool tokens to redeem
     * @param minAmountsOut - Minimum amount of asset tokens to receive
     *
     * @return exitFee - Calculated exit fee
     * @return pAiAfterExitFee - Final amount in (after accounting for exit fee)
     * @return actualAmountsOut - Calculated amounts of each token to pull
     */
    function exitPool(
        IConfigurableRightsPool self,
        IPool corePool,
        uint poolAmountIn,
        uint[] calldata minAmountsOut
    )
        external
        view
        returns (
            uint exitFee,
            uint pAiAfterExitFee,
            uint[] memory actualAmountsOut
        )
    {
        address[] memory tokens = corePool.getCurrentTokens();

        require(minAmountsOut.length == tokens.length, "ERR_AMOUNTS_MISMATCH");

        uint poolTotal = self.totalSupply();

        // Calculate exit fee and the final amount in
        if (msg.sender != corePool.getExitFeeCollector()) {
            exitFee = MayfairSafeMath.bmul(poolAmountIn, corePool.getExitFee());
        }

        pAiAfterExitFee = poolAmountIn - exitFee;
        uint ratio = MayfairSafeMath.bdiv(pAiAfterExitFee, poolTotal + 1);

        require(ratio != 0, "ERR_MATH_APPROX");

        actualAmountsOut = new uint[](tokens.length);

        // This loop contains external calls
        // External calls are to math libraries or the underlying pool, so low risk
        for (uint i = 0; i < tokens.length; i++) {
            address t = tokens[i];
            uint bal = corePool.getBalance(t);
            // Subtract 1 to ensure any rounding errors favor the pool
            uint tokenAmountOut = MayfairSafeMath.bmul(ratio, bal - 1);

            require(tokenAmountOut != 0, "ERR_MATH_APPROX");
            require(tokenAmountOut >= minAmountsOut[i], "ERR_LIMIT_OUT");

            actualAmountsOut[i] = tokenAmountOut;
        }
    }

    /**
     * @notice Join by swapping a fixed amount of an external token in (must be present in the pool)
     *         System calculates the pool token amount
     *
     * @param self - ConfigurableRightsPool instance calling the library
     * @param corePool - Core Pool the CRP is wrapping
     * @param tokenIn - Which token we're transferring in
     * @param tokenAmountIn - Amount of deposit
     * @param minPoolAmountOut - Minimum of pool tokens to receive
     *
     * @return poolAmountOut - Amount of pool tokens minted and transferred
     */
    function joinswapExternAmountIn(
        IConfigurableRightsPool self,
        IPool corePool,
        address tokenIn,
        uint tokenAmountIn,
        uint minPoolAmountOut
    ) external view returns (uint poolAmountOut) {
        require(corePool.isBound(tokenIn), "ERR_NOT_BOUND");
        require(
            tokenAmountIn <=
                MayfairSafeMath.bmul(
                    corePool.getBalance(tokenIn),
                    MayfairConstants.MAX_IN_RATIO
                ),
            "ERR_MAX_IN_RATIO"
        );

        poolAmountOut = corePool.calcPoolOutGivenSingleIn(
            corePool.getBalance(tokenIn),
            corePool.getDenormalizedWeight(tokenIn),
            self.totalSupply(),
            corePool.getTotalDenormalizedWeight(),
            tokenAmountIn,
            corePool.getSwapFee()
        );

        require(poolAmountOut >= minPoolAmountOut, "ERR_LIMIT_OUT");
    }

    /**
     * @notice Join by swapping an external token in (must be present in the pool)
     *         To receive an exact amount of pool tokens out. System calculates the deposit amount
     *
     * @param self - ConfigurableRightsPool instance calling the library
     * @param corePool - Core Pool the CRP is wrapping
     * @param tokenIn - Which token we're transferring in (system calculates amount required)
     * @param poolAmountOut - Amount of pool tokens to be received
     * @param maxAmountIn - Maximum asset tokens that can be pulled to pay for the pool tokens
     *
     * @return tokenAmountIn - amount of asset tokens transferred in to purchase the pool tokens
     */
    function joinswapPoolAmountOut(
        IConfigurableRightsPool self,
        IPool corePool,
        address tokenIn,
        uint poolAmountOut,
        uint maxAmountIn
    ) external view returns (uint tokenAmountIn) {
        require(corePool.isBound(tokenIn), "ERR_NOT_BOUND");

        tokenAmountIn = corePool.calcSingleInGivenPoolOut(
            corePool.getBalance(tokenIn),
            corePool.getDenormalizedWeight(tokenIn),
            self.totalSupply(),
            corePool.getTotalDenormalizedWeight(),
            poolAmountOut,
            corePool.getSwapFee()
        );

        require(tokenAmountIn != 0, "ERR_MATH_APPROX");
        require(tokenAmountIn <= maxAmountIn, "ERR_LIMIT_IN");

        require(
            tokenAmountIn <=
                MayfairSafeMath.bmul(
                    corePool.getBalance(tokenIn),
                    MayfairConstants.MAX_IN_RATIO
                ),
            "ERR_MAX_IN_RATIO"
        );
    }

    /**
     * @notice Exit a pool - redeem a specific number of pool tokens for an underlying asset
     *         Asset must be present in the pool, and will incur an _exitFee (if set to non-zero)
     *
     * @param self - ConfigurableRightsPool instance calling the library
     * @param corePool - Core Pool the CRP is wrapping
     * @param tokenOut - Which token the caller wants to receive
     * @param poolAmountIn - Amount of pool tokens to redeem
     * @param minAmountOut - Minimum asset tokens to receive
     *
     * @return exitFee - Calculated exit fee
     * @return pAiAfterExitFee - Pool amount in after exit fee
     * @return tokenAmountOut - Amount of asset tokens returned
     */
    function exitswapPoolAmountIn(
        IConfigurableRightsPool self,
        IPool corePool,
        address tokenOut,
        uint poolAmountIn,
        uint minAmountOut
    )
        external
        view
        returns (uint exitFee, uint pAiAfterExitFee, uint tokenAmountOut)
    {
        require(corePool.isBound(tokenOut), "ERR_NOT_BOUND");

        if (msg.sender != corePool.getExitFeeCollector()) {
            exitFee = corePool.getExitFee();
        }

        tokenAmountOut = corePool.calcSingleOutGivenPoolIn(
            corePool.getBalance(tokenOut),
            corePool.getDenormalizedWeight(tokenOut),
            self.totalSupply(),
            corePool.getTotalDenormalizedWeight(),
            poolAmountIn,
            corePool.getSwapFee(),
            exitFee
        );

        require(tokenAmountOut >= minAmountOut, "ERR_LIMIT_OUT");
        require(
            tokenAmountOut <=
                MayfairSafeMath.bmul(
                    corePool.getBalance(tokenOut),
                    MayfairConstants.MAX_OUT_RATIO
                ),
            "ERR_MAX_OUT_RATIO"
        );

        exitFee = MayfairSafeMath.bmul(poolAmountIn, exitFee);
        pAiAfterExitFee = poolAmountIn - exitFee;
    }

    /**
     * @notice Exit a pool - redeem pool tokens for a specific amount of underlying assets
     *         Asset must be present in the pool
     *
     * @param self - ConfigurableRightsPool instance calling the library
     * @param corePool - Core Pool the CRP is wrapping
     * @param tokenOut - Which token the caller wants to receive
     * @param tokenAmountOut - Amount of underlying asset tokens to receive
     * @param maxPoolAmountIn - Maximum pool tokens to be redeemed
     *
     * @return exitFee - Calculated exit fee
     * @return pAiAfterExitFee - Pool amount in after exit fee
     * @return poolAmountIn - Amount of pool tokens redeemed
     */
    function exitswapExternAmountOut(
        IConfigurableRightsPool self,
        IPool corePool,
        address tokenOut,
        uint tokenAmountOut,
        uint maxPoolAmountIn
    )
        external
        view
        returns (uint exitFee, uint pAiAfterExitFee, uint poolAmountIn)
    {
        require(corePool.isBound(tokenOut), "ERR_NOT_BOUND");
        require(
            tokenAmountOut <=
                MayfairSafeMath.bmul(
                    corePool.getBalance(tokenOut),
                    MayfairConstants.MAX_OUT_RATIO
                ),
            "ERR_MAX_OUT_RATIO"
        );

        if (msg.sender != corePool.getExitFeeCollector()) {
            exitFee = corePool.getExitFee();
        }

        poolAmountIn = corePool.calcPoolInGivenSingleOut(
            corePool.getBalance(tokenOut),
            corePool.getDenormalizedWeight(tokenOut),
            self.totalSupply(),
            corePool.getTotalDenormalizedWeight(),
            tokenAmountOut,
            corePool.getSwapFee(),
            exitFee
        );

        require(poolAmountIn != 0, "ERR_MATH_APPROX");
        require(poolAmountIn <= maxPoolAmountIn, "ERR_LIMIT_IN");

        exitFee = MayfairSafeMath.bmul(poolAmountIn, exitFee);
        pAiAfterExitFee = poolAmountIn - exitFee;
    }

    /**
     * @dev Check for zero transfer, and make sure it returns true to returnValue
     *
     * @param token - Address of the possible token
     */
    function verifyTokenComplianceInternal(address token) internal {
        bool returnValue = IERC20(token).transfer(msg.sender, 0);
        require(returnValue, "ERR_NONCONFORMING_TOKEN");
    }
}

