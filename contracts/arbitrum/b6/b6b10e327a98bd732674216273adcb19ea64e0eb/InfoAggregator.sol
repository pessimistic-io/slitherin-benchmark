// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "./Ownable2StepUpgradeable.sol";
import "./EnumerableSet.sol";
import "./AggregatorV3Interface.sol";
import "./ISavvyPositionManager.sol";
import "./IInfoAggregator.sol";
import "./IYieldStrategyManager.sol";
import "./Checker.sol";
import "./SafeCast.sol";
import "./TokenUtils.sol";
import {InfoAggregatorUtils} from "./InfoAggregatorUtils.sol";

contract InfoAggregator is IInfoAggregator, Ownable2StepUpgradeable {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @dev Addresses of SavvyPositionManager.
    EnumerableSet.AddressSet private savvyPositionManagers;

    /// @dev The constant variable to get value more correctly.
    uint256 public constant FIXED_POINT_SCALAR = 1e18;

    /// @inheritdoc	IInfoAggregator
    ISavvyPriceFeed public override svyPriceFeed;

    /// @inheritdoc	IInfoAggregator
    ISavvyToken public override svyToken;

    /// @inheritdoc	IInfoAggregator
    ISavvyBooster public override svyBooster;

    /// @inheritdoc	IInfoAggregator
    IVeSvy public override veSvy;

    /// @dev Addresses of yield token.
    SupportTokenInfo[] private supportTokens;

    uint256 private constant OFFSET_RANGE = 100;

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address[] memory _savvyPositionManagers,
        SupportTokenInfo[] memory _supportTokens,
        ISavvyPriceFeed priceFeed_,
        ISavvyToken svyToken_,
        ISavvyBooster svyBooster_,
        IVeSvy veSvy_
    ) public initializer {
        Checker.checkArgument(
            address(svyToken_) != address(0),
            "zero svyToken address"
        );
        Checker.checkArgument(
            address(svyBooster_) != address(0),
            "zero savvy booster address"
        );
        Checker.checkArgument(
            address(veSvy_) != address(0),
            "zero veSvy contract address"
        );
        Checker.checkArgument(
            address(priceFeed_) != address(0),
            "zero price feed address"
        );

        _addSavvyPositionManagers(_savvyPositionManagers);
        if (_supportTokens.length > 0) {
            _addSupportTokens(_supportTokens);
        }

        svyPriceFeed = priceFeed_;
        svyToken = svyToken_;
        svyBooster = svyBooster_;
        veSvy = veSvy_;
        __Ownable_init();
    }

    /// @inheritdoc	IInfoAggregator
    function addSavvyPositionManager(
        address[] calldata _savvyPositionManagers
    ) external override onlyOwner {
        Checker.checkArgument(
            _savvyPositionManagers.length > 0,
            "empty SavvyPositionManager array"
        );
        _addSavvyPositionManagers(_savvyPositionManagers);
    }

    /// @inheritdoc IInfoAggregator
    function addSupportTokens(
        SupportTokenInfo[] calldata _supportTokens
    ) external override onlyOwner {
        _addSupportTokens(_supportTokens);
    }

    /// @inheritdoc IInfoAggregator
    function getSavvyPositionManagers()
        external
        view
        override
        returns (address[] memory)
    {
        return savvyPositionManagers.values();
    }

    /// @inheritdoc ISavvyPositions
    function getWithdrawableAmount(
        address owner_
    ) external view returns (SavvyWithdrawInfo[] memory) {
        uint256 length = savvyPositionManagers.length();
        if (length == 0) {
            return new SavvyWithdrawInfo[](0);
        }

        uint256 depositedLength = 0;
        for (uint256 i = 0; i < length; i++) {
            ISavvyPositionManager savvyPositionManager = ISavvyPositionManager(
                savvyPositionManagers.at(i)
            );
            (, address[] memory depositedTokens) = savvyPositionManager
                .accounts(owner_);
            depositedLength += depositedTokens.length;
        }
        SavvyWithdrawInfo[] memory values = new SavvyWithdrawInfo[](
            depositedLength
        );
        uint256 index = 0;

        for (uint256 i = 0; i < length; i++) {
            ISavvyPositionManager savvyPositionManager = ISavvyPositionManager(
                savvyPositionManagers.at(i)
            );
            SavvyWithdrawInfo[] memory subValues = InfoAggregatorUtils
                ._getWithdrawableAmount(owner_, savvyPositionManager);
            for (uint256 j = 0; j < subValues.length; j++) {
                values[index++] = subValues[j];
            }
        }

        return values;
    }

    /// @inheritdoc ISavvyPositions
    function getBorrowableAmount(
        address owner_
    ) external view returns (SavvyPosition[] memory) {
        uint256 length = savvyPositionManagers.length();
        SavvyPosition[] memory values = new SavvyPosition[](length);

        if (length == 0) {
            return values;
        }

        for (uint256 i = 0; i < length; i++) {
            ISavvyPositionManager savvyPositionManager = ISavvyPositionManager(
                savvyPositionManagers.at(i)
            );
            uint256 borrowableAmount = InfoAggregatorUtils._getBorrowableAmount(
                owner_,
                savvyPositionManager
            );
            values[i] = SavvyPosition(
                savvyPositionManagers.at(i),
                borrowableAmount
            );
        }

        return values;
    }

    /// @inheritdoc	ISavvyOverview
    function getTotalDebtAmount() public view override returns (int256) {
        int256 totalDebt = 0;
        uint256 length = savvyPositionManagers.length();

        for (uint256 i = 0; i < length; i++) {
            totalDebt += InfoAggregatorUtils._getTotalDebtAmount(
                ISavvyPositionManager(savvyPositionManagers.at(i)),
                svyPriceFeed
            );
        }

        return totalDebt;
    }

    /// @inheritdoc	ISavvyOverview
    function getTotalDepositedAmount() public view override returns (uint256) {
        uint256 totalAmount = 0;
        uint256 length = savvyPositionManagers.length();

        for (uint256 i = 0; i < length; i++) {
            totalAmount += InfoAggregatorUtils._getTotalDepositedAmount(
                ISavvyPositionManager(savvyPositionManagers.at(i)),
                svyPriceFeed
            );
        }

        return totalAmount;
    }

    /// @inheritdoc	ISavvyOverview
    function getTotalValueLocked() public view override returns (uint256 totalValueLocked) {
        uint256 totalSVYStakedUSD = getTotalSVYStakedUSD();
        uint256 totalDepositedAmount = getTotalDepositedAmount();
        totalValueLocked = totalSVYStakedUSD + totalDepositedAmount;
    }

    /// @inheritdoc	ISavvyOverview
    function getTotalSVYStaked() public view override returns (uint256) {
        return svyToken.balanceOf(address(veSvy));
    }

    /// @inheritdoc	ISavvyOverview
    function getTotalSVYStakedUSD() public view override returns (uint256) {
        uint256 totalStakedSVY = getTotalSVYStaked();
        uint256 svyPrice = getSVYPrice();
        return totalStakedSVY * svyPrice / FIXED_POINT_SCALAR;
    }

    /// @inheritdoc	ISavvyOverview
    function getAvailableCredit() external view override returns (int256) {
        int256 totalAmount = 0;
        uint256 length = savvyPositionManagers.length();

        for (uint256 i = 0; i < length; i++) {
            totalAmount += InfoAggregatorUtils._getAvailableCreditUSD(
                ISavvyPositionManager(savvyPositionManagers.at(i)),
                svyPriceFeed
            );
        }

        return totalAmount;
    }

    /// @inheritdoc	ISavvyOverview
    function getAllTokenPrice()
        external
        view
        override
        returns (TokenPriceData[] memory)
    {
        uint256 length = savvyPositionManagers.length();
        uint256 tokenAmount = 0;

        for (uint256 i = 0; i < length; i++) {
            IYieldStrategyManager yieldStrategyManager = ISavvyPositionManager(
                savvyPositionManagers.at(i)
            ).yieldStrategyManager();
            address[] memory supportedBaseTokens = yieldStrategyManager
                .getSupportedBaseTokens();
            tokenAmount += supportedBaseTokens.length;
        }

        TokenPriceData[] memory tokenPrices = new TokenPriceData[](tokenAmount);
        if (tokenAmount == 0) return tokenPrices;

        uint256 index = 0;
        for (uint256 i = 0; i < length; i++) {
            IYieldStrategyManager yieldStrategyManager = ISavvyPositionManager(
                savvyPositionManagers.at(i)
            ).yieldStrategyManager();
            address[] memory supportedBaseTokens = yieldStrategyManager
                .getSupportedBaseTokens();
            for (uint256 j = 0; j < supportedBaseTokens.length; j++) {
                address tokenAddress = supportedBaseTokens[j];
                uint8 decimals = TokenUtils.expectDecimals(tokenAddress);
                tokenPrices[index++] = TokenPriceData(
                    tokenAddress,
                    svyPriceFeed.getBaseTokenPrice(tokenAddress, 10 ** decimals)
                );
            }
        }

        return tokenPrices;
    }

    /// @inheritdoc ISavvyUserPortfolio
    function getUserDepositedAmount(
        address user_
    ) public view returns (uint256) {
        uint256 totalAmount = 0;
        uint256 length = savvyPositionManagers.length();

        for (uint256 i = 0; i < length; i++) {
            totalAmount += InfoAggregatorUtils._getUserDepositedAmount(
                ISavvyPositionManager(savvyPositionManagers.at(i)),
                svyPriceFeed,
                user_
            );
        }

        return totalAmount;
    }

    /// @inheritdoc ISavvyUserPortfolio
    function getUserAvailableCredit(
        address user_
    ) external view returns (int256) {
        int256 totalAmount = 0;
        uint256 length = savvyPositionManagers.length();

        for (uint256 i = 0; i < length; i++) {
            totalAmount += InfoAggregatorUtils._getUserAvailableCreditUSD(
                ISavvyPositionManager(savvyPositionManagers.at(i)),
                svyPriceFeed,
                user_
            );
        }

        return totalAmount;
    }

    /// @inheritdoc ISavvyUserPortfolio
    function getUserDebtAmount(address user_) external view returns (int256) {
        int256 totalAmount = 0;
        uint256 length = savvyPositionManagers.length();

        for (uint256 i = 0; i < length; i++) {
            totalAmount += InfoAggregatorUtils._getUserDebtValueUSD(
                svyPriceFeed,
                ISavvyPositionManager(savvyPositionManagers.at(i)),
                user_
            );
        }

        return totalAmount;
    }

    /// @inheritdoc ISavvyUserBalance
    function getUserSVYBalance(
        address user_
    ) external view override returns (uint256) {
        Checker.checkArgument(user_ != address(0), "zero user address");
        return svyToken.balanceOf(user_);
    }

    /// @inheritdoc ISavvyUserBalance
    function getUserStakedSVYAmount(
        address user_
    ) external view override returns (uint256) {
        Checker.checkArgument(user_ != address(0), "zero user address");
        return veSvy.getStakedSvy(user_);
    }

    /// @inheritdoc ISavvyUserBalance
    function getUserVeSVYBalance(
        address user_
    ) external view override returns (uint256) {
        Checker.checkArgument(user_ != address(0), "zero user address");
        return veSvy.balanceOf(user_);
    }

    /// @inheritdoc ISavvyUserBalance
    function getUserClaimableVeSVYAmount(
        address user_
    ) external view override returns (uint256) {
        Checker.checkArgument(user_ != address(0), "zero user address");
        return veSvy.claimable(user_);
    }

    /// @inheritdoc ISavvyUserBalance
    function getUserClaimableSVYAmount(
        address user_
    ) external view override returns (uint256) {
        Checker.checkArgument(user_ != address(0), "zero user address");
        return svyBooster.getClaimableRewards(user_);
    }

    /// @inheritdoc ISavvyUserBalance
    function getSVYPrice() public view override returns (uint256) {
        return svyPriceFeed.getSavvyTokenPrice();
    }

    /// @inheritdoc ISavvyUserBalance
    function getSVYEarnRate(
        address user_
    ) public view override returns (uint256) {
        Checker.checkArgument(user_ != address(0), "zero user address");
        return svyBooster.getSvyEarnRate(user_);
    }

    /// @inheritdoc ISavvyUserBalance
    function getSVYAPY(address user_) external view override returns (uint256) {
        // formula: [user’s SVY earn rate in USD] / [user’s total deposit in USD]
        uint256 totalUserDepositedAmount = getUserDepositedAmount(user_);
        if (totalUserDepositedAmount == 0) {
            return 0;
        }
        uint256 earnRate = getSVYEarnRate(user_);
        earnRate = getSVYPrice() * earnRate;

        return earnRate / totalUserDepositedAmount;
    }

    /// @inheritdoc ISavvyPositions
    function getTotalDepositedTokenAmount(
        address user_
    ) external view override returns (SavvyPosition[] memory) {
        Checker.checkArgument(user_ != address(0), "zero user address");

        uint256 savvyPositionManagerCnt = savvyPositionManagers.length();
        uint256 length = supportTokens.length;
        SavvyPosition[] memory positions = new SavvyPosition[](
            length * savvyPositionManagerCnt
        );

        // loop all savvyPositionManagers.
        for (uint256 i = 0; i < savvyPositionManagerCnt; i++) {
            address savvyPositionManager = savvyPositionManagers.at(i);
            // loop base tokens and get deposited amount by usd.
            for (uint256 j = 0; j < length; j++) {
                uint256 index = i * savvyPositionManagerCnt + j;
                if (positions[index].baseToken == address(0)) {
                    positions[index].baseToken = supportTokens[j].baseToken;
                }

                positions[index].amount += InfoAggregatorUtils
                    ._getUserDepositedTokenPrice(
                        user_,
                        supportTokens[j].yieldToken,
                        savvyPositionManager,
                        svyPriceFeed
                    );
            }
        }

        return positions;
    }

    /// @inheritdoc ISavvyPositions
    function getTotalDebtTokenAmount(
        address user_
    ) external view override returns (DebtInfo[] memory) {
        Checker.checkArgument(user_ != address(0), "zero user address");

        uint256 length = savvyPositionManagers.length();
        DebtInfo[] memory debts = new DebtInfo[](length);

        for (uint256 i = 0; i < length; i++) {
            ISavvyPositionManager savvyPositionManager = ISavvyPositionManager(
                savvyPositionManagers.at(i)
            );
            debts[i].savvyPositionManager = address(savvyPositionManager);
            debts[i].amount = InfoAggregatorUtils._getUserDebtValueUSD(
                svyPriceFeed,
                savvyPositionManager,
                user_
            );
        }

        return debts;
    }

    /// @inheritdoc ISavvyPositions
    function getAvailableDepositTokenAmount(
        address user_
    ) external view override returns (SavvyPosition[] memory) {
        Checker.checkArgument(user_ != address(0), "zero user address");
        uint256 length = supportTokens.length;
        SavvyPosition[] memory positions = new SavvyPosition[](length);

        for (uint256 i = 0; i < length; i++) {
            address baseToken = supportTokens[i].baseToken;
            uint256 amount = IERC20(baseToken).balanceOf(user_);
            amount = InfoAggregatorUtils._getBaseTokenPrice(
                svyPriceFeed,
                baseToken,
                amount
            );
            positions[i] = SavvyPosition(baseToken, amount);
        }

        return positions;
    }

    /// @inheritdoc ISavvyPositions
    function getAvailableCreditToken(
        address user_
    ) external view override returns (DebtInfo[] memory) {
        uint256 length = savvyPositionManagers.length();
        DebtInfo[] memory credits = new DebtInfo[](length);
        for (uint256 i = 0; i < length; i++) {
            ISavvyPositionManager savvyPositionManager = ISavvyPositionManager(
                savvyPositionManagers.at(i)
            );
            int256 debtAmount = InfoAggregatorUtils._getUserDebtValueUSD(
                svyPriceFeed,
                savvyPositionManager,
                user_
            );
            uint256 depositAmount = InfoAggregatorUtils._getUserDepositedAmount(
                savvyPositionManager,
                svyPriceFeed,
                user_
            );
            uint256 minCollateralization = savvyPositionManager
                .minimumCollateralization();

            int256 availableCredit = SafeCast.toInt256(
                (depositAmount * FIXED_POINT_SCALAR) / minCollateralization
            ) - debtAmount;
            credits[i] = DebtInfo(
                address(savvyPositionManager),
                availableCredit
            );
        }

        return credits;
    }

    /// @inheritdoc ISavvyPool
    function getPoolDeposited(
        address user_,
        address poolAddress_
    ) external view override returns (uint256) {
        uint256 length = savvyPositionManagers.length();
        uint256 totalAmount = 0;
        address yieldToken = poolAddress_;

        if (length == 0) {
            return 0;
        }

        for (uint256 i = 0; i < length; i++) {
            address savvyPositionManager = savvyPositionManagers.at(i);
            IYieldStrategyManager yieldStrategyManager = ISavvyPositionManager(
                savvyPositionManager
            ).yieldStrategyManager();
            if (yieldStrategyManager.isSupportedYieldToken(yieldToken)) {
                totalAmount += InfoAggregatorUtils._getUserDepositedTokenPrice(
                    user_,
                    yieldToken,
                    savvyPositionManager,
                    svyPriceFeed
                );
            }
        }

        return totalAmount;
    }

    /// @inheritdoc ISavvyPool
    function getPoolUtilization(
        address poolAddress_,
        address savvyPositionManager_
    ) external view override returns (uint256, uint256) {
        Checker.checkArgument(poolAddress_ != address(0), "zero pool address");
        Checker.checkArgument(
            savvyPositionManager_ != address(0),
            "zero SavvyPositionManager address"
        );

        address yieldToken = poolAddress_;
        IYieldStrategyManager yieldStrategyManager = IYieldStrategyManager(
            ISavvyPositionManager(savvyPositionManager_).yieldStrategyManager()
        );
        ISavvyState.YieldTokenParams
            memory yieldTokenParams = yieldStrategyManager
                .getYieldTokenParameters(yieldToken);

        return (
            yieldTokenParams.expectedValue,
            yieldTokenParams.maximumExpectedValue
        );
    }

    function _addSavvyPositionManagers(
        address[] memory _savvyPositionManagers
    ) internal {
        for (uint256 i = 0; i < _savvyPositionManagers.length; i++) {
            address savvyPositionManager = _savvyPositionManagers[i];
            Checker.checkArgument(
                savvyPositionManager != address(0),
                "zero SavvyPositionManager address"
            );
            Checker.checkArgument(
                !savvyPositionManagers.contains(savvyPositionManager),
                "same SavvyPositionManager exists"
            );
            savvyPositionManagers.add(savvyPositionManager);
        }
    }

    function _addSupportTokens(
        SupportTokenInfo[] memory _supportTokens
    ) internal {
        uint256 length = _supportTokens.length;
        Checker.checkArgument(
            length > 0,
            "empty support token information array"
        );

        for (uint256 i = 0; i < length; i++) {
            Checker.checkState(
                InfoAggregatorUtils._checkSupportTokenExist(
                    supportTokens,
                    _supportTokens[i].yieldToken
                ) == false,
                "same token already exists"
            );
            supportTokens.push(_supportTokens[i]);
        }
    }

    uint256[100] private __gap;
}

