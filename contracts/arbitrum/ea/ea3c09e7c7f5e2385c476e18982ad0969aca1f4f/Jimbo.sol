// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {SafeTransferLib} from "./SafeTransferLib.sol";
import {ReentrancyGuard} from "./libraries_ReentrancyGuard.sol";
import {IERC20} from "./IERC20.sol";
import {Owned} from "./Owned.sol";
import {FixedPointMathLib} from "./FixedPointMathLib.sol";
import {JimboStaking} from "./JimboStaking.sol";
import {ERC20} from "./ERC20.sol";

import {PriceHelper} from "./PriceHelper.sol";
import {ILBFactory} from "./ILBFactory.sol";
import {ILBRouter} from "./ILBRouter.sol";
import {ILBToken} from "./ILBToken.sol";
import {ILBPair} from "./ILBPair.sol";

import {IUniswapV2Pair} from "./IUniswapV2Pair.sol";
import {IUniswapV3Pool} from "./IUniswapV3Pool.sol";

import {LBRouter} from "./LBRouter.sol";
import {LBPair} from "./LBPair.sol";

contract Jimbo is ERC20, Owned, ReentrancyGuard {
    using SafeTransferLib for address payable;
    using PriceHelper for uint256;

    error Initialized();
    error TriggerIntact();
    error AnchorIntact();
    error CantResetYet();
    error CantRecycleYet();

    uint256 internal constant PRECISION = 1e18;
    uint256 public constant INITIAL_TOTAL_SUPPLY = 69_420_000 * 1e18;

    // For jimbo's retirement
    address public jimbo;
    address public vault; // staking contract

    LBRouter public joeRouter;
    ILBFactory public joeFactory;
    LBPair public pair;
    IERC20 public immutable native; // weth

    bool public isRebalancing; // prevents taxing when adding/removing liq
    bool public initialized;

    // JOE LIQ
    uint16 public binStep; // bin steps
    uint24 public maxBin; // this is the last bin where we have liq

    // floor bin where liq sits
    uint24 public floorBin;

    uint256 public lastRecordedActiveBin; // recorded bin to know where rebalances occur.
    uint256 public anchorBin; // bin before floor bin

    uint256 public burnFee = 25; // 2.5%
    uint256 public stakeFee = 15; // 1.5%
    uint256 public jimboFee = 5; // 0.5%

    constructor(address native_) ERC20("JIMBO", "JIMBO", 18) Owned(msg.sender) {
        native = IERC20(native_);
    }

    /// -----------------------------------------------------------------------
    /// INITIALIZATION - init pools and bins
    /// -----------------------------------------------------------------------

    function initialize(
        address _jimbo,
        address mainPair, // main eth pair
        address _joeRouter,
        int256[] memory deltaIds,
        uint256[] memory distributionX,
        uint256[] memory distributionY,
        address _vault
    ) external payable onlyOwner {
        if (initialized) revert Initialized();

        isRebalancing = true;

        jimbo = _jimbo;
        vault = _vault;
        pair = LBPair(mainPair);
        joeRouter = LBRouter(payable(_joeRouter));
        joeFactory = joeRouter.getFactory();
        binStep = pair.getBinStep();

        // Approvals
        allowance[address(this)][address(joeRouter)] = type(uint256).max;
        native.approve(address(joeRouter), type(uint256).max);

        ILBToken(address(pair)).approveForAll(address(joeRouter), true);
        ILBToken(address(pair)).approveForAll(address(pair), true);

        uint24 activeBinId = getActiveBinId();

        lastRecordedActiveBin = activeBinId;
        maxBin = activeBinId + 50;
        floorBin = activeBinId;
        anchorBin = activeBinId;

        _mint(address(this), INITIAL_TOTAL_SUPPLY);

        _addLiquidity(
            deltaIds,
            distributionX,
            distributionY,
            INITIAL_TOTAL_SUPPLY,
            0,
            activeBinId
        );

        isRebalancing = false;
        initialized = true;
    }

    /// -----------------------------------------------------------------------
    /// REBALANCES - Scenario 1 (trigger bin rebal),2 (reset), 3. (recyle)
    /// -----------------------------------------------------------------------

    // scenario 1, the active bin moves passed trigger bin
    // 1. set up anchors and floor bin
    // 2. reset token bins so price can increase
    // This is a beefy func, thank you L2s.
    function triggerBinRebalance() public nonReentrant {
        if (!canRebalance()) revert TriggerIntact();

        isRebalancing = true;
        uint24 activeBinId = getActiveBinId();

        // when the active bin is the maxBin, we need to remove liquidity
        if (activeBinId == maxBin) {
            _maxBinRemoveLiq();
        } else {
            // remove all LP from ETH and JIMBO side
            _removeETHliq();
            _removeJimboLiquidityForTriggerRebal();
        }

        uint256 totalJimboInPool = balanceOf[address(this)];
        uint256 totalEthInContract = native.balanceOf(address(this));

        // circulating supply is all the supply that isn't owned by the protocol
        uint256 totalCirculatingJimbo = totalSupply -
            totalJimboInPool -
            balanceOf[address(0)];

        uint24 floorLiquidityBin = calculateFloorLiqBin(
            totalEthInContract,
            totalCirculatingJimbo
        );

        // trader joe works off deltas from 0
        int256 deltaForMainLiq = -(int24(activeBinId) -
            int(int24(floorLiquidityBin)));

        // set values
        floorBin = floorLiquidityBin;
        lastRecordedActiveBin = activeBinId;

        // set the new 51 token bins
        _rebalanceTokenLiquidityBinsForTriggerRebalance(totalJimboInPool);

        // if we don't have enough room to put in 5 anchors between floor and active bin
        if (activeBinId - floorLiquidityBin < 6) {
            int256[] memory deltaIds = new int256[](2);
            uint256[] memory distributionX = new uint256[](2);
            uint256[] memory distributionY = new uint256[](2);

            // give floor 90% liq
            deltaIds[0] = deltaForMainLiq;
            distributionX[0] = 0;
            distributionY[0] = (PRECISION * 90) / 100;

            // if floor bin is right under active bin, throw rest in active bin
            if (deltaForMainLiq == -1) {
                deltaIds[1] = 0;
                distributionY[1] = (PRECISION * 10) / 100;
            }

            // the anchor is right under active
            anchorBin = activeBinId - 1;

            _addLiquidity(
                deltaIds,
                distributionX,
                distributionY,
                0,
                native.balanceOf(address(this)),
                activeBinId
            );
        } else {
            // we set up 5 anchors + floor bin
            int256[] memory deltaIds = new int256[](6);
            uint256[] memory distributionX = new uint256[](6);
            uint256[] memory distributionY = new uint256[](6);

            // floor bin
            deltaIds[0] = deltaForMainLiq;
            distributionX[0] = 0;
            distributionY[0] = (PRECISION * 90) / 100;

            // if we were in the maxbin, active bin is still max bin so we
            // need to give it liquidity. Thus the first anchor is the active bin.
            if (activeBinId == maxBin) {
                distributionY[1] = ((PRECISION * 10 * 10) / 10000);
                deltaIds[1] = 0;

                //a - 2
                distributionY[2] = ((PRECISION * 10 * 15) / 10000);
                deltaIds[2] = -1;

                //a - 3
                distributionY[3] = ((PRECISION * 10 * 20) / 10000);
                deltaIds[3] = -2;

                //a - 4
                distributionY[4] = ((PRECISION * 10 * 25) / 10000);
                deltaIds[4] = -3;

                // floor bin
                distributionY[5] = ((PRECISION * 10 * 30) / 10000);
                deltaIds[5] = -4;

                anchorBin = activeBinId - 4;
            } else {
                // if we were not in max bin, just set up 5 anchors below active
                //a - 1
                distributionY[1] = ((PRECISION * 10 * 10) / 10000);
                deltaIds[1] = -1;

                //a - 2
                distributionY[2] = ((PRECISION * 10 * 15) / 10000);
                deltaIds[2] = -2;

                //a - 3
                distributionY[3] = ((PRECISION * 10 * 20) / 10000);
                deltaIds[3] = -3;

                //a - 4
                distributionY[4] = ((PRECISION * 10 * 25) / 10000);
                deltaIds[4] = -4;

                // floor bin
                distributionY[5] = ((PRECISION * 10 * 30) / 10000);
                deltaIds[5] = -5;

                anchorBin = activeBinId - 5;
            }

            _addLiquidity(
                deltaIds,
                distributionX,
                distributionY,
                0,
                totalEthInContract,
                activeBinId
            );
        }

        unchecked {
            maxBin = uint24(activeBinId + 51);
        }
        isRebalancing = false;
    }

    // scenario 2:
    // when a sell causes active bin to move below anchor, we reset the entire protocol.
    // token bins will move right next to the current active been and be redistributed.
    function triggerReset() public {
        if (!canReset()) revert CantResetYet();

        isRebalancing = true;

        // remove all token LP
        _removeJimboLiquidity();

        uint256 tokenXbalance = balanceOf[address(this)];
        uint256 tokenYbalance = native.balanceOf(address(this));

        // 51 token bins
        int256[] memory deltaIds = new int256[](51);
        uint256[] memory distributionX = new uint256[](51);
        uint256[] memory distributionY = new uint256[](51);

        // distribute 50% of tokens to 50 bins
        for (uint256 i = 0; i < 50; i++) {
            // we need to start at active + 1 because we don't want to
            // put liquidity in the floor bin in the case where the floor bin is the active bin
            deltaIds[i] = int256(i + 1);
            distributionX[i] = (PRECISION * 1) / 100;
        }

        // distribute 50% of tokens to last bin
        deltaIds[50] = 51;
        distributionX[50] = (PRECISION * 50) / 100;

        // reset values
        lastRecordedActiveBin = getActiveBinId();

        // set the anchor bin to the floor bin so that reset() cannot be triggered again until
        // we successfully rebalance the ETH liquidity again.
        anchorBin = floorBin;

        // decrement because we are starting 1 bin past the active bin
        maxBin = uint24(lastRecordedActiveBin + 51);

        _addLiquidity(
            deltaIds,
            distributionX,
            distributionY,
            tokenXbalance,
            0,
            uint24(lastRecordedActiveBin) + 1
        );

        isRebalancing = false;
    }

    // scenario 3
    // this func will be called if were already in floor bin and reset has happened.
    // additional tokens sold will be taken out of supply for fast price movement out of
    // the floor. The tokens will be redistributed back on trigger rebalance.
    function triggerRecycle() public {
        if (!canRecycle()) revert CantRecycleYet();

        isRebalancing = true;

        // remove floor bin lp
        _removeFloorBinLiquidity();

        uint256 tokenXbalance = balanceOf[address(this)];
        uint256 tokenYbalance = native.balanceOf(address(this));

        uint24 activeBinId = getActiveBinId();

        // only give floor bin ETH and keep tokens in contract
        int256[] memory deltaIds = new int256[](1);
        uint256[] memory distributionX = new uint256[](1);
        uint256[] memory distributionY = new uint256[](1);

        deltaIds[0] = 0;
        distributionX[0] = 0;

        // i know 100/100 == 1 but this is for clarity
        distributionY[0] = (PRECISION * 100) / 100;

        _addLiquidity(
            deltaIds,
            distributionX,
            distributionY,
            tokenXbalance,
            tokenYbalance,
            activeBinId
        );

        isRebalancing = false;
    }

    /// -----------------------------------------------------------------------
    /// TAX LOGIC
    /// -----------------------------------------------------------------------

    function chargeTax(
        address from,
        address to,
        uint256 amount
    ) internal returns (uint256 _amount) {
        _amount = amount;

        if (!isRebalancing) {
            uint256 sendToVault;
            uint24 activeBinId = getActiveBinId();
            // buy tax
            if (_isJoePool(from) || _isUniV3Pool(from) || _isUniV2Pair(from)) {
                uint256 devTax = _calculateFee(_amount, jimboFee);
                uint256 burn = _calculateFee(_amount, burnFee);
                sendToVault = _calculateFee(_amount, stakeFee);

                balanceOf[jimbo] += devTax;
                emit Transfer(from, jimbo, devTax);

                balanceOf[vault] += sendToVault;
                emit Transfer(from, vault, sendToVault);

                unchecked {
                    totalSupply -= burn;
                }
                emit Transfer(from, address(0), burn);

                _amount -= (devTax + sendToVault + burn);
            }

            // sell tax
            if (_isJoePool(to) || _isUniV3Pool(to) || _isUniV2Pair(to)) {
                if (activeBinId == floorBin) {
                    sendToVault = _calculateFee(_amount, (stakeFee + burnFee));
                    balanceOf[vault] += sendToVault;
                    emit Transfer(from, vault, sendToVault);

                    _amount -= sendToVault;
                } else {
                    uint256 devTax = _calculateFee(_amount, jimboFee);
                    uint256 burn = _calculateFee(_amount, burnFee);
                    sendToVault = _calculateFee(_amount, stakeFee);

                    balanceOf[jimbo] += devTax;
                    emit Transfer(from, jimbo, devTax);

                    balanceOf[vault] += sendToVault;
                    emit Transfer(from, vault, sendToVault);

                    unchecked {
                        totalSupply -= burn;
                    }
                    emit Transfer(from, address(0), burn);

                    _amount -= (devTax + sendToVault + burn);
                }
            }

            // reset tokens if the trades break anchor
            if (canReset()) {
                triggerReset();
            }

            // recycle once we're trading in floor bin
            if (canRecycle()) {
                triggerRecycle();
            }

            // Notify staking of new reward distro
            JimboStaking(vault).notifyRewardAmount(sendToVault);
        }
    }

    /// -----------------------------------------------------------------------
    /// HELPERS FOR BIN MATH AND LPs
    /// -----------------------------------------------------------------------

    // will set 50 bins + 1 max bin starting from active bin + 1
    // essentially moves the token price upwards as tokens are bought
    function _rebalanceTokenLiquidityBinsForTriggerRebalance(
        uint256 tokenXbalance
    ) internal {
        // 51 token bins
        int256[] memory deltaIds = new int256[](51);
        uint256[] memory distributionX = new uint256[](51);
        uint256[] memory distributionY = new uint256[](51);

        // distribute 50% of tokens to 50 bins
        for (uint256 i = 0; i < 50; i++) {
            // we need to start at active + 1
            deltaIds[i] = int256(i + 1);
            distributionX[i] = (PRECISION * 1) / 100;
        }

        // distribute 50% of tokens to last bin
        deltaIds[50] = 51;
        distributionX[50] = (PRECISION * 50) / 100;

        _addLiquidity(
            deltaIds,
            distributionX,
            distributionY,
            tokenXbalance,
            0,
            uint24(getActiveBinId()) + 1
        );
    }

    // removes all JIMBO liquidity specifically when resets are called.
    function _removeJimboLiquidity() internal {
        // only triggered when reset() is called
        // remove bin inclusive of the anchor, because anchor can never be the floor bin when reset() is triggered
        uint256 numberOfBinsToWithdraw = (maxBin - uint256(anchorBin)) + 1;

        // anchor is floor so no need to pull floor bin
        if (anchorBin == floorBin) {
            numberOfBinsToWithdraw--;
        }

        uint256[] memory amounts = new uint256[](numberOfBinsToWithdraw);
        uint256[] memory ids = new uint256[](numberOfBinsToWithdraw);

        for (uint256 i = 0; i < numberOfBinsToWithdraw; i++) {
            ids[i] = maxBin - i;
            amounts[i] = pair.balanceOf(address(this), maxBin - i);
        }

        pair.burn(address(this), address(this), ids, amounts);
    }

    // this is similar to the above function but removing these tokens require
    // slightly different logic due to off by 1 index errors
    function _maxBinRemoveLiq() internal {
        uint256 activeBinId = getActiveBinId();
        uint256 numberOfBinsToWithdraw = (activeBinId - anchorBin) + 1;

        if (anchorBin != floorBin) {
            numberOfBinsToWithdraw++;
        }

        uint256[] memory amounts = new uint256[](numberOfBinsToWithdraw);
        uint256[] memory ids = new uint256[](numberOfBinsToWithdraw);

        for (uint256 i = 0; i < numberOfBinsToWithdraw; i++) {
            ids[i] = anchorBin + i;
            amounts[i] = pair.balanceOf(address(this), anchorBin + i);
        }

        if (anchorBin != floorBin) {
            ids[numberOfBinsToWithdraw - 1] = floorBin;
            amounts[numberOfBinsToWithdraw - 1] = pair.balanceOf(
                address(this),
                floorBin
            );
        }

        pair.burn(address(this), address(this), ids, amounts);
    }

    // this is similar to the func that removes JIMBO liquidity but for trigger rebals
    // specifically cause it has slightly different indexing
    function _removeJimboLiquidityForTriggerRebal() internal {
        uint256 activeBinId = getActiveBinId();

        // not inclusive of the active bin
        uint256 numberOfBinsToWithdraw = (maxBin - activeBinId);

        if (numberOfBinsToWithdraw == 0) {
            return;
        }

        uint256[] memory amounts = new uint256[](numberOfBinsToWithdraw);
        uint256[] memory ids = new uint256[](numberOfBinsToWithdraw);

        for (uint256 i = 0; i < numberOfBinsToWithdraw; i++) {
            ids[i] = maxBin - i;
            amounts[i] = pair.balanceOf(address(this), maxBin - i);
        }

        pair.burn(address(this), address(this), ids, amounts);
    }

    // remove all eth LP
    function _removeETHliq() internal {
        // there will always be LP between anchor and active
        uint256 numberOfBinsToWithdraw = getActiveBinId() - anchorBin;

        // if we have a separate floor bin, get LP
        if (floorBin != anchorBin) {
            numberOfBinsToWithdraw++;
        }

        uint256[] memory amounts = new uint256[](numberOfBinsToWithdraw);
        uint256[] memory ids = new uint256[](numberOfBinsToWithdraw);

        for (uint256 i = 0; i < numberOfBinsToWithdraw; i++) {
            ids[i] = anchorBin + i;
            amounts[i] = pair.balanceOf(address(this), anchorBin + i);
        }

        if (floorBin != anchorBin) {
            ids[numberOfBinsToWithdraw - 1] = floorBin;
            amounts[numberOfBinsToWithdraw - 1] = pair.balanceOf(
                address(this),
                floorBin
            );
        }

        pair.burn(address(this), address(this), ids, amounts);
    }

    // remove LP only from floor bin
    function _removeFloorBinLiquidity() internal {
        uint256[] memory ids = new uint256[](1);
        uint256[] memory amounts = new uint256[](1);

        ids[0] = floorBin;
        amounts[0] = pair.balanceOf(address(this), floorBin);

        pair.burn(address(this), address(this), ids, amounts);
    }

    // generic add liq function
    function _addLiquidity(
        int256[] memory deltaIds,
        uint256[] memory distributionX,
        uint256[] memory distributionY,
        uint256 amountX,
        uint256 amountY,
        uint24 activeIdDesired
    ) internal {
        uint256 amountXmin = (amountX * 99) / 100; // We allow 1% amount slippage
        uint256 amountYmin = (amountY * 99) / 100; // We allow 1% amount slippage

        uint256 idSlippage = activeIdDesired - getActiveBinId();

        ILBRouter.LiquidityParameters memory liquidityParameters = ILBRouter
            .LiquidityParameters(
                IERC20(address(this)),
                native,
                binStep,
                amountX,
                amountY,
                amountXmin,
                amountYmin,
                activeIdDesired, //activeIdDesired
                idSlippage,
                deltaIds,
                distributionX,
                distributionY,
                address(this),
                address(this),
                block.timestamp
            );

        joeRouter.addLiquidity(liquidityParameters);
    }

    /// -----------------------------------------------------------------------
    /// OVVERIDES
    /// -----------------------------------------------------------------------

    function transfer(
        address to,
        uint256 amount
    ) public virtual override returns (bool) {
        balanceOf[msg.sender] -= amount;

        uint256 _amount = chargeTax(msg.sender, to, amount);

        unchecked {
            balanceOf[to] += _amount;
        }

        emit Transfer(msg.sender, to, _amount);

        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public virtual override returns (bool) {
        uint256 allowed = allowance[from][msg.sender]; // Saves gas for limited approvals.

        if (allowed != type(uint256).max)
            allowance[from][msg.sender] = allowed - amount;

        balanceOf[from] -= amount;

        uint256 _amount = chargeTax(msg.sender, to, amount);

        unchecked {
            balanceOf[to] += _amount;
        }

        emit Transfer(from, to, _amount);
        return true;
    }

    /// -----------------------------------------------------------------------
    /// MORE HELPERS AND VIEW FUNCS
    /// -----------------------------------------------------------------------

    function _calculateFee(
        uint256 amount,
        uint256 pct
    ) internal pure returns (uint256) {
        uint256 feePercentage = (PRECISION * pct) / 1000; // x pct
        return (amount * feePercentage) / PRECISION;
    }

    // trader joes getIdFromPrice is not accurate so
    // we have to find it ourselves by incrementing.
    // at most we increment 50 bins so no need for binary search. ty L2s.
    function calculateFloorLiqBin(
        uint256 totalEthInContract,
        uint256 totalCirculatingJimbo
    ) internal view returns (uint24) {
        uint256 newFloorPrice = getAverageTokenPrice(
            totalEthInContract,
            totalCirculatingJimbo
        );

        uint256 priceAtNextBin;
        uint24 newFloorBin = floorBin;
        uint24 activeBinId = getActiveBinId();

        for (
            newFloorBin = floorBin;
            newFloorBin < activeBinId - 1;
            newFloorBin++
        ) {
            priceAtNextBin = (pair.getPriceFromId(newFloorBin + 1))
                .convert128x128PriceToDecimal();
            if (priceAtNextBin > newFloorPrice) {
                break;
            }
        }

        return newFloorBin;
    }

    // eth backing per token
    function getAverageTokenPrice(
        uint256 totalETH,
        uint256 totalTokens
    ) public view returns (uint256) {
        return (totalETH * PRECISION) / (totalTokens);
    }

    function canRebalance() public view returns (bool) {
        return getActiveBinId() > lastRecordedActiveBin + 5;
    }

    function canReset() public view returns (bool) {
        return (getActiveBinId() < anchorBin);
    }

    function canRecycle() public view returns (bool) {
        return getActiveBinId() == floorBin;
    }

    function getActiveBinId() public view returns (uint24) {
        return pair.getActiveId();
    }

    function _isJoePool(address target) internal view returns (bool) {
        if (target.code.length == 0) return false;

        ILBPair pool = ILBPair(target);

        try pool.getTokenX() {} catch (bytes memory) {
            return false;
        }

        try pool.getTokenY() {} catch (bytes memory) {
            return false;
        }

        try pool.getBinStep() {} catch (bytes memory) {
            return false;
        }

        return true;
    }

    function _isUniV3Pool(address target) internal view returns (bool) {
        if (target.code.length == 0) return false;

        IUniswapV3Pool pool = IUniswapV3Pool(target);

        try pool.token0() {} catch (bytes memory) {
            return false;
        }

        try pool.token1() {} catch (bytes memory) {
            return false;
        }

        try pool.fee() {} catch (bytes memory) {
            return false;
        }

        return true;
    }

    function _isUniV2Pair(address target) internal view returns (bool) {
        if (target.code.length == 0) return false;

        IUniswapV2Pair uniPair = IUniswapV2Pair(target);

        try uniPair.token0() {} catch (bytes memory) {
            return false;
        }

        try uniPair.token1() {} catch (bytes memory) {
            return false;
        }

        try uniPair.kLast() {} catch (bytes memory) {
            return false;
        }

        return true;
    }

    // helper funcs for front end
    function binsUntilRebal() external view returns (uint256) {
        uint256 activeBinId = getActiveBinId();
        if (activeBinId > lastRecordedActiveBin + 5) {
            return type(uint256).max;
        }

        // need to blow 1 past the last acive bin
        if ((lastRecordedActiveBin + 6) - activeBinId > 0) {
            return (lastRecordedActiveBin + 6) - activeBinId;
        } else {
            return 0;
        }
    }

    function getFloorLiqBin() external view returns (uint256, uint256) {
        return pair.getBin(floorBin);
    }

    function getFloorPrice() external view returns (uint256) {
        return (pair.getPriceFromId(floorBin)).convert128x128PriceToDecimal();
    }
}

