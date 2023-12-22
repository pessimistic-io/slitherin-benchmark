// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./EnumerableSet.sol";

import "./ILBPair.sol";
import "./ILBRouter.sol";
import "./ILBToken.sol";

import "./ILBStrategy.sol";
import "./LiquidityAmounts.sol";
import "./StatManager.sol";

/// @title StrategyTJLiquidityBookLB
/// @author SteakHut Finance
/// @notice used in conjunction with a vault to manage TraderJoe Liquidity Book Positions
contract StrategyTJLiquidityBookLB is StratManager {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.UintSet;

    uint256 constant PRECISION = 1e18;

    uint256 public lastHarvest;

    /// @notice parameters which should not be changed after init
    IERC20 public immutable tokenX;
    IERC20 public immutable tokenY;
    ILBPair public immutable lbPair;
    ILBToken public immutable lbToken;
    uint16 public immutable binStep;

    /// @notice parameters which may be changed by a strategist
    int256[] public deltaIds;
    uint256[] public distributionX;
    uint256[] public distributionY;
    uint256 public idSlippage;
    uint256 public percentForSwap = 40;

    /// @notice where strategy currently has a non-zero balance in bins
    EnumerableSet.UintSet private _activeBins;

    /// -----------------------------------------------------------
    /// Events
    /// -----------------------------------------------------------
    event CollectRewards(
        uint256 lastHarvest,
        uint256 amountXBefore,
        uint256 amountYBefore,
        uint256 amountXAfter,
        uint256 amountYAfter
    );

    event FeeTransfer(uint256 amountX, uint256 amountY);

    event AddLiquidity(
        address user,
        uint256 amountX,
        uint256 amountY,
        uint256 liquidity
    );

    event RemoveLiquidity(address user, uint256 amountX, uint256 amountY);

    event Rebalance(
        uint256 amountXBefore,
        uint256 amountYBefore,
        uint256 amountXAfter,
        uint256 amountYAfter
    );

    /// -----------------------------------------------------------
    /// Constructor
    /// -----------------------------------------------------------

    constructor(
        address _joeRouter,
        address _keeper,
        ILBStrategy.StrategyParameters memory _strategyParams
    ) StratManager(_keeper, _joeRouter) {
        //require strategy to use < 50 bins due to gas limits
        require(
            _strategyParams.deltaIds.length < 50,
            "Strategy: Too many bins"
        );

        //check parameters are equal in length
        require(
            _strategyParams.deltaIds.length ==
            _strategyParams.distributionX.length &&
            _strategyParams.distributionX.length ==
            _strategyParams.distributionY.length,
            "Strategy: Unbalanced params"
        );

        //check distributions are equal
        if (binHasXLiquidity(_strategyParams.deltaIds)) {
            _checkDistribution(_strategyParams.distributionX);
        }
        if (binHasYLiquidity(_strategyParams.deltaIds)) {
            _checkDistribution(_strategyParams.distributionY);
        }

        //set immutable strategy parameters
        tokenX = _strategyParams.tokenX;
        tokenY = _strategyParams.tokenY;
        lbPair = ILBPair(_strategyParams.pair);
        lbToken = ILBToken(_strategyParams.pair);
        binStep = _strategyParams.binStep;

        //set strategist controlled initial parameters
        deltaIds = _strategyParams.deltaIds;
        idSlippage = _strategyParams.idSlippage;
        distributionX = _strategyParams.distributionX;
        distributionY = _strategyParams.distributionY;

        //give the strategy the required allowances
        _giveAllowances();
    }

    /// -----------------------------------------------------------
    /// Track Strategy Bin Functions
    /// -----------------------------------------------------------

    /// @notice Returns the type id at index `_index` where strategy has a non-zero balance
    /// @param _index The position index
    /// @return The non-zero position at index `_index`
    function strategyPositionAtIndex(
        uint256 _index
    ) public view returns (uint256) {
        return _activeBins.at(_index);
    }

    /// @notice Returns the number of non-zero balances of strategy
    /// @return The number of non-zero balances of strategy
    function strategyPositionNumber() public view returns (uint256) {
        return _activeBins.length();
    }

    /// @notice returns all of the active bin Ids in the strategy
    /// @return activeBins currently in use by the strategy
    function strategyActiveBins()
    public
    view
    returns (uint256[] memory activeBins)
    {
        activeBins = new uint256[](_activeBins.length());
        for (uint256 i; i < _activeBins.length(); i++) {
            activeBins[i] = strategyPositionAtIndex(i);
        }
    }

    /// @notice checks the proposed bin length
    /// @notice helps to ensure that we wont exceed the 50 bin limit in single call
    /// @return numProposedIds number of proposed bin Ids
    function checkProposedBinLength(
        int256[] memory proposedDeltas,
        uint256 activeId
    ) public view returns (uint256) {
        uint256 newIdCount;
        for (uint256 i; i < proposedDeltas.length; i++) {
            int256 _id = int256(activeId) + proposedDeltas[i];

            //if the proposed ID doesnt exist count it
            if (!_activeBins.contains(uint256(_id))) {
                newIdCount += 1;
            }
        }
        return (newIdCount + strategyPositionNumber());
    }

    /// -----------------------------------------------------------
    /// Internal functions
    /// -----------------------------------------------------------

    /// Internal function that adds liquidity to AMM and gets Liquidity Book tokens.
    /// @param amountX max amount of token X to add as liquidity
    /// @param amountY max amount of token Y to add as liquidity
    /// @param amountXMin min amount of token X to add as liquidity
    /// @param amountYMin min amount of token Y to add as liquidity
    /// @return depositIds the depositIds where liquidity was minted
    /// @return liquidityMinted set of liquidity deposited in each bin
    function _addLiquidity(
        uint256 amountX,
        uint256 amountY,
        uint256 amountXMin,
        uint256 amountYMin
    )
    internal
    whenNotPaused
    returns (uint256[] memory depositIds, uint256[] memory liquidityMinted)
    {
        //fetch the current active Id.
        (, , uint256 activeId) = lbPair.getReservesAndId();

        //check bin lengths are less than 50 bins due to block limit
        //further liquidity cannot be added until rebalanced
        require(
            checkProposedBinLength(deltaIds, activeId) < 50,
            "Strategy: Requires Rebalance"
        );

        //set the required liquidity parameters
        ILBRouter.LiquidityParameters memory liquidityParameters = ILBRouter.LiquidityParameters(
            tokenX,
            tokenY,
            binStep,
            amountX,
            amountY,
            amountXMin,
            amountYMin,
            activeId,
            idSlippage,
            deltaIds,
            distributionX,
            distributionY,
            address(this),
            block.timestamp
        );

        //add the required liquidity into the pair
        (depositIds, liquidityMinted) = ILBRouter(joeRouter).addLiquidity(
            liquidityParameters
        );

        //sum the total amount of liquidity minted
        uint256 liquidtyMintedHolder;
        for (uint256 i; i < liquidityMinted.length; i++) {
            liquidtyMintedHolder += liquidityMinted[i];
            //add the ID's to the user set
            _activeBins.add(depositIds[i]);
        }

        require(
            _activeBins.length() < 50,
            "Strategy: Too many bins after add; manager check bin slippage and call rebalance"
        );

        //emit an event
        emit AddLiquidity(msg.sender, amountX, amountY, liquidtyMintedHolder);
    }

    /// @notice performs the removal of liquidity from the pair and keeps tokens in strategy
    /// @param denominator the ownership stake to remove
    /// @notice PRECISION is full amount i.e all liquidity to be removed
    /// @return amountX the amount of liquidity removed as tokenX
    /// @return amountY the amount of liquidity removed as tokenY
    function _removeLiquidity(
        uint256 denominator
    ) internal returns (uint256 amountX, uint256 amountY) {
        uint256[] memory activeBinIds = getActiveBinIds();
        uint256[] memory amounts = new uint256[](activeBinIds.length);

        uint256 totalXBalanceWithdrawn;
        uint256 totalYBalanceWithdrawn;

        // To figure out amountXMin and amountYMin, we calculate how much X and Y underlying we have as liquidity
        for (uint256 i; i < activeBinIds.length; i++) {
            //amount of LBToken in each active bin
            uint256 LBTokenAmount = (PRECISION *
            lbToken.balanceOf(address(this), activeBinIds[i])) /
            (denominator);

            amounts[i] = LBTokenAmount;
            (uint256 binReserveX, uint256 binReserveY) = lbPair.getBin(
                uint24(activeBinIds[i])
            );

            totalXBalanceWithdrawn +=
            (LBTokenAmount * binReserveX) /
            lbToken.totalSupply(activeBinIds[i]);
            totalYBalanceWithdrawn +=
            (LBTokenAmount * binReserveY) /
            lbToken.totalSupply(activeBinIds[i]);
        }

        uint256 minTotalXBalanceWithSlippage = totalXBalanceWithdrawn * 99 / 100;
        uint256 minTotalYBalanceWithSlippage = totalYBalanceWithdrawn * 99 / 100;

        //remove the liquidity required
        (amountX, amountY) = ILBRouter(payable(joeRouter)).removeLiquidity(
            tokenX,
            tokenY,
            binStep,
            minTotalXBalanceWithSlippage,
            minTotalYBalanceWithSlippage,
            activeBinIds,
            amounts,
            address(this),
            block.timestamp
        );

        //remove the ids from the userSet; this needs to occur if we are withdrawing all liquidity
        //or if we are rebalancing not each time liquidity is withdrawn
        if (denominator == PRECISION) {
            for (uint256 i; i < activeBinIds.length; i++) {
                _activeBins.remove(activeBinIds[i]);
            }
        }

        //emit event
        emit RemoveLiquidity(msg.sender, amountX, amountY);
    }

    /// @notice gives the allowances required for this strategy
    function _giveAllowances() internal {
        uint256 MAX_INT = 2 ** 256 - 1;

        tokenX.safeApprove(joeRouter, uint256(MAX_INT));
        tokenY.safeApprove(joeRouter, uint256(MAX_INT));

        tokenX.safeApprove(owner(), uint256(MAX_INT));
        tokenY.safeApprove(owner(), uint256(MAX_INT));

        //provide required lb token approvals
        lbToken.setApprovalForAll(address(joeRouter), true);
    }

    /// @notice remove allowances for this strategy
    function _removeAllowances() internal {
        tokenX.safeApprove(joeRouter, 0);
        tokenY.safeApprove(joeRouter, 0);

        tokenX.safeApprove(owner(), 0);
        tokenY.safeApprove(owner(), 0);

        //revoke required lb token approvals
        lbToken.setApprovalForAll(address(joeRouter), false);
    }

    /// @notice swaps tokens from the strategy
    /// @param amountIn the amount of token that needs to be swapped
    /// @param _swapForY is tokenX being swapped for tokenY
    function _swap(
        uint256 amountIn,
        bool _swapForY
    ) internal returns (uint256 amountOutReal) {
        IERC20[] memory tokenPath = new IERC20[](2);

        //set the required token paths
        if (_swapForY) {
            tokenPath[0] = tokenX;
            tokenPath[1] = tokenY;
        } else {
            tokenPath[0] = tokenY;
            tokenPath[1] = tokenX;
        }

        //compute the required bin step
        uint256[] memory pairBinSteps = new uint256[](1);
        pairBinSteps[0] = binStep;

        //        (uint256 amountOut,) = ILBRouter(joeRouter).getSwapOut(lbPair, amountIn, _swapForY);
        //        uint256 amountOutWithSlippage = amountOut * 99 / 100;

        //perform the swapping of tokens
        amountOutReal = ILBRouter(joeRouter).swapExactTokensForTokens(
            amountIn,
            0,
            pairBinSteps,
            tokenPath,
            address(this),
            block.timestamp
        );
    }

    /// @notice harvests the earnings and takes a performance fee
    function _harvest() internal returns (uint256 amountXReceived, uint256 amountYReceived) {
        //collects pending rewards
        (amountXReceived, amountYReceived) = _collectRewards();

        lastHarvest = block.timestamp;
    }

    /// @notice collects any availiable rewards from the pair and charges fees
    /// @return amountXReceived tokenX amount received
    /// @return amountYReceived tokenY amount received
    function _collectRewards() internal returns (uint256 amountXReceived, uint256 amountYReceived) {
        uint256[] memory activeBinIds = getActiveBinIds();

        (amountXReceived, amountYReceived) = lbPair.collectFees(
            address(this),
            activeBinIds
        );
    }

    //    /// @notice charges protocol and strategist fees and distributes
    //    /// @param callFeeRecipient the address who will receive the call fee
    //    /// @param amountXReceived amount of tokenX to take a fee on
    //    /// @param amountYReceived amount of tokenY to take a fee on
    //    function _chargeFees(
    //        address callFeeRecipient,
    //        uint256 amountXReceived,
    //        uint256 amountYReceived
    //    ) internal {
    //        uint256 balX = (amountXReceived * performanceFee) / MAX_FEE;
    //        uint256 balY = (amountYReceived * performanceFee) / MAX_FEE;
    //
    //        if (balX > 0 || balY > 0) {
    //            uint256 callFeeAmountX = (balX * callFee) / MAX_FEE;
    //            uint256 callFeeAmountY = (balY * callFee) / MAX_FEE;
    //
    //            uint256 steakHutFeeAmountX = (balX * steakHutFee) / MAX_FEE;
    //            uint256 steakHutFeeAmountY = (balY * steakHutFee) / MAX_FEE;
    //
    //            uint256 strategistFeeX = (balX * STRATEGIST_FEE) / MAX_FEE;
    //            uint256 strategistFeeY = (balY * STRATEGIST_FEE) / MAX_FEE;
    //
    //            if (balX > 0) {
    //                //transfer x to reward receivers
    //                tokenX.safeTransfer(feeRecipient, steakHutFeeAmountX);
    //                tokenX.safeTransfer(callFeeRecipient, callFeeAmountX);
    //                tokenX.safeTransfer(strategist, strategistFeeX);
    //            }
    //            if (balY > 0) {
    //                //transfer y to reward receivers
    //                tokenY.safeTransfer(feeRecipient, steakHutFeeAmountY);
    //                tokenY.safeTransfer(callFeeRecipient, callFeeAmountY);
    //                tokenY.safeTransfer(strategist, strategistFeeY);
    //            }
    //
    //            //emit an event
    //            emit FeeTransfer(balX, balY);
    //        }
    //    }

    /// @notice helper safety check to see if distX and distY add to PRECISION
    /// @param _distribution distributionX or distributionY to check
    function _checkDistribution(uint256[] memory _distribution) internal pure {
        uint256 total;

        //loop over the distribution provided and make sure to sum to PRECISION
        for (uint256 i; i < _distribution.length; ++i) {
            total += _distribution[i];
        }
        require(total == PRECISION, "Strategy: Distribution incorrect");
    }

    /// -----------------------------------------------------------
    /// External functions
    /// -----------------------------------------------------------

    /// @notice puts any available tokenX or tokenY to work
    /// @return amountX amount of token X added as liquidity
    /// @return amountY amount of token Y added as liquidity
    function earn()
    external
    onlyManager
    returns (uint256 amountX, uint256 amountY)
    {
        uint256 balanceX = tokenX.balanceOf(address(this));
        uint256 balanceY = tokenY.balanceOf(address(this));

        //gas saving check if there is idle funds in the contract
        require(
            balanceX > 1e3 || balanceY > 1e3,
            "Vault: Insufficient idle funds in strategy"
        );

        //require the amounts to be deposited into the correct bin distributions
        (amountX, amountY) = _calculateAmountsPerformSwap(
            deltaIds,
            balanceX,
            balanceY
        );

        //use the funds in the strategy to add liquidty.
        if (amountX > 0 || amountY > 0) {
            _addLiquidity(amountX, amountY, 0, 0);
        }
    }

    /// @notice entrypoint for the vault to remove liquidity from the strategy
    /// @param denominator proportion of liquidity to remove
    /// @return amountX amount of tokenX removed from liquidity
    /// @return amountY amount of tokenY removed from liquidity
    function removeLiquidity(uint256 denominator)
    external
    onlyOwner
    returns (uint256 amountX, uint256 amountY)  {
        (amountX, amountY) = _removeLiquidity(denominator);
    }

    /// @notice harvest the rewards from the strategy
    /// @return amountXReceived amount of tokenX received from harvest
    /// @return amountYReceived amount of tokenY received from harvest
    function harvest()
    external
    virtual
    returns (uint256 amountXReceived, uint256 amountYReceived)
    {
        (amountXReceived, amountYReceived) = _harvest();
    }

    //    /// @notice harvest the rewards from the strategy using custom fee receiver
    //    /// @param callFeeRecipient the address to be compensated for gas
    //    /// @return amountXReceived amount of tokenX received from harvest
    //    /// @return amountYReceived amount of tokenY received from harvest
    //    function harvest(
    //        address callFeeRecipient
    //    )
    //    external
    //    virtual
    //    returns (uint256 amountXReceived, uint256 amountYReceived)
    //    {
    //        (amountXReceived, amountYReceived) = _harvest(callFeeRecipient);
    //    }

    /// -----------------------------------------------------------
    /// View functions
    /// -----------------------------------------------------------

    /// @notice get the active bins that the strategy currently holds liquidity in.
    /// @return activeBinIds array of active binIds
    function getActiveBinIds()
    public
    view
    returns (uint256[] memory activeBinIds)
    {
        uint256 _userPositionNumber = strategyPositionNumber();
        //init the new holder array
        activeBinIds = new uint256[](_userPositionNumber);

        //loop over user position index and retrieve the bin ids
        for (uint256 i; i < _userPositionNumber; ++i) {
            uint256 userPosition = strategyPositionAtIndex(i);
            activeBinIds[i] = userPosition;
        }

        return (activeBinIds);
    }

    /// @notice Calculates the vault's total holdings of tokenX and tokenY - in
    /// other words, how much of each token the vault would hold if it withdrew
    /// all its liquidity from Trader Joe Dex V2.
    /// @return totalX managed by the strategy
    /// @return totalY managed by the strategy
    function getTotalAmounts()
    public
    view
    returns (uint256 totalX, uint256 totalY)
    {
        //add currently active tokens supplied as liquidity
        (totalX, totalY) = LiquidityAmounts.getAmountsOf(
            address(this),
            strategyActiveBins(),
            address(lbPair)
        );

        //add currently unused tokens
        totalX += getBalanceX();
        totalY += getBalanceY();
    }

    /// @notice checks if the deltaId's contain X liquidity
    /// @param _deltaIds to check
    /// @return hasXLiquidity if tokenX is required as liquidity by strategy
    function binHasXLiquidity(
        int256[] memory _deltaIds
    ) public pure returns (bool hasXLiquidity) {
        for (uint256 i; i < _deltaIds.length; i++) {
            if (_deltaIds[i] >= 0) {
                hasXLiquidity = true;
                break;
            }
        }
    }

    /// @notice checks if the deltaId's contain Y liquidity
    /// @param _deltaIds to check
    /// @return hasYLiquidity if tokenY is required as liquidity by strategy
    function binHasYLiquidity(
        int256[] memory _deltaIds
    ) public pure returns (bool hasYLiquidity) {
        for (uint256 i; i < _deltaIds.length; i++) {
            if (_deltaIds[i] <= 0) {
                hasYLiquidity = true;
                break;
            }
        }
    }

    /// @notice checks if there is rewards ready to be harvested from the pair
    /// @param _increasingBinIds strictly increasing binIds to check rewards in
    /// @return rewardsX amount of rewards available of tokenX
    /// @return rewardsY amount of rewards available of tokenY
    function rewardsAvailable(
        uint256[] memory _increasingBinIds
    ) external view returns (uint256 rewardsX, uint256 rewardsY) {
        require(_increasingBinIds.length > 0, "Strat: Supply valid ids");
        //pending fees requires strictly increasing ids (require sorting off chain)
        (rewardsX, rewardsY) = lbPair.pendingFees(
            address(this),
            _increasingBinIds
        );
    }

    /// @notice Balance of tokenX in strategy not used in any position.
    /// @return tokenXAmount amount of tokenX idle in the strat
    function getBalanceX() public view returns (uint256) {
        return tokenX.balanceOf(address(this));
    }

    /// @notice Balance of tokenY in strategy not used in any position.
    /// @return tokenYAmount amount of tokenY idle in the strat
    function getBalanceY() public view returns (uint256) {
        return tokenY.balanceOf(address(this));
    }

    /// -----------------------------------------------------------
    /// Manager / Owner functions
    /// -----------------------------------------------------------

    /// @notice called as part of strat migration.
    /// Sends all the available funds back to the vault.
    function retireStrat() external onlyOwner {
        //add currently active tokens supplied as liquidity
        (uint256 totalX, uint256 totalY) = LiquidityAmounts.getAmountsOf(
            address(this),
            strategyActiveBins(),
            address(lbPair)
        );

        _harvest();

        if (totalX > 0 || totalY > 0) {
            _removeLiquidity(PRECISION);
        }

        uint256 tokenXBal = tokenX.balanceOf(address(this));
        uint256 tokenYBal = tokenY.balanceOf(address(this));

        tokenX.transfer(msg.sender, tokenXBal);
        tokenY.transfer(msg.sender, tokenYBal);
    }

    /// @notice Rescues funds stuck
    /// @param _token address of the token to rescue.
    function inCaseTokensGetStuck(address _token) external onlyOwner {
        uint256 amount = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(msg.sender, amount);
    }

    /// @notice Update percent for swap
    /// @param _percentForSwap a new percent for swap
    function updatePercentForSwap(uint256 _percentForSwap) external onlyOwner {
        percentForSwap = _percentForSwap;
    }

    /// @notice pauses deposits and withdraws all funds from third party systems.
    function panic() external onlyOwner {
        pause();

        //add currently active tokens supplied as liquidity
        (uint256 totalX, uint256 totalY) = LiquidityAmounts.getAmountsOf(
            address(this),
            strategyActiveBins(),
            address(lbPair)
        );

        _harvest();
        //if there is liquidity remove it from dex and hold in strat
        if (totalX > 0 || totalY > 0) {
            _removeLiquidity(PRECISION);
        }
    }

    /// @notice pauses deposits and removes allowances
    function pause() public onlyOwner {
        _pause();
        _removeAllowances();
    }

    /// @notice allows deposits into third part systems
    function unpause() external onlyOwner {
        _unpause();
        _giveAllowances();
    }

    /// -----------------------------------------------------------
    /// Rebalance functions
    /// -----------------------------------------------------------

    /// @notice point of call to execute a rebalance of the strategy with the same params
    function executeRebalance() external onlyManager {
        executeRebalanceWith(
            deltaIds,
            distributionX,
            distributionY,
            idSlippage
        );
    }

    /// @notice point of call to execute a rebalance of the strategy with new params
    /// @param _deltaIds the distribution of liquidity around the active bin
    /// @param _distributionX the distribution of tokenX liquidity around the active bin
    /// @param _distributionY the distribution of tokenY liquidity around the active bin
    /// @param _idSlippage slippage of bins acceptable
    function executeRebalanceWith(
        int256[] memory _deltaIds,
        uint256[] memory _distributionX,
        uint256[] memory _distributionY,
        uint256 _idSlippage
    ) public onlyManager {
        //ensure that we are keeping to the 50 bin limit
        require(
            _deltaIds.length < 50,
            "Strategy: Bins shall be limited to < 50"
        );

        //check parameters are equal in length
        require(
            _deltaIds.length == _distributionX.length &&
            _distributionX.length == _distributionY.length,
            "Strategy: Unbalanced params"
        );

        //check the distributions are correct
        if (binHasXLiquidity(_deltaIds)) {
            _checkDistribution(_distributionX);
        }

        if (binHasYLiquidity(_deltaIds)) {
            _checkDistribution(_distributionY);
        }

        (uint256 amountXBefore, uint256 amountYBefore) = getTotalAmounts();

        //harvest any pending fees
        //this may save strategy from performing a swap of tokens
        _harvest();

        //remove any liquidity from joeRouter and clear active bins set
        if (strategyPositionNumber() > 0) {
            _removeLiquidity(PRECISION);
        }

        //rebalance the strategy params
        deltaIds = _deltaIds;
        distributionX = _distributionX;
        distributionY = _distributionY;
        idSlippage = _idSlippage;

        //calculate new amounts to deposit if existing deposits
        if (amountXBefore > 0 || amountYBefore > 0) {
            (uint256 amountX, uint256 amountY) = _calculateAmountsPerformSwap(
                _deltaIds,
                tokenX.balanceOf(address(this)),
                tokenY.balanceOf(address(this))
            );

            if (amountX > 0 || amountY > 0) {
                _addLiquidity(amountX, amountY, 0, 0);
            }
        }

    }

    /// @notice aligns the tokens to the required strategy deltas
    /// performs swaps on tokens not required for the bin offsets
    /// @param _deltaIds the delta ids of the current strategy
    /// @param _amountX the amount of tokenX in the strategy
    /// @param _amountY the amount of tokenY in the strategy
    /// @return amountX amount of tokenX to add as liquidity
    /// @return amountY amount of tokenY to add as liquidity
    function _calculateAmountsPerformSwap(
        int256[] memory _deltaIds,
        uint256 _amountX,
        uint256 _amountY
    ) internal returns (uint256 amountX, uint256 amountY) {
        //only token y liquidity
        if (!binHasXLiquidity(_deltaIds) && binHasYLiquidity(_deltaIds)) {
            //swap X for Y
            _swap(_amountX, true);
            amountY = tokenY.balanceOf(address(this));
            amountX = 0;
        }
        //only token x liquidity
        if (!binHasYLiquidity(_deltaIds) && binHasXLiquidity(_deltaIds)) {
            //swap Y for X
            _swap(_amountY, false);
            amountX = tokenX.balanceOf(address(this));
            amountY = 0;
        }
        //if has both token x and token y liquidity
        if (binHasYLiquidity(_deltaIds) && binHasXLiquidity(_deltaIds)) {
            //if bins move too much we need to swap for both

            bool swappedY = false;
            if (_amountX == 0) {
                _swap((percentForSwap * _amountY) / 100, false);

                swappedY = true;
            } else {
                (uint256 _amountXInY,) = ILBRouter(joeRouter).getSwapOut(lbPair, _amountY, false);
                if (_amountX < _amountXInY) {
                    (uint256 diffPercent) = getDiffPercent(_amountX, _amountXInY + _amountX);
                    if (diffPercent < percentForSwap) {
                        uint256 _remainingPercent = percentForSwap - diffPercent;
                        _swap((_remainingPercent * _amountY) / 100, false);

                        swappedY = true;
                    }
                }
            }

            if (_amountY == 0) {
                _swap((percentForSwap * _amountX) / 100, true);
            } else if (!swappedY) {
                (uint256 _amountYInX,) = ILBRouter(joeRouter).getSwapOut(lbPair, _amountX, true);
                if (_amountY < _amountYInX) {
                    (uint256 _diffPercent) = getDiffPercent(_amountY, _amountYInX + _amountY);
                    if (_diffPercent < percentForSwap) {
                        uint256 _remainingPercent = percentForSwap - _diffPercent;
                        _swap((_remainingPercent * _amountX) / 100, true);
                    }
                }
            }

            //set the final amounts for deposits
            amountX = tokenX.balanceOf(address(this));
            amountY = tokenY.balanceOf(address(this));
        }
    }

    function getDiffPercent(uint256 numerator, uint256 denominator) public pure returns (uint256 remainder) {
        uint256 factor = 10 ** 2;
        bool rounding = 2 * ((numerator * factor) % denominator) >= denominator;
        remainder = (numerator * factor / denominator) % factor;
        if (rounding) {
            remainder += 1;
        }
    }

    //    /// @notice Returns whether this contract implements the interface defined by
    //    /// `interfaceId` (true) or not (false)
    //    /// @param _interfaceId The interface identifier
    //    /// @return Whether the interface is supported (true) or not (false)
    //    function supportsInterface(bytes4 _interfaceId) public pure returns (bool) {
    //        return
    //        _interfaceId == type(ILBToken).interfaceId ||
    //        _interfaceId == type(IERC165).interfaceId;
    //    }
}
