// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./IConfigurations.sol";
import "./IPricingOracle.sol";
import "./IPremuimPricer.sol";
import "./IBalanceSheet.sol";

import "./AccessControl.sol";
import "./EnumerableSet.sol";
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
contract BalanceSheet is IBalanceSheet, AccessControl {
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableSet for EnumerableSet.AddressSet;

    using PRBMathSD59x18 for int256;
    using PRBMathUD60x18 for uint256;

    address public immutable configurationsAddress;
    address public immutable premiumPricerAddress;

    mapping(address => EnumerableSet.UintSet) private userToTokenIds;
    mapping(address => uint256) private userToTotalAccruedFees;
    mapping(address => uint256) private userToTotalBorrowedAmount;
    mapping(address => uint256) private userToTotalPaymentsAmount;
    mapping(address => uint256) private userToLiquidationCount;
    mapping(address => uint256) private userToClaimableFees;

    EnumerableSet.AddressSet private users;

    bytes32 public constant ASSET_MANAGER_ROLE =
        keccak256("ASSET_MANAGER_ROLE");
    bytes32 public constant DEFRAG_SYSTEM_ADMIN_ROLE =
        keccak256("DEFRAG_SYSTEM_ADMIN_ROLE");

    event AddedCollateral(address indexed _user, uint256 _tokenId);
    event RemovedCollateral(address indexed _user, uint256 _tokenId);
    event AddedUser(address _user);
    event PaidAmount(address indexed _user, uint256 _paymentAmount);
    event AccruedFee(address indexed _user, uint256 _accruedFee);
    event AddedBorrowedAmount(address indexed _user, uint256 _borrowedAmount);
    event NullifiedLoan(
        address indexed _user,
        uint256 _outStandingLoan,
        uint256 _borrowedAmount,
        uint256 _accruedFees,
        uint256 _claimableFees,
        uint256 _liquidationCount
    );

    constructor(address _configurationsAddress, address _premiumPricerAddress) {
        configurationsAddress = _configurationsAddress;
        premiumPricerAddress = _premiumPricerAddress;

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /**
     * @dev ONLY CALLABLE BY ASSET MANAGER
     * @notice store loan information for a user
     * @param _userAddress - address of the user
     * @param _tokenIds - array of tokenIds which represent the collateral
     * @param _borrowedAmount - amount user borrows
     */
    function setLoan(
        address _userAddress,
        uint256[] memory _tokenIds,
        uint256 _borrowedAmount
    ) public onlyAssetManager {
        _addCollateral(_userAddress, _tokenIds);
        _addBorrowedAmount(_userAddress, _borrowedAmount);

        // only set the fee if there is a borrowed amount
        if (_borrowedAmount > 0) {
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
        address[] memory allUsers = EnumerableSet.values(users);

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
     * @param _tokenIds - token ID array
     */
    function removeCollateral(
        address _userAddress,
        uint256[] memory _tokenIds
    ) public onlyAssetManager {
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            require(
                EnumerableSet.contains(
                    userToTokenIds[_userAddress],
                    _tokenIds[i]
                ),
                "BalanceSheet: collateral does not exist"
            );
        }

        if (getOutstandingLoan(_userAddress) > 0) {
            uint256 newCollateralRatio = removingCollateralProjectedRatio(
                _userAddress,
                _tokenIds.length
            );

            require(
                newCollateralRatio >=
                    IConfigurations(configurationsAddress)
                        .liquidationThreshold(),
                "BalanceSheet: risks liquidation"
            );
        }

        for (uint256 i = 0; i < _tokenIds.length; i++) {
            EnumerableSet.remove(userToTokenIds[_userAddress], _tokenIds[i]);
            emit RemovedCollateral(_userAddress, _tokenIds[i]);
        }
    }

    /**
     * @notice checks if user address exists
     * @param _userAddress - address of the user
     * @return bool - true or false
     */
    function isExistingUser(address _userAddress) public view returns (bool) {
        return EnumerableSet.contains(users, _userAddress);
    }

    /**
     * @notice calculates projected collateral ratio if tokens are removed
     * @param _userAddress - address of the user
     * @param _numberOfTokens - number of collateral
     * @return newCollateralRatio
     */
    function removingCollateralProjectedRatio(
        address _userAddress,
        uint256 _numberOfTokens
    ) public view returns (uint256 newCollateralRatio) {
        uint256 newNumberOfTokens = EnumerableSet
            .values(userToTokenIds[_userAddress])
            .length - _numberOfTokens;

        if (getOutstandingLoan(_userAddress) > 0) {
            return
                (newNumberOfTokens * getAssetAveragePrice()).div(
                    getOutstandingLoan(_userAddress)
                );
        } else {
            return 0;
        }
    }

    /**
     * @notice calculates projected collateral ratio if tokens are added
     * @param _userAddress - address of the user
     * @param _numberOfTokens - number of collateral
     * @return newCollateralRatio
     */
    function addingCollateralProjectedRatio(
        address _userAddress,
        uint256 _numberOfTokens
    ) public view returns (uint256 newCollateralRatio) {
        uint256 newNumberOfTokens = EnumerableSet
            .values(userToTokenIds[_userAddress])
            .length + _numberOfTokens;
        if (getOutstandingLoan(_userAddress) > 0) {
            return
                (newNumberOfTokens * getAssetAveragePrice()).div(
                    getOutstandingLoan(_userAddress)
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
        require(
            _paymentAmount <= getOutstandingLoan(_userAddress),
            "BalanceSheet: payment amount exceeds outstanding loan"
        );

        uint256 feesToSend;

        if (_paymentAmount <= getAccruedFees(_userAddress)) {
            userToClaimableFees[_userAddress] += _paymentAmount;
            feesToSend = _paymentAmount;
        } else {
            feesToSend =
                getAccruedFees(_userAddress) -
                getClaimableFees(_userAddress);
            userToClaimableFees[_userAddress] += feesToSend;
        }

        userToTotalPaymentsAmount[_userAddress] += _paymentAmount;
        emit PaidAmount(_userAddress, _paymentAmount);

        return feesToSend;
    }

    /**
     * @notice returns basic loan data
     * @param _userAddress - address of the user
     * @return tokenIds array
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
            uint256[] memory tokenIds,
            uint256 accruedFees,
            uint256 borrowedAmount,
            uint256 paymentsAmount,
            uint256 claimableFees
        )
    {
        return (
            getTokenIds(_userAddress),
            getAccruedFees(_userAddress),
            getBorrowedAmount(_userAddress),
            getPaymentsAmount(_userAddress),
            getClaimableFees(_userAddress)
        );
    }

    /**
     * @notice returns loan metrics data
     * @param _userAddress - address of the user
     * @return collateralizationRatio array
     * @return outstandingLoan
     * @return borrowingPower
     * @return collateralValue
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
            uint256 collateralValue
        )
    {
        return (
            getCollateralizationRatio(_userAddress),
            getOutstandingLoan(_userAddress),
            getBorrowingPower(_userAddress),
            getCollateralValue(_userAddress)
        );
    }

    /**
     * @notice returns tokenIds representing collateral
     * @param _userAddress - address of the user
     * @return tokenIds
     */
    function getTokenIds(
        address _userAddress
    ) public view returns (uint256[] memory tokenIds) {
        return (EnumerableSet.values(userToTokenIds[_userAddress]));
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
        uint256 spotPrice = getAssetAveragePrice() * _numberOfTokens;

        return
            IPremuimPricer(premiumPricerAddress).getPrice(
                spotPrice,
                _strikePrice,
                IConfigurations(configurationsAddress).impliedVolatility(),
                IConfigurations(configurationsAddress).expirationCycle(),
                IConfigurations(configurationsAddress).riskFreeRate()
            );
    }

    /**
     * @notice calls nft pricing oracle
     * @return assetAveragePrice - average floor price from the NFT pricing oracle
     */
    function getAssetAveragePrice()
        public
        view
        returns (uint256 assetAveragePrice)
    {
        address pricingOracle = IConfigurations(configurationsAddress)
            .pricingOracle();

        return IPricingOracle(pricingOracle).currentAverage();
    }

    /**
     * @notice user collateral value
     * @param _userAddress - address of the user
     * @return collateralValue
     */
    function getCollateralValue(
        address _userAddress
    ) public view returns (uint256 collateralValue) {
        uint256 numberOfTokens = EnumerableSet.length(
            userToTokenIds[_userAddress]
        );

        return numberOfTokens * getAssetAveragePrice();
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
        uint256 maxBorrow = IConfigurations(configurationsAddress).maxBorrow();
        uint256 outStandingLoan = getOutstandingLoan(_userAddress);

        if (collateralValue.mul(maxBorrow) > outStandingLoan) {
            return collateralValue.mul(maxBorrow) - outStandingLoan;
        } else {
            return 0;
        }
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
        address[] memory allUsers = EnumerableSet.values(users);
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
            IConfigurations(configurationsAddress).liquidationThreshold();
    }

    /**
     * @notice goes through the user's collateral set and returns the addresses of users who are up for liquidation
     * @dev optimize this loop when filtering out users who are liquidatable
     * @return an array of user addresses
     */
    function getLiquidatables() public view returns (address[] memory) {
        address[] memory allUsers = EnumerableSet.values(users);
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
        address[] memory allUsers = EnumerableSet.values(users);
        uint256 amountBorrowed;
        for (uint256 i = 0; i < allUsers.length; i++) {
            amountBorrowed += userToTotalBorrowedAmount[allUsers[i]];
        }
        return amountBorrowed;
    }

    /**
     * @notice gets system total collateral
     * @return systemTotalCollateral variable for system total collateral
     */
    function getSystemTotalCollateral()
        public
        view
        returns (uint256 systemTotalCollateral)
    {
        address[] memory allUsers = EnumerableSet.values(users);
        uint256 totalCollateral;
        for (uint256 i = 0; i < allUsers.length; i++) {
            totalCollateral += getCollateralValue(allUsers[i]);
        }
        return totalCollateral;
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
        address[] memory allUsers = EnumerableSet.values(users);
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
        address[] memory allUsers = EnumerableSet.values(users);
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
    function nullifyLoan(address _userAddress) public onlyAssetManager {
        // reset users outstanding balance
        uint256 owedAmount = getOutstandingLoan(_userAddress);
        userToTotalPaymentsAmount[_userAddress] += owedAmount;

        // reset collateral
        uint256[] memory collateral = getTokenIds(_userAddress);
        for (uint256 i = 0; i < collateral.length; i++) {
            EnumerableSet.remove(userToTokenIds[_userAddress], collateral[i]);
        }

        // add counter
        userToLiquidationCount[_userAddress] += 1;

        emit NullifiedLoan(
            _userAddress,
            owedAmount,
            getBorrowedAmount(_userAddress),
            getAccruedFees(_userAddress),
            getClaimableFees(_userAddress),
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
        address[] memory allUsers = EnumerableSet.values(users);
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
        address[] memory allUsers = EnumerableSet.values(users);
        uint256 collateralValue;
        for (uint256 i = 0; i < allUsers.length; i++) {
            collateralValue += getCollateralValue(allUsers[i]);
        }
        return collateralValue;
    }

    /**
     * @notice gets system level total number of tokens
     * @return totalNumberOfTokens for the protocol
     */
    function getTotalNumberOfTokens()
        public
        view
        returns (uint256 totalNumberOfTokens)
    {
        address[] memory allUsers = EnumerableSet.values(users);
        uint256 numberOfTokens;
        for (uint256 i = 0; i < allUsers.length; i++) {
            numberOfTokens += getTokenIds(allUsers[i]).length;
        }
        return numberOfTokens;
    }

    /**
     * @notice gets system level metrics
     * @return totalBorrowedAmount
     * @return totalCollateralValue
     * @return totalNumberOfTokens
     * @return totalAccruedFees
     * @return totalPayments
     * @return totalClaimableFees
     * @return totalLiquidationCount
     */
    function getProtocolMetrics()
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
            getTotalNumberOfTokens(),
            getTotalAccruedFees(),
            getTotalPayments(),
            getTotalClaimableFees(),
            getTotalLiquidationCount()
        );
    }

    // ----------------------- Internal Functions -----------------------

    /**
     * @dev private function - called by setLoan() and updateFees()
     * @notice set fees which is the current premium divided by the premiumFeeProration
     * @param _userAddress - address of the user
     */
    function _setFee(address _userAddress) private {
        uint256 numberOfTokens = userToTokenIds[_userAddress].length();
        uint256 currentPremium = getCurrentPremium(
            numberOfTokens,
            getOutstandingLoan(_userAddress)
        );

        uint256 fee = currentPremium.div(
            IConfigurations(configurationsAddress).premiumFeeProration()
        );

        uint256 minimumPremiumFee = IConfigurations(configurationsAddress)
            .minimumPremiumFee();

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
        // check if user exausted borrowing power
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
     * @param _tokenIds - token ID array
     */
    function _addCollateral(
        address _userAddress,
        uint256[] memory _tokenIds
    ) private {
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            if (EnumerableSet.add(userToTokenIds[_userAddress], _tokenIds[i])) {
                emit AddedCollateral(_userAddress, _tokenIds[i]);
            }
        }
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

