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

import {console} from "./console.sol";

contract Jimbo is ERC20, Owned, ReentrancyGuard {
    using SafeTransferLib for address payable;
    using PriceHelper for uint256;

    error Initialized();
    error TriggerIntact();
    error AnchorIntact();

    uint256 internal constant PRECISION = 1e18;
    uint256 public constant INITIAL_TOTAL_SUPPLY = 69_420_000 * 1e18;

    // For jimbo's retirement
    address public jimbo;

    LBRouter public joeRouter;
    ILBFactory public joeFactory;
    LBPair public pair;
    address public vault; // staking contract
    IERC20 public immutable native; // weth

    bool public isRebalancing; // prevents taxing when adding/removing liq
    bool public initialized;

    // JOE LIQ
    uint16 public binStep; // bin steps
    uint24 public maxBin; // this is the last bin where we have liq

    // floor bin where liq sits
    uint24 public floorBin;

    uint256 public xPerBin; // xToken amount per bin
    uint256 public lastRecordedActiveBin; // recorded bin to know where rebalances occur.
    uint256 public anchorBin; // bin before floor bin

    // amount of protocol tokens in last bin
    uint256 public maxBinAmt;

    uint256 public burnFee = 25; // 2.5%
    uint256 public stakeFee = 15; // 1.5%
    uint256 public jimboFee = 5; // 0.5%

    constructor(address native_) ERC20("PUMP", "PUMP", 18) Owned(msg.sender) {
        native = IERC20(native_);
    }

    // ==== Initialize ====

    function initialize(
        address _jimbo,
        address mainPair, // main eth pair
        address _joeRouter,
        int256[] memory deltaIds,
        uint256[] memory distributionX,
        uint256[] memory distributionY,
        address _vault,
        uint256 _xPerBin
    ) external payable onlyOwner {
        if (initialized) revert Initialized();
        isRebalancing = true;

        jimbo = _jimbo;
        vault = _vault;
        pair = LBPair(mainPair);
        joeRouter = LBRouter(payable(_joeRouter));
        joeFactory = joeRouter.getFactory();

        binStep = pair.getBinStep();
        xPerBin = _xPerBin;
        maxBinAmt = _xPerBin * 50;

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

    // ==== Rebalance ====

    // scenario 1, the active bin moves passed trigger bin
    function triggerBinRebalance() public nonReentrant {
        isRebalancing = true;

        uint24 activeBinId = getActiveBinId();

        if (!canRebalance()) revert TriggerIntact();

        // remove eth side liq
        _removeETHliq();

        uint256 totalEthInContract = native.balanceOf(address(this));

        // last bin has 50% of tokens, so we do maxBin - 1 * xPerBin, and then * 2
        uint256 totalJimboInPool = ((maxBin - (activeBinId + 1)) * xPerBin) + maxBinAmt;
        uint256 protocolOwnedJimbo = totalJimboInPool + balanceOf[address(this)];
        uint256 totalCirculatingJimbo = totalSupply - protocolOwnedJimbo - balanceOf[address(0)];

        uint24 floorLiquidityBin = calculateFloorLiqBin(
            totalEthInContract,
            totalCirculatingJimbo
        );

        int256 deltaForMainLiq = -(int24(activeBinId) -
            int(int24(floorLiquidityBin)));

        // set values
        floorBin = floorLiquidityBin;
        lastRecordedActiveBin = activeBinId;

        // if theres not enough room for 5 anchors, we just give 1 anchor below active bin
        // and leave the rest of array empty

        if (activeBinId - floorLiquidityBin < 5) {
            int256[] memory deltaIds = new int256[](2);
            uint256[] memory distributionX = new uint256[](2);
            uint256[] memory distributionY = new uint256[](2);

            deltaIds[0] = deltaForMainLiq;
            distributionX[0] = 0;
            distributionY[0] = (PRECISION * 90) / 100;

            // if floor bin is right under active bin, throw rest in active bin
            if (deltaForMainLiq == -1) {
                deltaIds[1] = 0;
                distributionY[1] = (PRECISION * 10) / 100;
            } else {
                // throw all liq right below active
                distributionY[1] = ((PRECISION * 10) / 100);
                deltaIds[1] = 0;
            }

            anchorBin = activeBinId - 1;

            _addLiquidity(
                deltaIds,
                distributionX,
                distributionY,
                0,
                totalEthInContract,
                activeBinId
            );
        } else {
            int256[] memory deltaIds = new int256[](6);
            uint256[] memory distributionX = new uint256[](6);
            uint256[] memory distributionY = new uint256[](6);

            deltaIds[0] = deltaForMainLiq;
            distributionX[0] = 0;
            distributionY[0] = (PRECISION * 90) / 100;

            distributionY[1] = ((PRECISION * 10 * 10) / 10000);
            deltaIds[1] = -1;
            distributionY[2] = ((PRECISION * 10 * 15) / 10000);
            deltaIds[2] = -2;
            distributionY[3] = ((PRECISION * 10 * 20) / 10000);
            deltaIds[3] = -3;
            distributionY[4] = ((PRECISION * 10 * 25) / 10000);
            deltaIds[4] = -4;
            distributionY[5] = ((PRECISION * 10 * 30) / 10000);
            deltaIds[5] = -5;

            anchorBin = activeBinId - 5;

            _addLiquidity(
                deltaIds,
                distributionX,
                distributionY,
                0,
                totalEthInContract,
                activeBinId
            );
        }

        isRebalancing = false;
    }

    // scenario 2
    // when a sell causes active bin to move below anchor, we reset the entire protocol
    // gas heavy so dumper pays.
    // will be called by the transfer func on sells
    function _reset() internal {
        isRebalancing = true;

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
            deltaIds[i] = int256(i+1);
            distributionX[i] = (PRECISION * 1) / 100;
        }

        // distribute 50% of tokens to last bin
        deltaIds[50] = 51;
        distributionX[50] = (PRECISION * 50) / 100;


        for (uint256 i = 0; i < 51; i++) {
            console.log(i, uint256(deltaIds[i]), distributionX[i], distributionY[i]);
        }

        // reset values
        lastRecordedActiveBin = getActiveBinId();

        // set the anchor bin to the floor bin so that reset() cannot be triggered again until
        // we successfully rebalance the ETH liquidity again.
        anchorBin = floorBin;

        // decrement because we are going 1 bin past the active bin
        maxBin = uint24(lastRecordedActiveBin + 51);

        // each bin besides the last bin is 1%
        xPerBin = tokenXbalance / 100;

        // last bin has 50% of all tokens
        maxBinAmt = tokenXbalance / 2;

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
    // transfer func should check if we need to call this
    // this func will be called if were already in floor bin and ppl
    // keep selling.
    function _recycle() internal {
        isRebalancing = true;
        // remove floor bin lp
        _removeFloorBinLiquidity();

        uint256 tokenXbalance = balanceOf[address(this)];
        uint256 tokenYbalance = native.balanceOf(address(this));

        uint24 activeBinId = getActiveBinId();

        // only give floor bin ETH and give tokens to maxBin
        int256[] memory deltaIds = new int256[](1);
        deltaIds[0] = 0;

        // give tokens to last bin
        uint256[] memory distributionX = new uint256[](1);
        distributionX[0] = 0;

        // put all eth back to active bin
        uint256[] memory distributionY = new uint256[](1);
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

    function _removeJimboLiquidity() internal {
        // only triggered when reset() is called
        // remove bin inclusive of the anchor, because anchor can never be thel floor bin when reset() is triggered
        uint256 numberOfBinsToWithdraw = (maxBin - uint256(anchorBin)) + 1;

        uint256[] memory amounts = new uint256[](numberOfBinsToWithdraw);
        uint256[] memory ids = new uint256[](numberOfBinsToWithdraw);

        for (uint256 i = 0; i < numberOfBinsToWithdraw; i++) {
            ids[i] = anchorBin + i;
            amounts[i] = pair.balanceOf(address(this), anchorBin + i);
        }

        pair.burn(address(this), address(this), ids, amounts);
    }

    function _removeETHliq() internal {
        // floor bin + how many anchor + bins we cleared through
        uint256 numberOfBinsToWithdraw = getActiveBinId() - anchorBin;

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

    function _removeFloorBinLiquidity() internal {
        uint256[] memory ids = new uint256[](1);
        uint256[] memory amounts = new uint256[](1);

        ids[0] = floorBin;
        amounts[0] = pair.balanceOf(address(this), floorBin);

        pair.burn(address(this), address(this), ids, amounts);
    }

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

    // ==== Tax and transfer mechanism ====

    /**
        @notice charge tax on sells and buys functions.
        @return _amount remaining to the sender
     */
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

                // Notify staking of new reward distro
                JimboStaking(vault).notifyRewardAmount(sendToVault);

                // recycle tokens if the trades are happening in the floor bin
                if (activeBinId < anchorBin) {
                    _reset();       
                } else if (activeBinId == floorBin) {
                    _recycle();
                }
            }
        }
    }

    function transfer(
        address to,
        uint256 amount
    ) public virtual override returns (bool) {
        balanceOf[msg.sender] -= amount;

        uint256 _amount = chargeTax(msg.sender, to, amount);

        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
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

        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[to] += _amount;
        }

        emit Transfer(from, to, _amount);
        return true;
    }

    // ==== Helpers ====

    function _calculateFee(
        uint256 amount,
        uint256 pct
    ) internal pure returns (uint256) {
        uint256 feePercentage = (PRECISION * pct) / 1000; // x pct
        return (amount * feePercentage) / PRECISION;
    }

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

        console.log("");
        console.log("");
        console.log("");
        console.log("");
        console.log("");
        console.log("");
        console.log("");
        console.log("START LOOP AT:", newFloorBin);
        console.log("END LOOP BEFORE: ", activeBinId);

        for (newFloorBin = floorBin; newFloorBin < activeBinId; newFloorBin++) {
            priceAtNextBin = (pair.getPriceFromId(newFloorBin+1)).convert128x128PriceToDecimal();
            console.log("PRICE AT NEW FLOOR, PRICE AT NEXT BIN", newFloorPrice, priceAtNextBin);
            if (priceAtNextBin > newFloorPrice) {
                console.log("PRICE AT CURRENT NEW FLOOR BIN:", (pair.getPriceFromId(newFloorBin)).convert128x128PriceToDecimal());
                break;
            }
        }

        console.log("****************EXPECTED BIN FLOOR*************", newFloorBin);
        return newFloorBin;
    }

    /**
        @notice Helper func.
     */
    function getAverageTokenPrice(
        uint256 totalETH,
        uint256 totalTokens
    ) public view returns (uint256) {
        console.log("FUIUUUUUUUUCK TOTAL ETH", totalETH);
        console.log("FUIUUUUUUUUCK TOTAL TOKENS", totalTokens);

        return (totalETH * PRECISION) / (totalTokens);
    }

    function canRebalance() public view returns (bool) {
        return getActiveBinId() > lastRecordedActiveBin + 5;
    }

    /**
        @notice Get's the pool active bin id.
     */
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

        IUniswapV2Pair pair = IUniswapV2Pair(target);

        try pair.token0() {} catch (bytes memory) {
            return false;
        }

        try pair.token1() {} catch (bytes memory) {
            return false;
        }

        try pair.kLast() {} catch (bytes memory) {
            return false;
        }

        return true;
    }

    function binsUntilRebal() external view returns (uint256) {
        uint256 activeBinId = getActiveBinId();
        if (activeBinId > lastRecordedActiveBin + 5) {
            return type(uint256).max;
        }

        // need to blow 1 past the last acive bin
        return (lastRecordedActiveBin + 6) - getActiveBinId();
    }

    function getFloorLiqBin() external view returns (uint256, uint256) {
        return pair.getBin(floorBin);
    }

    function getFloorPrice() external view returns (uint256) {
        return (pair.getPriceFromId(floorBin)).convert128x128PriceToDecimal();
    }
}

