pragma solidity ^0.8.17;

import "./ERC20_IERC20.sol";
import "./SafeERC20.sol";
import "./ExponentialNoError.sol";
import "./VeladashLendingLensInterface.sol";
import "./AggregatorV2V3Interface.sol";
import "./SafeMath.sol";

contract VeladashLendingLens is ExponentialNoError {
        
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    struct VTokenMetadata {
        address vToken;
        uint256 exchangeRateCurrent;
        uint256 supplyRatePerBlock;
        uint256 borrowRatePerBlock;
        uint256 reserveFactorMantissa;
        uint256 totalBorrows;
        uint256 totalReserves;
        uint256 totalSupply;
        uint256 totalCash;
        bool isListed;
        uint256 collateralFactorMantissa;
        address underlyingAssetAddress;
        uint256 vTokenDecimals;
        uint256 underlyingDecimals;
        uint256 borrowCap;
        bool borrowPaused;
        int256 utilizationRate;
        uint256 underlyingPrice;
    }

    function vTokenMetadata(
        address _comptroller,
        address _vToken
    ) public returns (VTokenMetadata memory) {
        IComptroller comptroller = IComptroller(_comptroller);
        IComptroller.Market memory market = comptroller.markets(address(_vToken));
        IPriceOracle oracle = IPriceOracle(comptroller.oracle());
        uint256 oraclePriceMantissa = oracle.getUnderlyingPrice(_vToken);

        VTokenMetadata memory meta;
        meta = VTokenMetadata({
            vToken: _vToken,
            exchangeRateCurrent: IVToken(_vToken).exchangeRateStored(),
            supplyRatePerBlock: IVToken(_vToken).supplyRatePerBlock(),
            borrowRatePerBlock: IVToken(_vToken).borrowRatePerBlock(),
            reserveFactorMantissa: IVToken(_vToken).reserveFactorMantissa(),
            totalBorrows: IVToken(_vToken).totalBorrows(),
            totalReserves: IVToken(_vToken).totalReserves(),
            totalSupply: IVToken(_vToken).totalSupply(),
            totalCash: IVToken(_vToken).getCash(),
            isListed: market.isListed,
            collateralFactorMantissa: market.collateralFactorMantissa,
            underlyingAssetAddress: isBaseToken(_vToken) ? address(0) : IVToken(_vToken).underlying(),
            vTokenDecimals: IVToken(_vToken).decimals(),
            underlyingDecimals: isBaseToken(_vToken) ? 18 : IERC20Extented(IVToken(_vToken).underlying()).decimals(),
            borrowCap: comptroller.borrowCaps(_vToken),
            borrowPaused: comptroller.borrowGuardianPaused(_vToken),
            utilizationRate: _getUtilizationRate(_vToken),
            underlyingPrice: oraclePriceMantissa
        });
        return meta;
    }

    function vTokenMetadataAll(
        address _comptroller,
        address[] calldata vTokens
    ) external returns (VTokenMetadata[] memory) {
        uint256 vTokenCount = vTokens.length;
        VTokenMetadata[] memory res = new VTokenMetadata[](vTokenCount);
        for (uint256 i = 0; i < vTokenCount; i++) {
            res[i] = vTokenMetadata(_comptroller, vTokens[i]);
        }
        return res;
    }

struct VTokenBalances {
        address vToken;
        address underlying;
        uint256 balanceOf;
        uint256 borrowBalanceCurrent;
        uint256 borrowBalanceCurrentUsd;
        uint256 balanceOfUnderlying;
        uint256 balanceOfUnderlyingUsd;
        uint256 tokenBalance;
        uint256 tokenBalanceUsd;
        uint256 tokenAllowance;
        uint256 underlyingPrice;
    }

    function vTokenBalances(
        address comptroller,
        address vToken,
        address payable account
    ) public returns (VTokenBalances memory) {
        address underlying = address(0);
        uint256 balanceOf = IVToken(vToken).balanceOf(account);
        uint256 borrowBalanceCurrent = IVToken(vToken).borrowBalanceStored(account);
        uint256 balanceOfUnderlying = IVToken(vToken).balanceOfUnderlying(account);
        uint256 tokenBalance;
        uint256 tokenAllowance;

        if (isBaseToken(vToken)) {
            tokenBalance = account.balance;
            tokenAllowance = account.balance;
        } else {
            underlying = IVToken(vToken).underlying();
            tokenBalance = IERC20(underlying).balanceOf(account);
            tokenAllowance = IERC20(underlying).allowance(account, address(vToken));
        }

        uint256 oraclePriceMantissa = IPriceOracle(IComptroller(comptroller).oracle()).getUnderlyingPrice(vToken);
        Exp memory underlyingPrice = Exp({mantissa: oraclePriceMantissa});

        return
            VTokenBalances({
                vToken: vToken,
                underlying: underlying,
                balanceOf: balanceOf,
                borrowBalanceCurrent: borrowBalanceCurrent,
                borrowBalanceCurrentUsd: mul_(borrowBalanceCurrent, underlyingPrice),
                balanceOfUnderlying: balanceOfUnderlying,
                balanceOfUnderlyingUsd: mul_(balanceOfUnderlying, underlyingPrice),
                tokenBalance: tokenBalance,
                tokenBalanceUsd: mul_(tokenBalance, underlyingPrice),
                tokenAllowance: tokenAllowance,
                underlyingPrice: underlyingPrice.mantissa
            });
    }

    function vTokenBalancesAll(
        address _comptroller,
        address[] calldata vTokens,
        address payable account
    ) external returns (VTokenBalances[] memory) {
        uint256 vTokenCount = vTokens.length;
        VTokenBalances[] memory res = new VTokenBalances[](vTokenCount);
        for (uint256 i = 0; i < vTokenCount; i++) {
            res[i] = vTokenBalances(_comptroller, vTokens[i], account);
        }
        return res;
    }
    
    struct AccountLimits {
        address[] markets;
        uint256 liquidity;
        uint256 shortfall;
    }

    function getAccountLimits(address _comptroller, address account) external view returns (AccountLimits memory) {
        IComptroller comptroller = IComptroller(_comptroller);
        (uint256 errorCode, uint256 liquidity, uint256 shortfall) = comptroller.getAccountLiquidity(account);
        require(errorCode == 0);

        return AccountLimits({markets: comptroller.getAssetsIn(account), liquidity: liquidity, shortfall: shortfall});
    }

    function estimateSupplyRateAfterChange(
        address vToken,
        uint256 change,
        bool redeem,
        address comptroller
    )
        external
        view
        returns (
            uint256,
            uint256
        )
    {
        uint256 cashPriorNew;

        if (redeem) {
            cashPriorNew = sub_(IVToken(vToken).getCash(), change);
        } else {
            cashPriorNew = add_(IVToken(vToken).getCash(), change);
        }

        uint256 supplyInterestRate = IInterestRateModel(IVToken(vToken).interestRateModel()).getSupplyRate(
            cashPriorNew,
            IVToken(vToken).totalBorrows(),
            IVToken(vToken).totalReserves(),
            IVToken(vToken).reserveFactorMantissa()
        );
        
        uint256 oraclePriceMantissa = IPriceOracle(IComptroller(comptroller).oracle()).getUnderlyingPrice(vToken);
        return (supplyInterestRate, oraclePriceMantissa);
    }

    function estimateBorrowRateAfterChange(
        address vToken,
        uint256 change,
        bool repay,
        address comptroller
    )
        external
        view
        returns (
            uint256,
            uint256
        )
    {
        uint256 cashPriorNew;
        uint256 totalBorrowsNew;

        if (repay) {
            cashPriorNew = add_(IVToken(vToken).getCash(), change);
            totalBorrowsNew = sub_(IVToken(vToken).totalBorrows(), change);
        } else {
            cashPriorNew = sub_(IVToken(vToken).getCash(), change);
            totalBorrowsNew = add_(IVToken(vToken).totalBorrows(), change);
        }

        uint256 borrowInterestRate = IInterestRateModel(IVToken(vToken).interestRateModel()).getBorrowRate(cashPriorNew, totalBorrowsNew, IVToken(vToken).totalReserves());
        uint256 oraclePriceMantissa = IPriceOracle(IComptroller(comptroller).oracle()).getUnderlyingPrice(vToken);
        
        return (borrowInterestRate, oraclePriceMantissa);
    }

    function getSupplyAndBorrowRate(
        address vToken,
        uint256 cash,
        uint256 totalBorrows,
        uint256 totalReserves,
        uint256 reserveFactorMantissa
    ) external view returns (uint256, uint256) {
        return (
            IInterestRateModel(IVToken(vToken).interestRateModel()).getSupplyRate(cash, totalBorrows, totalReserves, reserveFactorMantissa),
            IInterestRateModel(IVToken(vToken).interestRateModel()).getBorrowRate(cash, totalBorrows, totalReserves)
        );
    }

    function _getUtilizationRate(address vToken) internal returns (int256) {
        (bool success, bytes memory returnData) = IVToken(vToken).interestRateModel().call(
            abi.encodePacked(
                IJumpRateModelV2(IVToken(vToken).interestRateModel()).utilizationRate.selector,
                abi.encode(IVToken(vToken).getCash(), IVToken(vToken).totalBorrows(), IVToken(vToken).totalReserves())
            )
        );

        int256 utilizationRate;
        if (success) {
            utilizationRate = abi.decode(returnData, (int256));
        } else {
            utilizationRate = -1;
        }

        return utilizationRate;
    }

    function isBaseToken(address vToken) internal view returns (bool) {
        return _compareStrings(IVToken(vToken).symbol(), "vETH");
    }

    function _compareStrings(string memory a, string memory b) internal pure returns (bool) {
        return (keccak256(abi.encodePacked((a))) == keccak256(abi.encodePacked((b))));
    }
}

