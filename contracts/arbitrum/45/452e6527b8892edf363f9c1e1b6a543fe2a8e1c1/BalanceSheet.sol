// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IConfigurations} from "./IConfigurations.sol";
import {IPremuimPricer} from "./IPremuimPricer.sol";
import {IBalanceSheet} from "./IBalanceSheet.sol";

import "./AccessControlUpgradeable.sol";
import "./EnumerableSetUpgradeable.sol";
import "./AggregatorV2V3Interface.sol";
import "./PRBMathSD59x18.sol";
import "./PRBMathUD60x18.sol";

//   /$$$$$$$            /$$$$$$$$
//  | $$__  $$          | $$_____/
//  | $$  \ $$  /$$$$$$ | $$     /$$$$$$  /$$$$$$   /$$$$$$
//  | $$  | $$ /$$__  $$| $$$$$ /$$__  $$|____  $$ /$$__  $$
//  | $$  | $$| $$$$$$$$| $$__/| $$  \__/ /$$$$$$$| $$  \ $$
//  | $$  | $$| $$_____/| $$   | $$      /$$__  $$| $$  | $$
//  | $$$$$$$/|  $$$$$$$| $$   | $$     |  $$$$$$$|  $$$$$$$
//  |_______/  \_______/|__/   |__/      \_______/ \____  $$
//                                                 /$$  \ $$
//                                                |  $$$$$$/
//                                                 \______/

/// @title Balance Sheet: keeps track of loan data and health
/// @author DeFragDAO
/// @custom:experimental This is an experimental contract
contract BalanceSheet is IBalanceSheet, AccessControlUpgradeable {
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

    using PRBMathSD59x18 for int256;
    using PRBMathUD60x18 for uint256;

    IConfigurations public configurations;

    mapping(address => uint256) private userToCollateralAmount;
    mapping(address => uint256) private userToTotalAccruedFees;
    mapping(address => uint256) private userToTotalBorrowedAmount;
    mapping(address => uint256) private userToTotalPaymentsAmount;
    mapping(address => uint256) private userToLiquidationCount;
    mapping(address => uint256) private userToClaimableFees;

    EnumerableSetUpgradeable.AddressSet private users;

    bytes32 public constant ASSET_MANAGER_ROLE =
        keccak256("ASSET_MANAGER_ROLE");
    bytes32 public constant DEFRAG_SYSTEM_ADMIN_ROLE =
        keccak256("DEFRAG_SYSTEM_ADMIN_ROLE");

    event AddedCollateral(address indexed _user, uint256 _amount);
    event RemovedCollateral(address indexed _user, uint256 _amount);
    event AddedUser(address _user);
    event SetPayment(address indexed _user, uint256 _paymentAmount);
    event AccruedFee(address indexed _user, uint256 _accruedFee);
    event AddedBorrowedAmount(address indexed _user, uint256 _borrowedAmount);
    event SetLiquidation(
        address indexed _user,
        uint256 _collateralCount,
        uint256 _liquidationCount
    );

    function initialize(address _configurationsAddress) external initializer {
        __AccessControl_init();

        configurations = IConfigurations(_configurationsAddress);

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /**
     * @dev ONLY CALLABLE BY ASSET MANAGER
     * @notice store loan information for a user
     * @param _userAddress - address of the user
     * @param _collateralAmount - amount user deposits
     * @param _borrowedAmount - amount user borrows
     */
    function setLoan(
        address _userAddress,
        uint256 _collateralAmount,
        uint256 _borrowedAmount
    ) public onlyAssetManager {
        _addCollateral(_userAddress, _collateralAmount);

        // run validations on _borrowedAmount - only if it's above 0
        // only set the fee if there is a borrowed amount
        if (_borrowedAmount > 0) {
            _addBorrowedAmount(_userAddress, _borrowedAmount);
            _setFee(_userAddress);
        }

        if (!isExistingUser(_userAddress)) {
            _addUser(_userAddress);
        }
    }

    /**
     * @dev ONLY CALLABLE BY DEFRAG SYSTEM ADMIN
     * @notice updating fees on every user if they have an outstanding loan
     * @notice frequency is determined by the premiumFeeProration
     */
    function updateFees() public onlyAdmin {
        address[] memory allUsers = EnumerableSetUpgradeable.values(users);

        for (uint256 i = 0; i < allUsers.length; i++) {
            if (getOutstandingLoan(allUsers[i]) > 0) {
                _setFee(allUsers[i]);
            }
        }
    }

    /**
     * @notice ONLY CALLABLE BY ASSET MANAGER
     * @notice removes token ids from the user's collateral set
     * @param _userAddress - address of the user
     * @param _amount - amount of collateral to remove
     */
    function removeCollateral(
        address _userAddress,
        uint256 _amount
    ) public onlyAssetManager {
        require(
            userToCollateralAmount[_userAddress] >= _amount,
            "BalanceSheet: not enough collateral to remove"
        );

        if (getOutstandingLoan(_userAddress) > 0) {
            uint256 newProjectLTV = removingCollateralProjectedLTV(
                _userAddress,
                _amount
            );

            require(
                newProjectLTV <= configurations.maxBorrow() &&
                    newProjectLTV > 0,
                "BalanceSheet: LTV above max borrow"
            );
        }

        userToCollateralAmount[_userAddress] -= _amount;

        emit RemovedCollateral(_userAddress, _amount);
    }

    /**
     * @notice checks if user address exists
     * @param _userAddress - address of the user
     * @return bool - true or false
     */
    function isExistingUser(address _userAddress) public view returns (bool) {
        return EnumerableSetUpgradeable.contains(users, _userAddress);
    }

    /**
     * @notice calculates projected loan to value ratio if tokens are removed
     * @param _userAddress - address of the user
     * @param _amount - number of collateral to be removed
     * @return newLTV
     */
    function removingCollateralProjectedLTV(
        address _userAddress,
        uint256 _amount
    ) public view returns (uint256 newLTV) {
        uint256 newNumberOfTokens = userToCollateralAmount[_userAddress] -
            _amount;

        if (getOutstandingLoan(_userAddress) > 0 && newNumberOfTokens > 0) {
            return
                getOutstandingLoan(_userAddress).div(
                    ((newNumberOfTokens * getAssetCurrentPrice()) / 10 ** 18)
                );
        } else {
            return 0;
        }
    }

    /**
     * @notice ONLY CALLABLE BY ASSET MANAGER
     * @notice adds payment amount to userToTotalPaymentsAmount
     * @param _userAddress - address of the user
     * @param _paymentAmount - payment amount
     * @return amount of fees to send to the treasury
     */
    function setPayment(
        address _userAddress,
        uint256 _paymentAmount
    ) public onlyAssetManager returns (uint256) {
        // solhint-disable-next-line reason-string
        require(
            _paymentAmount <= getOutstandingLoan(_userAddress),
            "BalanceSheet: payment amount exceeds outstanding loan"
        );

        uint256 claimableFees;

        // if fees that are still owed are more than the payment amount
        // add the payment amount to the claimable fees
        if (
            _paymentAmount <=
            (getAccruedFees(_userAddress) - getClaimableFees(_userAddress))
        ) {
            userToClaimableFees[_userAddress] += _paymentAmount;
            claimableFees = _paymentAmount;
        } else {
            claimableFees =
                getAccruedFees(_userAddress) -
                getClaimableFees(_userAddress);
            userToClaimableFees[_userAddress] += claimableFees;
        }

        userToTotalPaymentsAmount[_userAddress] += _paymentAmount;
        emit SetPayment(_userAddress, _paymentAmount);

        return claimableFees.mul(configurations.protocolFee());
    }

    /**
     * @notice returns basic loan data
     * @param _userAddress - address of the user
     * @return collateralAmount
     * @return accruedFees
     * @return borrowedAmount
     * @return paymentsAmount
     */
    function getLoanBasics(
        address _userAddress
    )
        public
        view
        returns (
            uint256 collateralAmount,
            uint256 accruedFees,
            uint256 borrowedAmount,
            uint256 paymentsAmount,
            uint256 claimableFees
        )
    {
        return (
            getCollateralAmount(_userAddress),
            getAccruedFees(_userAddress),
            getBorrowedAmount(_userAddress),
            getPaymentsAmount(_userAddress),
            getClaimableFees(_userAddress)
        );
    }

    /**
     * @notice returns loan metrics data
     * @param _userAddress - address of the user
     * @return collateralizationRatio
     * @return outstandingLoan
     * @return borrowingPower
     * @return collateralValue
     * @return loanToValueRatio - LTV
     * @return healthScore
     */
    function getLoanMetrics(
        address _userAddress
    )
        public
        view
        returns (
            uint256 collateralizationRatio,
            uint256 outstandingLoan,
            uint256 borrowingPower,
            uint256 collateralValue,
            uint256 loanToValueRatio,
            uint256 healthScore
        )
    {
        return (
            getCollateralizationRatio(_userAddress),
            getOutstandingLoan(_userAddress),
            getBorrowingPower(_userAddress),
            getCollateralValue(_userAddress),
            getLoanToValueRatio(_userAddress),
            getHealthScore(_userAddress)
        );
    }

    /**
     * @notice returns tokenIds representing collateral
     * @param _userAddress - address of the user
     * @return amount
     */
    function getCollateralAmount(
        address _userAddress
    ) public view returns (uint256 amount) {
        return userToCollateralAmount[_userAddress];
    }

    /**
     * @notice returns a users' accrued fees
     * @param _userAddress - address of the user
     * @return accruedFees
     */
    function getAccruedFees(
        address _userAddress
    ) public view returns (uint256 accruedFees) {
        return (userToTotalAccruedFees[_userAddress]);
    }

    /**
     * @notice returns users' borrowed amount
     * @param _userAddress - address of the user
     * @return borrowedAmount
     */
    function getBorrowedAmount(
        address _userAddress
    ) public view returns (uint256 borrowedAmount) {
        return (userToTotalBorrowedAmount[_userAddress]);
    }

    /**
     * @notice returns users' loan re-payments
     * @param _userAddress - address of the user
     * @return paymentsAmount
     */
    function getPaymentsAmount(
        address _userAddress
    ) public view returns (uint256 paymentsAmount) {
        return (userToTotalPaymentsAmount[_userAddress]);
    }

    /**
     * @notice calls configurations contract to fetch constants
     * @notice calls nft pricing oracle
     * @notice uses the current price and constants to figure out the premium price
     * @param _numberOfTokens - number of tokens to calculated the premium for
     * @param _strikePrice - is the same a borrowedAmount
     * @return currentPremium - put option price - divide by 10**18 to get decimal value
     */
    function getCurrentPremium(
        uint256 _numberOfTokens,
        uint256 _strikePrice
    ) public view returns (uint256 currentPremium) {
        uint256 spotPrice = (getAssetCurrentPrice() * _numberOfTokens) /
            10 ** 18;

        return
            IPremuimPricer(configurations.premiumPricer()).getPrice(
                spotPrice,
                _strikePrice,
                configurations.impliedVolatility(),
                configurations.expirationCycle(),
                configurations.riskFreeRate()
            );
    }

    /**
     * @notice calls nft pricing oracle
     * @return assetAveragePrice - average floor price from the NFT pricing oracle
     */
    function getAssetCurrentPrice()
        public
        view
        returns (uint256 assetAveragePrice)
    {
        address pricingOracle = configurations.pricingOracle();

        // normalize 8 digit oracle response to 18 digits
        return (uint256(AggregatorV2V3Interface(pricingOracle).latestAnswer()) *
            10 ** (18 - AggregatorV2V3Interface(pricingOracle).decimals()));
    }

    /**
     * @notice user collateral value
     * @param _userAddress - address of the user
     * @return collateralValue
     */
    function getCollateralValue(
        address _userAddress
    ) public view returns (uint256 collateralValue) {
        return
            (userToCollateralAmount[_userAddress] * getAssetCurrentPrice()) /
            10 ** 18;
    }

    /**
     * @notice user outstanding loan
     * @param _userAddress - address of the user
     * @return outstandingLoan
     */
    function getOutstandingLoan(
        address _userAddress
    ) public view returns (uint256 outstandingLoan) {
        return
            getBorrowedAmount(_userAddress) +
            getAccruedFees(_userAddress) -
            getPaymentsAmount(_userAddress);
    }

    /**
     * @notice amount user can borrow up to
     * @param _userAddress - address of the user
     * @return borrowingPower - returns borrowingPower
     */
    function getBorrowingPower(
        address _userAddress
    ) public view returns (uint256 borrowingPower) {
        uint256 collateralValue = getCollateralValue(_userAddress);
        uint256 maxBorrow = configurations.maxBorrow();
        uint256 outStandingLoan = getOutstandingLoan(_userAddress);

        if (collateralValue.mul(maxBorrow) > outStandingLoan) {
            return collateralValue.mul(maxBorrow) - outStandingLoan;
        } else {
            return 0;
        }
    }

    /**
     * @notice protocol max borrow
     * @return maxBorrow - returns maxBorrow
     */
    function getMaxBorrow() public view returns (uint256 maxBorrow) {
        return configurations.maxBorrow();
    }

    /**
     * @notice retrieve collateralization ratio
     * @param _userAddress - address of the user
     * @return collateralizationRatio - expressed as decimal
     */
    function getCollateralizationRatio(
        address _userAddress
    ) public view returns (uint256 collateralizationRatio) {
        if (getOutstandingLoan(_userAddress) > 0) {
            uint256 collateralValue = getCollateralValue(_userAddress);
            uint256 outstandingLoan = getOutstandingLoan(_userAddress);

            return collateralValue.div(outstandingLoan);
        } else {
            return 0;
        }
    }

    /**
     * @notice returns borrower's claimable fees for underwriters
     * @param _userAddress - address of the user
     * @return claimableFees
     */
    function getClaimableFees(
        address _userAddress
    ) public view returns (uint256 claimableFees) {
        return (userToClaimableFees[_userAddress]);
    }

    /**
     * @notice returns system claimable fees for underwriters
     * @return totalClaimableFees
     */
    function getTotalClaimableFees()
        public
        view
        returns (uint256 totalClaimableFees)
    {
        address[] memory allUsers = EnumerableSetUpgradeable.values(users);
        uint256 claimableFees;
        for (uint256 i = 0; i < allUsers.length; i++) {
            claimableFees += getClaimableFees(allUsers[i]);
        }
        return claimableFees;
    }

    /**
     * @notice returns true is the collateralization ration is under the liquidation threshold
     * @param _userAddress - address of the user
     * @return true or false
     */
    function isLiquidatable(address _userAddress) public view returns (bool) {
        return
            getCollateralizationRatio(_userAddress) > 0 &&
            getCollateralizationRatio(_userAddress) <
            configurations.liquidationThreshold();
    }

    /**
     * @notice goes through the user's collateral set and returns the addresses of users who are up for liquidation
     * @dev optimize this loop when filtering out users who are liquidatable
     * @return an array of user addresses
     */
    function getLiquidatables() public view returns (address[] memory) {
        address[] memory allUsers = EnumerableSetUpgradeable.values(users);
        address[] memory liquidables;

        for (uint256 i = 0; i < allUsers.length; i++) {
            if (isLiquidatable(allUsers[i])) {
                address[] memory oldLiquidatables = liquidables;
                liquidables = new address[](oldLiquidatables.length + 1);

                for (uint256 j = 0; j < oldLiquidatables.length; j++) {
                    liquidables[j] = oldLiquidatables[j];
                }

                liquidables[liquidables.length - 1] = allUsers[i];
            }
        }

        return liquidables;
    }

    /**
     * @notice gets system total amount borrowed
     * @return totalAmountBorrowed variable for total amount borrowed
     */
    function getTotalAmountBorrowed()
        public
        view
        returns (uint256 totalAmountBorrowed)
    {
        address[] memory allUsers = EnumerableSetUpgradeable.values(users);
        uint256 amountBorrowed;
        for (uint256 i = 0; i < allUsers.length; i++) {
            amountBorrowed += userToTotalBorrowedAmount[allUsers[i]];
        }
        return amountBorrowed;
    }

    /**
     * @notice gets system total accrued fees
     * @return totalAccruedFees variable for total amount borrowed
     */
    function getTotalAccruedFees()
        public
        view
        returns (uint256 totalAccruedFees)
    {
        address[] memory allUsers = EnumerableSetUpgradeable.values(users);
        uint256 accruedFees;
        for (uint256 i = 0; i < allUsers.length; i++) {
            accruedFees += getAccruedFees(allUsers[i]);
        }
        return accruedFees;
    }

    /**
     * @notice gets system total payments
     * @return totalPayments variable for total payments
     */
    function getTotalPayments() public view returns (uint256 totalPayments) {
        address[] memory allUsers = EnumerableSetUpgradeable.values(users);
        uint256 payments;
        for (uint256 i = 0; i < allUsers.length; i++) {
            payments += getPaymentsAmount(allUsers[i]);
        }
        return payments;
    }

    /**
     * @notice null out user outstanding loan and collateral
     * @param _userAddress - address of the user
     */
    function setLiquidation(address _userAddress) public onlyAssetManager {
        // reset collateral
        uint256 collateralAmount = getCollateralAmount(_userAddress);
        userToCollateralAmount[_userAddress] -= collateralAmount;

        // add liquidation counter
        userToLiquidationCount[_userAddress] += 1;

        emit SetLiquidation(
            _userAddress,
            collateralAmount,
            getLiquidationCount(_userAddress)
        );
    }

    /**
     * @notice get user liquidation count
     * @param _userAddress - address of the user
     * @return liquidationCount
     */
    function getLiquidationCount(
        address _userAddress
    ) public view returns (uint256 liquidationCount) {
        return userToLiquidationCount[_userAddress];
    }

    /**
     * @notice gets system level liquidation count
     * @return totalLiquidationCount variable for total protocol liquidations
     */
    function getTotalLiquidationCount()
        public
        view
        returns (uint256 totalLiquidationCount)
    {
        address[] memory allUsers = EnumerableSetUpgradeable.values(users);
        uint256 accruedFees;
        for (uint256 i = 0; i < allUsers.length; i++) {
            accruedFees += getLiquidationCount(allUsers[i]);
        }
        return accruedFees;
    }

    /**
     * @notice gets system level collateral value
     * @return totalCollateralValue for the protocol
     */
    function getTotalCollateralValue()
        public
        view
        returns (uint256 totalCollateralValue)
    {
        address[] memory allUsers = EnumerableSetUpgradeable.values(users);
        uint256 collateralValue;
        for (uint256 i = 0; i < allUsers.length; i++) {
            collateralValue += getCollateralValue(allUsers[i]);
        }
        return collateralValue;
    }

    /**
     * @notice gets system level total number of tokens
     * @return totalCollateralAmount for the protocol
     */
    function getTotalCollateralAmount()
        public
        view
        returns (uint256 totalCollateralAmount)
    {
        address[] memory allUsers = EnumerableSetUpgradeable.values(users);
        uint256 collateralAmount;
        for (uint256 i = 0; i < allUsers.length; i++) {
            collateralAmount += getCollateralAmount(allUsers[i]);
        }
        return collateralAmount;
    }

    /**
     * @notice gets system level basics
     * @return totalBorrowedAmount
     * @return totalCollateralValue
     * @return totalNumberOfTokens
     * @return totalAccruedFees
     * @return totalPayments
     * @return totalClaimableFees
     * @return totalLiquidationCount
     */
    function getProtocolBasics()
        external
        view
        returns (
            uint256 totalBorrowedAmount,
            uint256 totalCollateralValue,
            uint256 totalNumberOfTokens,
            uint256 totalAccruedFees,
            uint256 totalPayments,
            uint256 totalClaimableFees,
            uint256 totalLiquidationCount
        )
    {
        return (
            getTotalAmountBorrowed(),
            getTotalCollateralValue(),
            getTotalCollateralAmount(),
            getTotalAccruedFees(),
            getTotalPayments(),
            getTotalClaimableFees(),
            getTotalLiquidationCount()
        );
    }

    /**
     * @notice gets system level metrics
     * @return totalOutstandingLoans
     * @return protocolLoanToValueRatio
     * @return protocolHealthScore
     */
    function getProtocolMetrics()
        public
        view
        returns (
            uint256 totalOutstandingLoans,
            uint256 protocolLoanToValueRatio,
            uint256 protocolHealthScore
        )
    {
        return (
            getTotalOutstandingLoans(),
            getProtocolLoanToValueRatio(),
            getProtocolHealthScore()
        );
    }

    /**
     * @notice get total amount for oustanding loans
     * @return totalOutstandingLoans
     */
    function getTotalOutstandingLoans()
        public
        view
        returns (uint256 totalOutstandingLoans)
    {
        address[] memory allUsers = EnumerableSetUpgradeable.values(users);
        uint256 outstandingLoans;
        for (uint256 i = 0; i < allUsers.length; i++) {
            outstandingLoans += getOutstandingLoan(allUsers[i]);
        }
        return outstandingLoans;
    }

    /**
     * @notice gets all users
     * @return array of all users
     */
    function getAllUsers() public view returns (address[] memory) {
        return EnumerableSetUpgradeable.values(users);
    }

    /**
     * @notice get loan to value ratio for the user
     * @return loanToValueRatio
     */
    function getLoanToValueRatio(
        address _userAddress
    ) public view returns (uint256 loanToValueRatio) {
        if (getCollateralValue(_userAddress) == 0) {
            return 0;
        }

        return
            getOutstandingLoan(_userAddress).div(
                getCollateralValue(_userAddress)
            );
    }

    /**
     * @notice gets system level loan to value ratio
     * @return protocolLoanToValueRatio
     */
    function getProtocolLoanToValueRatio()
        public
        view
        returns (uint256 protocolLoanToValueRatio)
    {
        if (getTotalCollateralValue() == 0) {
            return 0;
        }

        return getTotalOutstandingLoans().div(getTotalCollateralValue());
    }

    /**
     * @notice gets system level loan to value ratio
     * @return protocolLoanToValueRatio
     */
    function getProtocolLTVThreshold() public view returns (uint256) {
        return uint256(1e18).div(configurations.liquidationThreshold());
    }

    /**
     * @notice gets user's health score
     * @return healthScore
     */
    function getHealthScore(
        address _userAddress
    ) public view returns (uint256 healthScore) {
        if (getLoanToValueRatio(_userAddress) == 0) {
            return 0;
        }

        return getProtocolLTVThreshold().div(getLoanToValueRatio(_userAddress));
    }

    /**
     * @notice gets system level health score
     * @return protocolHealthScore
     */
    function getProtocolHealthScore()
        public
        view
        returns (uint256 protocolHealthScore)
    {
        if (getProtocolLoanToValueRatio() == 0) {
            return 0;
        }

        return getProtocolLTVThreshold().div(getProtocolLoanToValueRatio());
    }

    // ----------------------- Internal Functions -----------------------

    /**
     * @dev private function - called by setLoan() and updateFees()
     * @notice set fees which is the current premium divided by the premiumFeeProration
     * @param _userAddress - address of the user
     */
    function _setFee(address _userAddress) private {
        uint256 collateralAmount = userToCollateralAmount[_userAddress];
        uint256 currentPremium = getCurrentPremium(
            collateralAmount,
            getOutstandingLoan(_userAddress)
        );

        uint256 fee = currentPremium.div(configurations.premiumFeeProration());

        uint256 minimumPremiumFee = configurations.minimumPremiumFee();

        uint256 additionalFee = fee + minimumPremiumFee;
        userToTotalAccruedFees[_userAddress] += additionalFee;
        emit AccruedFee(_userAddress, additionalFee);
    }

    /**
     * @dev private function - called by setLoan()
     * @notice adds user to a users enumerable set
     * @param _userAddress - address of the user
     */
    function _addUser(address _userAddress) private {
        users.add(_userAddress);
        emit AddedUser(_userAddress);
    }

    /**
     * @notice adds borrowing power
     * @param _userAddress - address of the user
     * @param _borrowedAmount - amount borrowed
     */
    function _addBorrowedAmount(
        address _userAddress,
        uint256 _borrowedAmount
    ) private {
        // make sure the amount is more than minBorrow
        require(
            _borrowedAmount >= configurations.minBorrow(),
            "BalanceSheet: borrow amount too low"
        );

        // check if user exhausted borrowing power
        require(
            _borrowedAmount <= getBorrowingPower(_userAddress),
            "BalanceSheet: amount higher than borrowing power"
        );
        userToTotalBorrowedAmount[_userAddress] += _borrowedAmount;
        emit AddedBorrowedAmount(_userAddress, _borrowedAmount);
    }

    /**
     * @notice adds token ids to the user's collateral set
     * @param _userAddress - address of the user
     * @param _amount - amount of tokens added
     */
    function _addCollateral(address _userAddress, uint256 _amount) private {
        userToCollateralAmount[_userAddress] += _amount;
        emit AddedCollateral(_userAddress, _amount);
    }

    modifier onlyAssetManager() {
        require(
            hasRole(ASSET_MANAGER_ROLE, msg.sender),
            "BalanceSheet: only AssetManager"
        );
        _;
    }

    modifier onlyAdmin() {
        require(
            hasRole(DEFRAG_SYSTEM_ADMIN_ROLE, msg.sender),
            "BalanceSheet: only DefragSystemAdmin"
        );
        _;
    }
}

