// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IAaveL2Pool} from "./IAaveL2Pool.sol";
import {IAaveL2Encoder} from "./IAaveL2Encoder.sol";
import {ERC20} from "./ERC20.sol";
import {IPositionManager} from "./IPositionManager.sol";
import {TokenAllocation} from "./TokenAllocation.sol";
import {TokenExposure} from "./TokenExposure.sol";
import {ProtohedgeVault} from "./ProtohedgeVault.sol";
import {PriceUtils} from "./PriceUtils.sol";
import {PositionType} from "./PositionType.sol";
import {IGmxRouter} from "./IGmxRouter.sol";
import {Math} from "./Math.sol";
import {USDC_MULTIPLIER, PERCENTAGE_MULTIPLIER, BASIS_POINTS_DIVISOR} from "./Constants.sol";
import {GlpUtils} from "./GlpUtils.sol";
import {ERC20} from "./ERC20.sol";
import {PositionManagerStats} from "./PositionManagerStats.sol";
import {IAaveProtocolDataProvider} from "./IAaveProtocolDataProvider.sol";
import {Strings} from "./Strings.sol";
import {RebalanceAction} from "./RebalanceAction.sol";

uint256 constant MIN_BUY_OR_SELL_AMOUNT = 100000;

import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./OwnableUpgradeable.sol";

struct InitializeArgs {
    string positionName;
    uint256 decimals;
    uint256 targetLtv;
    address tokenPriceFeedAddress;
    address aaveL2PoolAddress;
    address aaveL2EncoderAddress;
    address usdcAddress;
    address borrowTokenAddress;
    address protohedgeVaultAddress;
    address priceUtilsAddress;
    address gmxRouterAddress;
    address glpUtilsAddress;
    address aaveProtocolDataProviderAddress;
}

contract AaveBorrowPositionManager is
    IPositionManager,
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable
{
    string private positionName;
    uint256 public usdcAmountBorrowed;
    bool private _canRebalance;
    uint256 private decimals;
    address private tokenPriceFeedAddress;
    uint256 private targetLtv;
    uint256 public amountOfTokens;
    uint256 public collateral;

    IAaveL2Pool private l2Pool;
    IAaveL2Encoder private l2Encoder;
    ERC20 private usdcToken;
    ERC20 private borrowToken;
    ProtohedgeVault private protohedgeVault;
    PriceUtils private priceUtils;
    IGmxRouter private gmxRouter;
    GlpUtils private glpUtils;
    IAaveProtocolDataProvider private aaveProtocolDataProvider;

    modifier onlyVaultOrOwnerOrSelf() {
        require(
            msg.sender == address(protohedgeVault) ||
                msg.sender == owner() ||
                msg.sender == address(this) // If sender is coming from IPositionManager
        );
        _;
    }

    function initialize(InitializeArgs memory args) public initializer {
        positionName = args.positionName;
        decimals = args.decimals;
        _canRebalance = true;
        tokenPriceFeedAddress = args.tokenPriceFeedAddress;
        targetLtv = args.targetLtv;

        l2Pool = IAaveL2Pool(args.aaveL2PoolAddress);
        l2Encoder = IAaveL2Encoder(args.aaveL2EncoderAddress);
        usdcToken = ERC20(args.usdcAddress);
        borrowToken = ERC20(args.borrowTokenAddress);
        protohedgeVault = ProtohedgeVault(args.protohedgeVaultAddress);
        priceUtils = PriceUtils(args.priceUtilsAddress);
        gmxRouter = IGmxRouter(args.gmxRouterAddress);
        glpUtils = GlpUtils(args.glpUtilsAddress);
        aaveProtocolDataProvider = IAaveProtocolDataProvider(
            args.aaveProtocolDataProviderAddress
        );

        usdcToken.approve(
            address(l2Pool),
            0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
        );
        usdcToken.approve(
            address(gmxRouter),
            0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
        );
        borrowToken.approve(
            address(gmxRouter),
            0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
        );
        borrowToken.approve(
            address(l2Pool),
            0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
        );

        __Ownable_init();
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function name() public view override returns (string memory) {
        return positionName;
    }

    function positionWorth() public view override returns (uint256) {
        return getLoanWorth();
    }

    function costBasis() public view override returns (uint256) {
        return usdcAmountBorrowed;
    }

    function pnl() external view override returns (int256) {
        return int256(costBasis() - positionWorth());
    }

    function buy(
        uint256 usdcAmount
    ) external override onlyVaultOrOwnerOrSelf returns (uint256) {
        uint256 targetRatio = collateralRatio();
        uint256 desiredTotalCollateral = ((getLoanWorth() + usdcAmount) *
            targetRatio) / BASIS_POINTS_DIVISOR;
        int256 desiredCollateral = int256(
            desiredTotalCollateral - getCollateral()
        );

        if (desiredCollateral >= 0) {
            require(
                protohedgeVault.getAvailableLiquidity() >=
                    uint256(desiredCollateral),
                "Insufficient liquidity"
            );
            usdcToken.transferFrom(
                address(protohedgeVault),
                address(this),
                uint256(desiredCollateral)
            );

            bytes32 supplyArgs = l2Encoder.encodeSupplyParams(
                address(usdcToken),
                uint256(desiredCollateral),
                0
            );

            l2Pool.supply(supplyArgs);
        }

        uint256 tokensToBorrow = (usdcAmount * (1 * 10 ** decimals)) / price();

        bytes32 borrowArgs = l2Encoder.encodeBorrowParams(
            address(borrowToken),
            tokensToBorrow,
            2, // variable rate mode,
            0
        );

        l2Pool.borrow(borrowArgs);

        address[] memory swapPath = new address[](2);
        swapPath[0] = address(borrowToken);
        swapPath[1] = address(usdcToken);

        gmxRouter.swap(swapPath, tokensToBorrow, 0, address(protohedgeVault));

        usdcAmountBorrowed += usdcAmount;

        return tokensToBorrow;
    }

    function sell(
        uint256 usdcAmount
    ) external override onlyVaultOrOwnerOrSelf returns (uint256) {
        uint256 loanWorth = getLoanWorth();
        uint256 usdcAmountToRepay = Math.min(loanWorth, usdcAmount);
        uint256 feeBasisPoints = glpUtils.getFeeBasisPoints(
            address(usdcToken),
            address(borrowToken),
            usdcAmountToRepay
        );
        uint256 usdcAmountWithSlippage = (usdcAmountToRepay *
            (BASIS_POINTS_DIVISOR + feeBasisPoints)) / BASIS_POINTS_DIVISOR;
        usdcToken.transferFrom(
            address(protohedgeVault),
            address(this),
            usdcAmountWithSlippage
        );

        address[] memory swapPath = new address[](2);
        swapPath[0] = address(usdcToken);
        swapPath[1] = address(borrowToken);

        uint256 amountBefore = borrowToken.balanceOf(address(this));
        gmxRouter.swap(swapPath, usdcAmountWithSlippage, 0, address(this));
        uint256 amountSwapped = Math.min(
            borrowToken.balanceOf(address(this)) - amountBefore,
            getAmountOfTokens()
        );

        bytes32 repayArgs = l2Encoder.encodeRepayParams(
            address(borrowToken),
            amountSwapped,
            2 // variable rate mode
        );

        l2Pool.repay(repayArgs);

        uint256 amountBorrowed = (amountSwapped * this.price()) /
            (1 * 10 ** decimals);
        if (amountBorrowed > usdcAmountBorrowed) {
            usdcAmountBorrowed = 0;
        } else {
            usdcAmountBorrowed -= amountBorrowed;
        }

        rebalanceCollateral();

        return amountSwapped;
    }

    function rebalanceCollateral() public onlyVaultOrOwnerOrSelf {
        uint256 loanWorth = getLoanWorth(); // 850001
        uint256 currentCollateral = getCollateral(); // 1250166
        uint256 expectedCollateral = (loanWorth * PERCENTAGE_MULTIPLIER) / // 1465518
            getTargetLtv();
        uint256 currentLoanToValue = getLoanToValue(); // 67991
        uint256 upperBound = (getTargetLtv() + 500) * 10; // 53000
        uint256 lowerBound = (getTargetLtv() - 500) * 10; // 43000

        if (currentLoanToValue > upperBound) {
            uint256 amountToSupply = expectedCollateral - currentCollateral;

            if (amountToSupply > usdcToken.balanceOf(address(this))) {
                usdcToken.transferFrom(
                    address(protohedgeVault),
                    address(this),
                    amountToSupply - usdcToken.balanceOf(address(this))
                );
            }

            bytes32 supplyArgs = l2Encoder.encodeSupplyParams(
                address(usdcToken),
                amountToSupply,
                0
            );

            l2Pool.supply(supplyArgs);
        } else if (currentLoanToValue < lowerBound) {
            uint256 amountToWithdraw = currentCollateral - expectedCollateral; //

            bytes32 withdrawArgs = l2Encoder.encodeWithdrawParams(
                address(usdcToken),
                amountToWithdraw
            );

            l2Pool.withdraw(withdrawArgs);

            usdcToken.transfer(address(protohedgeVault), amountToWithdraw);
        }
    }

    function exposures()
        external
        view
        override
        returns (TokenExposure[] memory)
    {
        TokenExposure[] memory tokenExposures = new TokenExposure[](1);
        tokenExposures[0] = TokenExposure({
            amount: -1 * int256(getLoanWorth()),
            token: address(borrowToken),
            symbol: borrowToken.symbol()
        });
        return tokenExposures;
    }

    function allocations()
        external
        view
        override
        returns (TokenAllocation[] memory)
    {
        TokenAllocation[] memory tokenAllocations = new TokenAllocation[](1);
        tokenAllocations[0] = TokenAllocation({
            tokenAddress: address(borrowToken),
            symbol: borrowToken.symbol(),
            percentage: BASIS_POINTS_DIVISOR,
            leverage: 1,
            positionType: PositionType.Short
        });
        return tokenAllocations;
    }

    function price() public view override returns (uint256) {
        return priceUtils.getTokenPrice(tokenPriceFeedAddress) / (1 * 10 ** 2); // Convert to USDC price
    }

    function claim() external {}

    function compound() external pure override returns (uint256) {
        return 0;
    }

    function canCompound() external pure override returns (bool) {
        return false;
    }

    function canRebalance(
        uint256 amountOfUsdcToHave
    ) external view override returns (bool, string memory) {
        (, uint256 amountToBuyOrSell) = this.rebalanceInfo(amountOfUsdcToHave);

        if (amountToBuyOrSell < MIN_BUY_OR_SELL_AMOUNT) {
            return (
                false,
                string.concat(
                    "Min buy or sell amount is ",
                    Strings.toString(MIN_BUY_OR_SELL_AMOUNT),
                    "but buy or sell amount is ",
                    Strings.toString(amountToBuyOrSell),
                    " for position manager",
                    name()
                )
            );
        }

        return (true, "");
    }

    function getCollateral() public view returns (uint256) {
        (
            uint256 currentATokenBalance,
            ,
            ,
            ,
            ,
            ,
            ,
            ,

        ) = aaveProtocolDataProvider.getUserReserveData(
                address(usdcToken),
                address(this)
            );
        return currentATokenBalance;
    }

    function getLoanToValue() public view returns (uint256) {
        return
            getCollateral() > 0
                ? (getLoanWorth() * PERCENTAGE_MULTIPLIER * 10) /
                    getCollateral()
                : 0;
    }

    function getAmountOfTokens() public view returns (uint256) {
        (, , uint256 currentVariableDebt, , , , , , ) = aaveProtocolDataProvider
            .getUserReserveData(address(borrowToken), address(this));
        return currentVariableDebt;
    }

    function getLoanWorth() public view returns (uint256) {
        uint256 tokens = getAmountOfTokens();
        return (tokens * price()) / (1 * 10 ** decimals);
    }

    function getLiquidationThreshold() public view returns (uint256) {
        (
            ,
            ,
            uint256 liquidationThreshold,
            ,
            ,
            ,
            ,
            ,
            ,

        ) = aaveProtocolDataProvider.getReserveConfigurationData(
                address(borrowToken)
            );
        return liquidationThreshold;
    }

    function getLiquidationLevel() public view returns (uint256) {
        return
            (getCollateral() * getLiquidationThreshold()) /
            BASIS_POINTS_DIVISOR;
    }

    function collateralRatio() public view override returns (uint256) {
        return (PERCENTAGE_MULTIPLIER * PERCENTAGE_MULTIPLIER) / getTargetLtv();
    }

    function getTargetLtv() public view returns (uint256) {
        (
            ,
            ,
            uint256 liquidationThreshold,
            ,
            ,
            ,
            ,
            ,
            ,

        ) = aaveProtocolDataProvider.getReserveConfigurationData(
                address(borrowToken)
            );
        return liquidationThreshold - 1000;
    }

    function stats()
        external
        view
        override
        returns (PositionManagerStats memory)
    {
        return
            PositionManagerStats({
                positionManagerAddress: address(this),
                name: this.name(),
                positionWorth: this.positionWorth(),
                costBasis: this.costBasis(),
                pnl: this.pnl(),
                tokenExposures: this.exposures(),
                tokenAllocations: this.allocations(),
                price: this.price(),
                collateralRatio: this.collateralRatio(),
                loanWorth: getLoanWorth(),
                liquidationLevel: getLiquidationLevel(),
                collateral: getCollateral()
            });
    }

    function rebalance(
        uint256 usdcAmountToHave
    ) public override onlyVaultOrOwnerOrSelf returns (bool) {
        (RebalanceAction rebalanceAction, uint256 amountToBuyOrSell) = this
            .rebalanceInfo(usdcAmountToHave);

        if (rebalanceAction == RebalanceAction.Buy) {
            this.buy(amountToBuyOrSell);
        } else if (rebalanceAction == RebalanceAction.Sell) {
            this.sell(amountToBuyOrSell);
        }

        return true;
    }

    function liquidate() external override onlyVaultOrOwnerOrSelf {
        this.sell(this.positionWorth());
    }

    function protohedgeVaultAddress() public view override returns (address) {
        return address(protohedgeVault);
    }

    function contractOwner() public view override returns (address) {
        return owner();
    }
}

