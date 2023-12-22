// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "./SafeERC20.sol";
import "./EnumerableSet.sol";

import "./StratManager.sol";
import "./FeeManager.sol";
import "./ILBStrategy.sol";

import "./ILBToken.sol";
import "./ILBPair.sol";
import "./ILBRouter.sol";

import "./LiquidityAmounts.sol";
import "./Uint256x256Math.sol";
import "./BinHelper.sol";

/// @title StrategyTJLiquidityBookLB V2.1
/// @author SteakHut Finance
/// @notice used in conjunction with a vault to manage TraderJoe Liquidity Book Positions (V2.1 Support Only)
/// @notice rewards are harvested and sent back to the vault for distribution
contract StrategyTJLiquidityBookLB is StratManager, FeeManager {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.UintSet;
    using Uint256x256Math for uint256;
    using BinHelper for uint256;

    uint256 constant PRECISION = 1e18;

    //amount of liquidity to reserve in strategy
    uint256 public liquidityReserve = 98;

    uint256 public lastHarvest;

    /// @notice parameters which should not be changed after init
    IERC20 public tokenX;
    IERC20 public tokenY;
    ILBPair public lbPair;
    ILBToken public lbToken;
    uint16 public binStep;

    /// @notice parameters which may be changed by a strategist
    int256[] public deltaIds;
    uint256[] public distributionX;
    uint256[] public distributionY;
    uint256 public idSlippage;

    /// @notice parameters which may be changed by a owner
    uint256 public MAX_BINS = 50;

    /// @notice where strategy currently has a non-zero balance in bins
    EnumerableSet.UintSet private _activeBins;

    /// @notice mapping of current liquidities per bin (used for fee calculation)
    mapping(uint256 => uint256) public storedLiquidities;

    /// -----------------------------------------------------------
    /// Events
    /// -----------------------------------------------------------
    event CollectRewards(
        address user,
        uint256 lastHarvest,
        uint256 amountXBefore,
        uint256 amountYBefore,
        uint256 amountXAfter,
        uint256 amountYAfter
    );

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

    event UpdateMaxBins(uint256 maxBins);
    event UpdateLiquidityReserve(uint256 liquidityReserve);

    /// -----------------------------------------------------------
    /// Constructor
    /// -----------------------------------------------------------

    constructor(
        address _joeRouter,
        address _keeper,
        address _strategist,
        address _feeRecipient,
        address _vault,
        ILBStrategy.StrategyParameters memory _strategyParams
    ) StratManager(_keeper, _strategist, _joeRouter, _vault, _feeRecipient) {
        //require strategy to use < MAX_BINS bins due to gas limits
        require(
            _strategyParams.deltaIds.length < MAX_BINS,
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
    /// @notice helps to ensure that we wont exceed the MAX_BINS bin limit in single call
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
        uint256 activeId = lbPair.getActiveId();

        //check bin lengths are less than MAX_BINS bins due to block limit
        //further liquidity cannot be added until rebalanced
        require(
            checkProposedBinLength(deltaIds, activeId) < MAX_BINS,
            "Strategy: Requires Rebalance"
        );

        //set the required liquidity parameters
        ILBRouter.LiquidityParameters memory liquidityParameters = ILBRouter
            .LiquidityParameters(
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
                address(this),
                block.timestamp
            );

        //add the required liquidity into the pair
        (, , , , depositIds, liquidityMinted) = ILBRouter(joeRouter)
            .addLiquidity(liquidityParameters);

        //sum the total amount of liquidity minted
        uint256 liquidtyMintedHolder;
        for (uint256 i; i < liquidityMinted.length; i++) {
            liquidtyMintedHolder += liquidityMinted[i];
            //add the ID's to the user set
            _activeBins.add(depositIds[i]);
        }

        require(
            _activeBins.length() < MAX_BINS,
            "LBStrategy: Too many bins after add; manager check bin slippage and call rebalance"
        );

        //update the liquidites mapping to be current
        _updateLiquidities();

        //emit an event
        emit AddLiquidity(msg.sender, amountX, amountY, liquidtyMintedHolder);
    }

    /// @notice performs the removal of liquidity from the pair and keeps tokens in strategy
    /// does not take the fee, this is only handled when user withdraws or manually
    /// @param denominator the ownership stake to remove
    /// @notice PRECISION is full amount i.e all liquidity to be removed
    /// @return amountX the amount of liquidity removed as tokenX
    /// @return amountY the amount of liquidity removed as tokenY
    function _removeLiquidity(
        uint256 denominator
    ) internal returns (uint256 amountX, uint256 amountY) {
        uint256[] memory activeBinIds = strategyActiveBins();
        uint256[] memory amounts = new uint256[](activeBinIds.length);

        // To figure out amountXMin and amountYMin, we calculate how much X and Y underlying we have as liquidity
        for (uint256 i; i < activeBinIds.length; i++) {
            //amount of LBToken in each active bin
            uint256 LBTokenAmount = (PRECISION *
                lbToken.balanceOf(address(this), activeBinIds[i])) /
                (denominator);

            amounts[i] = LBTokenAmount;
        }

        //remove the liquidity required
        (amountX, amountY) = ILBRouter(payable(joeRouter)).removeLiquidity(
            tokenX,
            tokenY,
            binStep,
            0,
            0,
            activeBinIds,
            amounts,
            address(this),
            block.timestamp
        );

        //remove the ids from the userSet; this needs to occur if we are withdrawing all liquidity
        //or if we are rebalancing; not each time liquidity is withdrawn
        if (denominator == PRECISION) {
            for (uint256 i; i < activeBinIds.length; i++) {
                uint256 _id = activeBinIds[i];
                _activeBins.remove(_id);

                //we need to remove all the liqudidity from the mapping
                storedLiquidities[activeBinIds[i]] = 0;
            }
        } else {
            //active bins will be valid
            //we need to update the withdrawn liqudidity from the mapping
            _updateLiquidities();
        }

        //emit event
        emit RemoveLiquidity(msg.sender, amountX, amountY);
    }

    /// @notice updates the current liquidites mapping
    function _updateLiquidities() internal {
        uint256[] memory activeBinIds = strategyActiveBins();
        //get a snapshot of the most recent liquidities
        (, , uint256[] memory liquidities) = LiquidityAmounts
            .getAmountsAndLiquiditiesOf(
                address(this),
                activeBinIds,
                address(lbPair)
            );
        //iterate and add the most current liquidities to the mapping
        for (uint256 i; i < liquidities.length; ++i) {
            //update the mapping
            storedLiquidities[activeBinIds[i]] = liquidities[i];
        }
    }

    /// @notice gives the allowances required for this strategy
    function _giveAllowances() internal {
        uint256 MAX_INT = 2 ** 256 - 1;

        tokenX.safeApprove(joeRouter, uint256(MAX_INT));
        tokenY.safeApprove(joeRouter, uint256(MAX_INT));

        tokenX.safeApprove(vault, uint256(MAX_INT));
        tokenY.safeApprove(vault, uint256(MAX_INT));

        //provide required lb token approvals
        lbToken.approveForAll(joeRouter, true);
    }

    /// @notice remove allowances for this strategy
    function _removeAllowances() internal {
        tokenX.safeApprove(joeRouter, 0);
        tokenY.safeApprove(joeRouter, 0);

        tokenX.safeApprove(vault, 0);
        tokenY.safeApprove(vault, 0);

        //revoke required lb token approvals
        lbToken.approveForAll(joeRouter, false);
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

        ILBRouter.Version[] memory versions = new ILBRouter.Version[](1);
        versions[0] = ILBRouter.Version.V2_1; // the version of the Dex to perform the swap on

        ILBRouter.Path memory path; // instanciate and populate the path to perform the swap.
        path.pairBinSteps = pairBinSteps;
        path.versions = versions;
        path.tokenPath = tokenPath;

        //perform the swapping of tokens
        amountOutReal = ILBRouter(joeRouter).swapExactTokensForTokens(
            amountIn,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    /// @notice collects any availiable rewards from the pair and charges fees
    /// @return feesX tokenX amount received
    /// @return feesY tokenY amount received
    function _collectRewards() internal returns (uint256 feesX, uint256 feesY) {
        //get the current totals of tokens in the strategy (active and not active)
        (uint256 amountX, uint256 amountY) = getTotalAmounts();

        uint256[] memory activeBinIds = strategyActiveBins();

        //get a snapshot of the most recent liquidities
        (
            uint256[] memory amountsX,
            uint256[] memory amountsY,
            uint256[] memory liquidities
        ) = LiquidityAmounts.getAmountsAndLiquiditiesOf(
                address(this),
                activeBinIds,
                address(lbPair)
            );

        //holder to store fee growth inside
        uint256[] memory feeGrowthInside = new uint256[](liquidities.length);

        //loop over and calculate applicable fees.
        for (uint256 i; i < liquidities.length; ++i) {
            uint256 _id = activeBinIds[i];
            uint256 bal = lbToken.balanceOf(address(this), _id);

            uint256 _feesL;

            //if the current liquidty > stored liquidty, there is fee growth inside the bin
            //check for overflow
            if (liquidities[i] > storedLiquidities[_id]) {
                _feesL = liquidities[i] - storedLiquidities[_id];
            } else {
                _feesL = 0;
            }

            uint256 _feesX = _feesL.mulDivRoundDown(
                amountsX[i],
                liquidities[i]
            );
            uint256 _feesY = _feesL.mulDivRoundDown(
                amountsY[i],
                liquidities[i]
            );

            feesX += _feesX;
            feesY += _feesY;

            //the amount of tokens attributable to the _feeL gained.
            uint256 _amount = _feesL.mulDivRoundDown(bal, liquidities[i]);

            feeGrowthInside[i] = performanceFee.mulDivRoundDown(
                _amount,
                MAX_FEE
            );
        }

        //if fees have been collected send protocols share to helper
        //check for zero below
        if (feesX > 0 || feesY > 0) {
            //distribute the rewards back to the vault for distribution
            //it is then the vaults responsibility to convert the fee's back and distribute
            lbToken.batchTransferFrom(
                address(this),
                address(vault),
                activeBinIds,
                feeGrowthInside
            );
        }

        //update the current liquidities after rewards have been trasnferred to vault.
        _updateLiquidities();

        //emit event fee's collected
        emit CollectRewards(
            address(0),
            lastHarvest,
            amountX - feesX,
            amountY - feesY,
            amountX,
            amountY
        );
    }

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

    /// @notice harvests the earnings and takes a performance fee
    function _harvest()
        internal
        returns (uint256 amountXReceived, uint256 amountYReceived)
    {
        //collects pending rewards
        (amountXReceived, amountYReceived) = _collectRewards();

        lastHarvest = block.timestamp;
    }

    /// -----------------------------------------------------------
    /// External functions
    /// -----------------------------------------------------------

    /// @notice harvest the rewards from the strategy using custom fee receiver
    /// @return amountXReceived amount of tokenX received from harvest
    /// @return amountYReceived amount of tokenY received from harvest
    function harvest()
        external
        virtual
        returns (uint256 amountXReceived, uint256 amountYReceived)
    {
        (amountXReceived, amountYReceived) = _harvest();
    }

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

        //require the amounts to be deposited into the correct bin distributions
        (amountX, amountY) = _calculateAmountsPerformSwap(
            deltaIds,
            balanceX,
            balanceY
        );

        //use the funds in the strategy to add liquidty.
        if (amountX > 0 || amountY > 0) {
            (uint256 _amountX, uint256 _amountY) = computeReserveAmounts(
                amountX,
                amountY
            );
            //add the required liquidity
            _addLiquidity(_amountX, _amountY, 0, 0);
        }
    }

    /// @notice entrypoint for the vault to remove liquidity from the strategy
    /// @param denominator proportion of liquidity to remove
    /// @return amountX amount of tokenX removed from liquidity
    /// @return amountY amount of tokenY removed from liquidity
    function removeLiquidity(
        uint256 denominator
    ) external returns (uint256 amountX, uint256 amountY) {
        require(msg.sender == vault, "Strategy: !vault");

        //harvest any pending rewards prior to removing liquidity
        _collectRewards();

        (amountX, amountY) = _removeLiquidity(denominator);
    }

    /// -----------------------------------------------------------
    /// View functions
    /// -----------------------------------------------------------

    /// @notice ensure to always keep a reserve of tokens in contract
    /// @return amountX amount of tokenX to add as liquidity
    /// @return amountY amount of tokenX to add as liquidity
    function computeReserveAmounts(
        uint256 _amountX,
        uint256 _amountY
    ) internal view returns (uint256 amountX, uint256 amountY) {
        amountX = _amountX.mulDivRoundDown(liquidityReserve, 100);
        amountY = _amountY.mulDivRoundDown(liquidityReserve, 100);
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

    /// @notice entrypoint for owner to remove liquidity from protocol and store in strategy (ignores rewards)
    /// @param denominator proportion of liquidity to remove
    /// @return amountX amount of tokenX removed from liquidity
    /// @return amountY amount of tokenY removed from liquidity
    function removeLiquidityIgnoreRewards(
        uint256 denominator
    ) external onlyOwner returns (uint256 amountX, uint256 amountY) {
        (amountX, amountY) = _removeLiquidity(denominator);
    }

    /// @notice called as part of strat migration.
    /// Sends all the available funds back to the vault.
    function retireStrat() external {
        require(msg.sender == vault, "!vault");

        //add currently active tokens supplied as liquidity
        (uint256 totalX, uint256 totalY) = LiquidityAmounts.getAmountsOf(
            address(this),
            strategyActiveBins(),
            address(lbPair)
        );

        if (totalX > 0 || totalY > 0) {
            _removeLiquidity(PRECISION);
        }

        uint256 tokenXBal = tokenX.balanceOf(address(this));
        uint256 tokenYBal = tokenY.balanceOf(address(this));

        tokenX.transfer(vault, tokenXBal);
        tokenY.transfer(vault, tokenYBal);
    }

    /// @notice pauses deposits and withdraws all funds from third party systems.
    function panic() external onlyOwner {
        pause();

        //check currently active tokens supplied as liquidity
        (uint256 totalX, uint256 totalY) = LiquidityAmounts.getAmountsOf(
            address(this),
            strategyActiveBins(),
            address(lbPair)
        );

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

    /// @notice allows deposits into third party systems
    function unpause() external onlyOwner {
        _unpause();
        _giveAllowances();
    }

    /// @notice allows to update the max bins amount
    function updateMaxBins(uint256 maxBins) external onlyOwner {
        require(maxBins > 0, "maxBins shall be greater than 0");
        MAX_BINS = maxBins;

        emit UpdateMaxBins(maxBins);
    }

    /// @notice allows to update the liquidity reserve amount
    function updateLiquidityReserve(
        uint256 _liquidityReserve
    ) external onlyOwner {
        require(
            _liquidityReserve < 100,
            "LBStrategy: liquidityReserve shall be less than 100"
        );
        liquidityReserve = _liquidityReserve;

        emit UpdateLiquidityReserve(_liquidityReserve);
    }

    /// -----------------------------------------------------------
    /// Rebalance functions
    /// -----------------------------------------------------------

    /// @notice point of call to execute a rebalance of the strategy with the same params
    /// @return amountX total amountX supplied after the rebalance
    /// @return amountY total amountY supplied after the rebalance
    function executeRebalance()
        external
        onlyManager
        returns (uint256 amountX, uint256 amountY)
    {
        (amountX, amountY) = executeRebalance(
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
    /// @return amountX total amountX supplied after the rebalance
    /// @return amountY total amountY supplied after the rebalance
    function executeRebalance(
        int256[] memory _deltaIds,
        uint256[] memory _distributionX,
        uint256[] memory _distributionY,
        uint256 _idSlippage
    ) public onlyManager returns (uint256 amountX, uint256 amountY) {
        //ensure that we are keeping to the MAX_BINS bin limit
        require(
            _deltaIds.length < MAX_BINS,
            "Strategy: Bins shall be limited to <MAX_BINS"
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

        //harvest any pending fees
        //we should harvest pending rewards as part of keepers checks

        (uint256 amountXBefore, uint256 amountYBefore) = getTotalAmounts();

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
            (amountX, amountY) = _calculateAmountsPerformSwap(
                _deltaIds,
                tokenX.balanceOf(address(this)),
                tokenY.balanceOf(address(this))
            );
        }

        //only add liquidity if strategy has funds
        if (amountX > 0 || amountY > 0) {
            (uint256 _amountX, uint256 _amountY) = computeReserveAmounts(
                amountX,
                amountY
            );
            _addLiquidity(_amountX, _amountY, 0, 0);
        }

        (amountX, amountY) = getTotalAmounts();

        //emit event
        emit Rebalance(amountXBefore, amountYBefore, amountX, amountY);
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
            //we want to minimise the swap amounts limit to 1%
            //used to seed bins with a minimal amount of liquidity to reduce swap fee and slippage
            if (_amountX == 0) {
                //swap y for x (minimise amount, only to seed liquidity)
                _swap((1 * _amountY) / 100, false);
            }

            if (_amountY == 0) {
                //swap x for y (minimise amount, only to seed liquidity)
                _swap((1 * _amountX) / 100, true);
            }

            //set the final amounts for deposits
            amountX = tokenX.balanceOf(address(this));
            amountY = tokenY.balanceOf(address(this));
        }
    }
}

/// -----------------------------------------------------------
/// END STEAKHUT-LIQUIDITY 2023
/// -----------------------------------------------------------

