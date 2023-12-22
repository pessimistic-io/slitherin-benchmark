// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "./AccessControlUpgradeable.sol";
import "./UUPSUpgradeable.sol";
import "./SafeERC20.sol";
import "./IERC20Metadata.sol";
import "./AggregatorV3Interface.sol";
import "./IStrategy.sol";
import "./IDodoSingleAssetPool.sol";
import "./IDodoMine.sol";
import "./IDodoPool.sol";

contract DodoStrategy is AccessControlUpgradeable, UUPSUpgradeable, IStrategy {
    using SafeERC20 for IERC20;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    IERC20 public override underlying;
    IVault public override vault;

    IERC20 public dodoToken;
    IERC20 public dodoCapitalToken;
    IDodoSingleAssetPool public dodoPool;
    IDodoMine public dodoFarm;
    IDodoPool public dodoUsdcPair;
    AggregatorV3Interface public underlyingPriceFeed;
    AggregatorV3Interface public dodoPriceFeed;

    bool internal isBase;
    bool internal sellBase;
    uint256 internal underlyingMultiplier;
    uint256 internal dodoMultiplier;

    function initialize(
        IVault _vault,
        IERC20 _dodoToken,
        IDodoSingleAssetPool _dodoPool,
        IDodoMine _dodoFarm,
        AggregatorV3Interface _underlyingPriceFeed,
        AggregatorV3Interface _dodoPriceFeed,
        IDodoPool _dodoUsdcPair
    ) external initializer {
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, address(_vault));

        underlying = _vault.underlying();
        vault = _vault;
        dodoToken = _dodoToken;
        dodoPool = _dodoPool;
        dodoFarm = _dodoFarm;
        dodoUsdcPair = _dodoUsdcPair;
        sellBase = dodoUsdcPair._BASE_TOKEN_() == address(_dodoToken);

        underlyingPriceFeed = _underlyingPriceFeed;
        dodoPriceFeed = _dodoPriceFeed;

        uint8 underlyingDecimal = IERC20Metadata(address(underlying))
            .decimals();
        uint8 dodoDecimal = IERC20Metadata(address(_dodoToken)).decimals();

        underlyingMultiplier =
            10**(_underlyingPriceFeed.decimals() + underlyingDecimal);
        dodoMultiplier = 10**(_dodoPriceFeed.decimals() + dodoDecimal);

        isBase = address(underlying) == _dodoPool._BASE_TOKEN_();
        dodoCapitalToken = IERC20(
            isBase
                ? _dodoPool._BASE_CAPITAL_TOKEN_()
                : _dodoPool._QUOTE_CAPITAL_TOKEN_()
        );
    }

    function invest() external override onlyRole(OPERATOR_ROLE) {
        dodoFarm.claim(address(dodoCapitalToken));
        _sellReward();

        uint256 _amount = underlying.balanceOf(address(this));
        require(_amount != 0, "zero");

        if (_amount != 0) {
            underlying.safeApprove(address(dodoPool), _amount);
            uint256 lpTokens = _depositToDodoLp(_amount);

            dodoCapitalToken.safeApprove(address(dodoFarm), lpTokens);
            dodoFarm.deposit(address(dodoCapitalToken), lpTokens);

            emit Invested(_amount);
        }
    }

    function withdraw(uint256 amount)
        external
        onlyRole(OPERATOR_ROLE)
        returns (uint256 actualWithdrawn)
    {
        require(amount != 0, "zero");

        uint256 lpSupply = dodoCapitalToken.totalSupply();

        uint256 lpAmountToWithdraw = (amount * lpSupply) / _getExpectedTarget();

        uint256 stakedLpBalance = dodoFarm.getUserLpBalance(
            address(dodoCapitalToken),
            address(this)
        );

        if (stakedLpBalance < lpAmountToWithdraw) {
            lpAmountToWithdraw = stakedLpBalance;
            dodoFarm.withdrawAll(address(dodoCapitalToken));
        } else {
            dodoFarm.withdraw(address(dodoCapitalToken), lpAmountToWithdraw);
        }

        _withdrawFromDodoLp();
        _sellReward();

        uint256 currentBal = underlying.balanceOf(address(this));
        actualWithdrawn = currentBal < amount ? currentBal : amount;

        underlying.safeTransfer(address(vault), actualWithdrawn);

        emit Withdrawn(actualWithdrawn);
    }

    function withdrawAll()
        external
        override
        onlyRole(OPERATOR_ROLE)
        returns (uint256 actualWithdrawn)
    {
        dodoFarm.withdrawAll(address(dodoCapitalToken));

        if (dodoCapitalToken.balanceOf(address(this)) != 0) {
            _withdrawFromDodoLp();
        }

        _sellReward();

        actualWithdrawn = underlying.balanceOf(address(this));
        require(actualWithdrawn != 0, "zero");

        underlying.safeTransfer(address(vault), actualWithdrawn);

        emit Withdrawn(actualWithdrawn);
    }

    function totalAssets() external view returns (uint256) {
        uint256 currBal = underlying.balanceOf(address(this));

        uint256 lpValue = _getAmountFromLpAmount(
            dodoFarm.getUserLpBalance(address(dodoCapitalToken), address(this))
        );

        uint256 dodoAmount = dodoToken.balanceOf(address(this)) +
            dodoFarm.getPendingReward(address(dodoCapitalToken), address(this));

        return currBal + lpValue + _getAmountFromDodoAmount(dodoAmount);
    }

    function _depositToDodoLp(uint256 _amount) internal returns (uint256) {
        if (isBase) {
            return dodoPool.depositBase(_amount);
        } else {
            return dodoPool.depositQuote(_amount);
        }
    }

    function _withdrawFromDodoLp() internal returns (uint256) {
        if (isBase) {
            return dodoPool.withdrawAllBase();
        } else {
            return dodoPool.withdrawAllQuote();
        }
    }

    function _withdrawLpFromFarm(uint256 lpAmount)
        internal
        returns (uint256 actualWithdrawn)
    {
        if (lpAmount != 0) {
            actualWithdrawn = lpAmount;
        } else {
            actualWithdrawn = dodoFarm.getUserLpBalance(
                address(dodoCapitalToken),
                address(this)
            );
        }

        if (actualWithdrawn != 0) {
            dodoFarm.withdraw(address(dodoCapitalToken), actualWithdrawn);
        }
    }

    function _sellReward() internal returns (uint256 underlyingReceived) {
        uint256 dodoBal = dodoToken.balanceOf(address(this));

        if (dodoBal != 0) {
            dodoToken.safeTransfer(address(dodoUsdcPair), dodoBal);
            if (sellBase) {
                return dodoUsdcPair.sellBase(address(this));
            } else {
                return dodoUsdcPair.sellQuote(address(this));
            }
        }
    }

    function _getExpectedTarget() internal view returns (uint256) {
        (uint256 baseExpectedTarget, uint256 quoteExpectedTarget) = dodoPool
            .getExpectedTarget();
        if (isBase) return baseExpectedTarget;
        return quoteExpectedTarget;
    }

    function _getAmountFromLpAmount(uint256 lpAmount)
        internal
        view
        returns (uint256)
    {
        if (lpAmount == 0) return 0;
        uint256 lpSupply = dodoCapitalToken.totalSupply();
        if (lpSupply == 0) return 0;

        uint256 amount = (lpAmount * _getExpectedTarget()) / lpSupply;
        uint256 penalty = isBase
            ? dodoPool.getWithdrawBasePenalty(amount)
            : dodoPool.getWithdrawQuotePenalty(amount);

        return amount - penalty;
    }

    function _getAmountFromDodoAmount(uint256 dodoAmount)
        internal
        view
        returns (uint256)
    {
        if (dodoAmount == 0) return 0;
        (, int256 dodoPrice, , , ) = dodoPriceFeed.latestRoundData();
        (, int256 underlyingPrice, , , ) = underlyingPriceFeed
            .latestRoundData();

        require(dodoPrice > 0 && underlyingPrice > 0, "invalid price");

        return
            (dodoAmount * uint256(dodoPrice) * underlyingMultiplier) /
            (uint256(underlyingPrice) * dodoMultiplier);
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyRole(DEFAULT_ADMIN_ROLE)
    {}
}

