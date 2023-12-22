// SPDX-License-Identifier: Unlicense
pragma solidity ^0.7.3;

import "./Initializable.sol";
import "./OwnableUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./IERC20Upgradeable.sol";
import "./SafeMath.sol";
import "./ILiquidityPool.sol";
import "./IComptroller.sol";
import "./ILPT.sol";
import "./IFlashLoanReceiver.sol";
import "./IxTokenManager.sol";
import "./BlockLock.sol";

/// @title Liquidity Pool
/// @notice The most important contract. Almost all the protocol is coded here
/// @dev Upgradeable Smart Contract
contract LiquidityPool is
    Initializable,
    OwnableUpgradeable,
    BlockLock,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    ILiquidityPool
{
    using SafeMath for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    struct Borrow {
        uint256 amount;
        uint256 interestIndex;
        uint256 borrowedAtBlock;
    }

    address private stableCoin;
    address private liquidityPoolToken;
    uint256 private accrualBlock;
    uint256 private borrowIndex;
    uint256 private optimalUtilizationRate;
    uint256 private baseBorrowRate;
    uint256 private slope1;
    uint256 private slope2;
    uint256 private reserveFactor;
    uint256 private xtkFeeFactor;
    uint256 private flashLoanFeeFactor;
    uint256 private lptBaseValue;
    uint256 private minimumLoanValue;
    uint256 private liquidityPenaltyFactor;
    uint256 private maxLiquidationHealthRatio;
    uint256 private minBorrowHealthRatio;

    /// @dev Comptroller's address
    address public comptroller;
    /// @dev Current total borrows owed to this Liquidity Pool
    uint256 public totalBorrows;
    /// @dev Current reserves
    uint256 public reserves;
    /// @dev Current protocol earnings
    uint256 public xtkEarns;

    uint256 private stableCoinDecimalMultiplier;

    mapping(address => Borrow) borrows;
    mapping(address => bool) liquidationExempt;
    mapping(address => bool) flashBorrowers;

    IxTokenManager private xTokenManager;

    uint256 private constant RATIOS = 1e16;
    uint256 private constant FACTOR = 1e18;
    uint256 private constant BLOCKS_PER_YEAR = 2628000;

    event UpdateLiquidityPoolToken(address indexed liquidityPoolToken);
    event UpdateComptroller(address indexed comptroller);
    event UpdateInterestModelParameters(
        uint256 optimalUtilizationRate,
        uint256 baseBorrowRate,
        uint256 slope1,
        uint256 slope2
    );
    event UpdateXtkFeeFactor(uint256 xtkFeeFactor);
    event UpdateReserveFeeFactor(uint256 reserveFactor);
    event UpdateLPTBaseValue(uint256 lptBaseValue);
    event UpdateMinimumLoanValue(uint256 minimumLoanValue);
    event UpdateLiquidationPenaltyFactor(uint256 liquidityPenaltyFactor);
    event WithdrawFee(address indexed recipient, uint256 xtkEarns);
    event SupplyEvent(address indexed supplier, uint256 supplyAmount, uint256 lptAmount);
    event WithdrawEvent(address indexed supplier, uint256 lptAmount, uint256 withdrawAmount);
    event BorrowEvent(address indexed borrower, uint256 borrowAmount, uint256 debtAmount);
    event RepayEvent(address indexed borrower, uint256 repayAmount, uint256 debtAmount);
    event LiquidateEvent(address indexed borrower, address indexed liquidator, uint256 amount, address[] markets);
    event FlashLoan(address indexed receiver, uint256 amount, uint256 amountFee);

    modifier onlyOwnerOrManager() {
        require(msg.sender == owner() || xTokenManager.isManager(msg.sender, address(this)), "Non-admin caller");
        _;
    }

    /// @notice Upgradeable smart contract constructor
    /// @dev Initializes this Liquidity Pool
    function initialize(address _stableCoin, uint256 _decimal) external initializer {
        require(_stableCoin != address(0));
        __Ownable_init();
        __Pausable_init_unchained();
        __ReentrancyGuard_init_unchained();

        stableCoin = _stableCoin;
        stableCoinDecimalMultiplier = 10**(18 - _decimal);
        borrowIndex = FACTOR;
        maxLiquidationHealthRatio = 120;
        minBorrowHealthRatio = 105;
    }

    /// @notice USDC owned by this Liquidity Pool
    /// @dev The return value has 18 decimals
    /// @return (uint256) How much USDC the Liquidity Pool owns
    function currentLiquidity() public view returns (uint256) {
        return convertTo18(IERC20Upgradeable(stableCoin).balanceOf(address(this)));
    }

    /// @notice Tells how much the protocol is being used
    /// @return (uint256) Utilization Rate value multiplied by FACTOR(1e18)
    function utilizationRate() public view returns (uint256) {
        if (totalBorrows == 0) return 0;
        return totalBorrows.mul(FACTOR).div(totalBorrows.add(currentLiquidity()).sub(reserves).sub(xtkEarns));
    }

    /// @notice Tells the current borrow rate
    /// @dev If the utilization rate is less or equal than the optimal utilization rate, a model using the slope 1 is used.
    /// @dev Otherwise the model uses the slope 2. This slope 2 is moved to the origin in order to avoid problems by the uint type
    /// @return (uint256) Borrow rate value multiplied by FACTOR
    function borrowRate() public view returns (uint256) {
        uint256 uRate = utilizationRate();
        if (uRate <= optimalUtilizationRate) return slope1.mul(uRate).div(FACTOR).add(baseBorrowRate);
        return
            baseBorrowRate.add(
                slope1.mul(optimalUtilizationRate).add(slope2.mul(uRate.sub(optimalUtilizationRate))).div(FACTOR)
            );
    }

    /// @notice Tells the current borrow rate per block
    /// @dev The borrow rateis divided by an estimated amount of blocks per year to help computing indexes
    /// @return (uint256) Borrow rate per block value multiplied by FACTOR
    function borrowRatePerBlock() public view returns (uint256) {
        return borrowRate().div(BLOCKS_PER_YEAR);
    }

    /// @notice Anyone can know how much a borrower owes to the Liquidity Pool
    /// @dev The value is updated via the ratio between the current borrow index and the borrower's borrow index
    /// @dev The return value has 18 decimals
    /// @param _borrower (address) Borrower's address
    /// @return (uint256) How much a Borrower owes to the Liquidity Pool in USDC terms
    function updatedBorrowBy(address _borrower) public view override returns (uint256) {
        Borrow storage borrowerBorrow = borrows[_borrower];
        uint256 borrowAmount = borrowerBorrow.amount;

        if (borrowAmount == 0) return 0;
        (uint256 newBorrowIndex, ) = calculateBorrowInformationAtBlock(block.number);

        return borrowAmount.mul(newBorrowIndex).div(borrowerBorrow.interestIndex);
    }

    /// @notice Accrues the protocol interests
    /// @dev This function updates the borrow index and the total borrows values
    function accrueInterest() private {
        reserves = calculateReservesInformation(block.number);
        xtkEarns = calculateXtkEarnings(block.number);
        (borrowIndex, totalBorrows) = calculateBorrowInformationAtBlock(block.number);
        accrualBlock = block.number;
    }

    /// @notice Calculates updated borrow information at a given block
    /// @dev Computes the borrow index and total borrows depending on how many blocks have passed since latest interaction
    /// @param _block (uint256) Block to look against
    /// @return newBorrowIndex (uint256) Updated borrow index
    /// @return newTotalBorrow (uint256) Updated total borrows
    function calculateBorrowInformationAtBlock(uint256 _block)
        private
        view
        returns (uint256 newBorrowIndex, uint256 newTotalBorrow)
    {
        if (_block <= accrualBlock) return (borrowIndex, totalBorrows);
        if (totalBorrows == 0) return (borrowIndex, totalBorrows);

        uint256 deltaBlock = _block.sub(accrualBlock);
        uint256 interestFactor = borrowRatePerBlock().mul(deltaBlock).add(FACTOR);

        newBorrowIndex = borrowIndex.mul(interestFactor).div(FACTOR);
        newTotalBorrow = totalBorrows.mul(interestFactor).div(FACTOR);
    }

    /// @notice Calculates updated reserves information at a given block
    /// @dev Computes the accrued reserves value
    /// @param _block (uint256) Block to look against
    /// @return newReserves (uint256) Updated reserves value
    function calculateReservesInformation(uint256 _block) private view returns (uint256 newReserves) {
        if (_block <= accrualBlock) return reserves;

        uint256 deltaBlock = _block.sub(accrualBlock);
        uint256 reservesInterest = borrowRatePerBlock()
            .mul(deltaBlock)
            .mul(reserveFactor)
            .div(FACTOR)
            .mul(totalBorrows)
            .div(FACTOR);
        newReserves = reserves.add(reservesInterest);
    }

    /// @notice Calculates updated protocol earning information at a given block
    /// @dev Computes the accrued protocol earning value
    /// @param _block (uint256) Block to look against
    /// @return newXtkEarnings (uint256) Updated protocol earning value
    function calculateXtkEarnings(uint256 _block) private view returns (uint256 newXtkEarnings) {
        if (_block <= accrualBlock) return xtkEarns;

        uint256 deltaBlock = _block.sub(accrualBlock);
        uint256 xtkInterest = borrowRatePerBlock().mul(deltaBlock).mul(xtkFeeFactor).div(FACTOR).mul(totalBorrows).div(
            FACTOR
        );
        newXtkEarnings = xtkEarns.add(xtkInterest);
    }

    /// @notice Lenders can supply as much USDC as they want into the Liquidity Pool
    /// @dev This will mint LPT upon updated LPT value
    /// @dev The amount param accepts the original token decimals, in case of USDC it has 6 decimals
    /// @param _amount (uint256) Amount of USDC to be supplied into the Liquidity Pool
    function supply(uint256 _amount) external notLocked(msg.sender) nonReentrant whenNotPaused {
        require(liquidityPoolToken != address(0), "LPT token has not set yet");
        lock(msg.sender);
        accrueInterest();
        uint256 currentLptPrice = getLPTValue();
        IERC20Upgradeable(stableCoin).safeTransferFrom(msg.sender, address(this), _amount);
        uint256 lptToMint = _amount.mul(currentLptPrice).div(FACTOR);
        ILPT(liquidityPoolToken).mint(msg.sender, lptToMint);

        emit SupplyEvent(msg.sender, _amount, lptToMint);
    }

    /// @notice Lenders can exchange their LPT for USDC upon interest earned by the protocol
    /// @dev This will burn LPT in exchange for USDC
    /// @dev The LPT has the same decimals as USDC, so the param accepts 6 decimals
    /// @param _lptAmount (uint256) Amount of LPT to be burned
    function withdraw(uint256 _lptAmount) external notLocked(msg.sender) nonReentrant whenNotPaused {
        lock(msg.sender);
        accrueInterest();
        uint256 currentLptPrice = getLPTValue();
        uint256 currentCash = convertFrom18(currentLiquidity());
        uint256 usdcAmount = _lptAmount.mul(FACTOR).div(currentLptPrice);
        uint256 finalAmount = usdcAmount;
        uint256 finalLPTAmount = _lptAmount;
        if (currentCash < usdcAmount) {
            finalAmount = currentCash;
            // rounding to the protocol
            finalLPTAmount = (finalAmount.mul(currentLptPrice).sub(1)).div(FACTOR).add(1);
        }
        ILPT(liquidityPoolToken).burnFrom(msg.sender, finalLPTAmount);
        IERC20Upgradeable(stableCoin).safeTransfer(msg.sender, finalAmount);

        emit WithdrawEvent(msg.sender, _lptAmount, finalAmount);
    }

    /// @notice Borrowers can borrow USDC having their collaterals as guarantee
    /// @dev Borrowers can only borrow the minimum loan value or more in order to avoid gas fee costs that are not worthy to pay for
    /// @dev Borrowers can only borrow the specified amount if they have enough collateral. Despite they can borrow 100% of that,
    /// @dev it is recommended to borrow up to 80% of that value
    /// @dev The amount param accepts the original token decimals, in case of USDC it has 6 decimals
    /// @param _amount (uint256) Borrow amount
    function borrow(uint256 _amount) external notLocked(msg.sender) nonReentrant whenNotPaused {
        lock(msg.sender);
        accrueInterest();

        Borrow storage borrowerBorrow = borrows[msg.sender];
        uint256 updatedBorrowAmount = updatedBorrowBy(msg.sender);

        uint256 parsedAmount = convertTo18(_amount);
        updatedBorrowAmount = updatedBorrowAmount.add(parsedAmount);
        require(updatedBorrowAmount >= minimumLoanValue, "You must borrow the minimum loan value or more");

        uint256 healthRatio = IComptroller(comptroller).borrowingCapacity(msg.sender).mul(1e2).div(updatedBorrowAmount);

        require(healthRatio >= minBorrowHealthRatio, "You do not have enough collateral to borrow this amount");

        borrowerBorrow.amount = updatedBorrowAmount;
        borrowerBorrow.interestIndex = borrowIndex;
        borrowerBorrow.borrowedAtBlock = block.number;
        totalBorrows = totalBorrows.add(parsedAmount);

        IERC20Upgradeable(stableCoin).safeTransfer(msg.sender, _amount);

        emit BorrowEvent(msg.sender, _amount, updatedBorrowAmount);
    }

    /// @notice Borrowers can pay a portion of their debt
    /// @dev The borrower has to have a borrow active amount
    /// @dev If the borrower pays more than he owes, the payment is done by the whole debt and not all of the amount is used
    /// @dev The amount param accepts the original token decimals, in case of USDC it has 6 decimals
    /// @param _amount (uint256) Borrow amount
    function repay(uint256 _amount) public notLocked(msg.sender) nonReentrant whenNotPaused {
        repayInternal(_amount);
    }

    /// @notice Borrowers can pay a portion of their debt
    /// @dev The borrower has to have a borrow active amount
    /// @dev If the borrower pays more than he owes, the payment is done by the whole debt and not all of the amount is used
    /// @dev Only available to flash loan whitelist addresses to avoid the reentrancy guard
    /// @dev The amount param accepts the original token decimals, in case of USDC it has 6 decimals
    /// @param _amount (uint256) Borrow amount
    function whitelistRepay(uint256 _amount) external notLocked(msg.sender) whenNotPaused {
        require(flashBorrowers[msg.sender], "The sender is not whitelisted");

        repayInternal(_amount);
    }

    /// @notice Borrowers can pay all of their debt
    /// @dev The borrower can not pay in the same block that they borrowedfrom. This is to avoid attacks of other smart contracts
    /// @dev The borrower has to have a borrow active amount
    function payAll() external {
        repay(convertFrom18(uint256(-1)));
    }

    /// @notice Borrowers can pay a portion of their debt
    /// @dev The borrower has to have a borrow active amount
    /// @dev If the borrower pays more than he owes, the payment is done by the whole debt and not all of the amount is used
    /// @dev The amount param accepts the original token decimals, in case of USDC it has 6 decimals
    /// @param _amount (uint256) Borrow amount
    function repayInternal(uint256 _amount) private {
        lock(msg.sender);
        accrueInterest();
        uint256 parsedAmount = convertTo18(_amount);
        Borrow storage borrowerBorrow = borrows[msg.sender];

        uint256 updatedBorrowAmount = updatedBorrowBy(msg.sender);
        borrowerBorrow.interestIndex = borrowIndex;

        require(updatedBorrowAmount > 0, "You have no borrows to be repaid");

        if (parsedAmount > updatedBorrowAmount) parsedAmount = updatedBorrowAmount;

        updatedBorrowAmount = updatedBorrowAmount.sub(parsedAmount);
        require(
            updatedBorrowAmount == 0 || updatedBorrowAmount >= minimumLoanValue,
            "You must borrow the minimum loan value or more"
        );

        borrowerBorrow.amount = updatedBorrowAmount;
        totalBorrows = totalBorrows.sub(parsedAmount);

        IERC20Upgradeable(stableCoin).safeTransferFrom(msg.sender, address(this), convertFrom18(parsedAmount));

        emit RepayEvent(msg.sender, _amount, updatedBorrowAmount);
    }

    /// @notice Liquidator can liquidate a portion of a loan on behalf of a borrower
    /// @dev The protocol decides first the more stable markets, then the more volatile ones to reward the liquidator
    /// @param _borrower (address) Borrower's address
    /// @dev The amount param accepts the original token decimals, in case of USDC it has 6 decimals
    /// @param _amount (address) Amount to be liquidated
    function liquidate(address _borrower, uint256 _amount) external whenNotPaused {
        address[] memory emptyMarkets = new address[](0);
        liquidateInternal(_borrower, _amount, emptyMarkets);

        emit LiquidateEvent(_borrower, msg.sender, _amount, emptyMarkets);
    }

    /// @notice Liquidator can liquidate a portion of a loan on behalf of a borrower
    /// @dev The liquidator decides the order of markets they want to get collaterals from
    /// @param _borrower (address) Borrower's address
    /// @param _amount (address) Amount to be liquidated
    /// @dev The amount param accepts the original token decimals, in case of USDC it has 6 decimals
    /// @param _markets (address) Peferred markets addresses
    function liquidateWithPreference(
        address _borrower,
        uint256 _amount,
        address[] memory _markets
    ) external whenNotPaused {
        liquidateInternal(_borrower, _amount, _markets);

        emit LiquidateEvent(_borrower, msg.sender, _amount, _markets);
    }

    /// @notice Internal liquidate function
    /// @dev This is the one performing the liquidation logic
    /// @param _borrower (address) Borrower's address
    /// @param _amount (uint256) Amount to be liquidated
    /// @param _markets (address[] memory) Preferred markets if applies
    function liquidateInternal(
        address _borrower,
        uint256 _amount,
        address[] memory _markets
    ) private {
        accrueInterest();
        require(_borrower != msg.sender, "You are not allowed to liquidate your own debt");
        require(liquidationExempt[_borrower] == false, "Borrower is exempt from liquidation");

        uint256 parsedAmount = convertTo18(_amount);
        Borrow storage borrowerBorrow = borrows[_borrower];
        require(borrowerBorrow.amount > 0, "You have no borrows to be repaid");

        uint256 updatedBorrowAmount = updatedBorrowBy(_borrower);
        borrowerBorrow.interestIndex = borrowIndex;

        require(
            IComptroller(comptroller).getHealthRatio(_borrower) < 100,
            "You can not liquidate this loan because it has a good health factor"
        );

        if (parsedAmount > updatedBorrowAmount) parsedAmount = updatedBorrowAmount;

        borrowerBorrow.amount = updatedBorrowAmount.sub(parsedAmount);
        totalBorrows = totalBorrows.sub(parsedAmount);

        IERC20Upgradeable(stableCoin).safeTransferFrom(msg.sender, address(this), convertFrom18(parsedAmount));

        uint256 amount = parsedAmount.mul(FACTOR).div(uint256(1e18).sub(liquidityPenaltyFactor));

        if (_markets.length == 0) IComptroller(comptroller).sendCollateralToLiquidator(msg.sender, _borrower, amount);
        else
            IComptroller(comptroller).sendCollateralToLiquidatorWithPreference(msg.sender, _borrower, amount, _markets);

        // If a debt is under the max liquidation threshold, 
        // the entirety of the debt can be liquidated by the owner or manager
        // Otherwise, the liquidation cannot be more than the max liquidation health ratio
        if (updatedBorrowAmount >= minimumLoanValue || 
            (msg.sender != owner() && !xTokenManager.isManager(msg.sender, address(this)))) {
            // Limit liquidation amount to the max liquidation borrower health ratio
            uint256 healthRatio = IComptroller(comptroller).getHealthRatio(_borrower);
            require(
                healthRatio <= maxLiquidationHealthRatio,
                "Cannot liquidate more than up to the max % liquidation health ratio"
            );
        }
    }

    /// @notice Allows whitelisted smartcontracts to access the liquidity of the pool within one transaction
    /// @dev The amount param accepts the original token decimals, in case of USDC it has 6 decimals
    /// @param _receiver (address) The address of the contract receiving the funds. The receiver should implement the IFlashLoanReceiver interface.
    /// @param _amount (uint256) The amount requested for this flashloan
    /// @param _params (bytes[] memory) The arbitrary data pass to the receiver contract
    function flashLoan(
        address _receiver,
        uint256 _amount,
        bytes memory _params
    ) external override notLocked(msg.sender) nonReentrant whenNotPaused {
        lock(msg.sender);
        require(flashBorrowers[msg.sender], "The sender is not whitelisted");

        accrueInterest();
        uint256 availableLiquidityBefore = IERC20Upgradeable(stableCoin).balanceOf(address(this));
        require(availableLiquidityBefore >= _amount, "There is not enough liquidity available to borrow");

        uint256 amountFee;
        if (flashLoanFeeFactor > 0) {
            amountFee = _amount.mul(flashLoanFeeFactor).div(FACTOR);
            require(amountFee > 0, "The requested amount is too small for a flashLoan.");
        }

        IFlashLoanReceiver receiver = IFlashLoanReceiver(_receiver);
        IERC20Upgradeable(stableCoin).safeTransfer(_receiver, _amount);
        receiver.executeOperation(_amount, amountFee, _params);
        IERC20Upgradeable(stableCoin).safeTransferFrom(_receiver, address(this), _amount.add(amountFee));

        emit FlashLoan(_receiver, _amount, amountFee);
    }

    /// @notice Only owners can withdraw protocol earnings
    /// @param _recipient (address) Owners specify where to send the earnings
    function withdrawFees(address _recipient) external onlyOwner {
        require(_recipient != address(0));
        uint256 feeAmount = convertFrom18(xtkEarns);
        xtkEarns = 0;
        IERC20Upgradeable(stableCoin).safeTransfer(_recipient, feeAmount);
        emit WithdrawFee(_recipient, feeAmount);
    }

    /// @notice Owners can determine the LPT address
    /// @param _liquidityPoolToken (address) LPT address
    function setLiquidityPoolToken(address _liquidityPoolToken) external onlyOwner {
        require(_liquidityPoolToken != address(0));
        liquidityPoolToken = _liquidityPoolToken;
        emit UpdateLiquidityPoolToken(_liquidityPoolToken);
    }

    /// @notice Owners can determine the Comptroller address
    /// @param _comptroller (address) Comptroller address
    function setComptroller(address _comptroller) external onlyOwner {
        comptroller = _comptroller;
        emit UpdateComptroller(_comptroller);
    }

    function setxTokenManager(IxTokenManager _manager) external onlyOwner {
        require(address(xTokenManager) == address(0), "Cannot set manager twice");
        xTokenManager = _manager;
    }

    /// @notice Owners can determine the interest model variables
    /// @dev This parameters must be entered as percentages. Ex 35 is meant to be understood as 35%
    /// @param _optimalUtilizationRate (uint256) Optimal utilization rate
    /// @param _baseBorrowRate (uint256) Base borrow rate
    /// @param _slope1 (uint256) Slope 1
    /// @param _slope2 (uint256) Slope 2
    function setInterestModelParameters(
        uint256 _optimalUtilizationRate,
        uint256 _baseBorrowRate,
        uint256 _slope1,
        uint256 _slope2
    ) external onlyOwner {
        accrueInterest();

        optimalUtilizationRate = _optimalUtilizationRate.mul(RATIOS);
        baseBorrowRate = _baseBorrowRate.mul(RATIOS);
        slope1 = _slope1.mul(RATIOS);
        slope2 = _slope2.mul(RATIOS);

        emit UpdateInterestModelParameters(_optimalUtilizationRate, _baseBorrowRate, _slope1, _slope2);
    }

    /// @notice Owners can determine the reserve factor value
    /// @dev This parameter must be entered as percentage. Ex 35 is meant to be understood as 35%
    /// @param _reserveFactor (uint256) Reserve factor
    function setReserveFactor(uint256 _reserveFactor) external onlyOwner {
        require(_reserveFactor <= 15, "The reserve factor should be equal or less than 15%");
        accrueInterest();
        reserveFactor = _reserveFactor.mul(RATIOS);
        emit UpdateReserveFeeFactor(_reserveFactor);
    }

    /// @notice Owners can determine the protocol earning factor value
    /// @dev This parameter must be entered as percentage. Ex 35 is meant to be understood as 35%
    /// @param _xtkFeeFactor (uint256) Protocol earning factor
    function setXtkFeeFactor(uint256 _xtkFeeFactor) external onlyOwner {
        require(_xtkFeeFactor <= 15, "The reserve factor should be equal or less than 15%");
        accrueInterest();
        xtkFeeFactor = _xtkFeeFactor.mul(RATIOS);
        emit UpdateXtkFeeFactor(_xtkFeeFactor);
    }

    /// @notice Owners can determine the protocol earning factor value
    /// @param _lptBaseValue (uint256) Liquidity Pool Token Base Value
    function setLPTBaseValue(uint256 _lptBaseValue) external onlyOwner {
        lptBaseValue = _lptBaseValue;
        emit UpdateLPTBaseValue(_lptBaseValue);
    }

    /// @notice Owners can determine the minimum loan value
    /// @param _minimumLoanValue (uint256) Minimum loan value
    function setMinimumLoanValue(uint256 _minimumLoanValue) external onlyOwner {
        minimumLoanValue = _minimumLoanValue;
        emit UpdateMinimumLoanValue(_minimumLoanValue);
    }

    /// @notice Owners can determine the liquidation penalty factor value
    /// @dev This parameter must be entered as percentage. Ex 35 is meant to be understood as 35%
    /// @param _liquidityPenaltyFactor (uint256) Liquidation penalty factor
    function setLiquidationPenaltyFactor(uint256 _liquidityPenaltyFactor) external onlyOwner {
        liquidityPenaltyFactor = _liquidityPenaltyFactor.mul(RATIOS);
        emit UpdateLiquidationPenaltyFactor(_liquidityPenaltyFactor);
    }

    /// @notice Owners can determine the maximum liquidation health ratio
    /// @notice Liquidations pushing borrower's health ratio above this percentage are not allowed
    /// @dev This parameter must be entered as percentage. Ex 150 is meant to be understood as 150%
    /// @param _maxLiquidationHealthRatio (uint256) Max liquidation health ratio
    function setMaxLiquidationHealthRatio(uint256 _maxLiquidationHealthRatio) external onlyOwner {
        require(maxLiquidationHealthRatio >= 110 && maxLiquidationHealthRatio <= 150);
        maxLiquidationHealthRatio = _maxLiquidationHealthRatio;
    }

    /// @notice Owners can determine the minimum borrow health ratio
    /// @notice Borrows pushing the health ratio below this percentage are not allowed
    /// @dev This parameter must be entered as percentage. Ex 150 is meant to be understood as 150%
    /// @param _minBorrowHealthRatio (uint256) Min borrow health ratio
    function setMinBorrowHealthRatio(uint256 _minBorrowHealthRatio) external onlyOwner {
        require(_minBorrowHealthRatio >= 105 && _minBorrowHealthRatio <= 150);
        minBorrowHealthRatio = _minBorrowHealthRatio;
    }

    /// @dev Exempts an address from liquidation
    /// @param xAsset The address to exempt
    function exemptFromLiquidation(address xAsset) external onlyOwner {
        liquidationExempt[xAsset] = true;
    }

    /// @dev Removes exemption for an address from liquidation
    /// @param xAsset The address to remove exemption
    function removeLiquidationExemption(address xAsset) external onlyOwner {
        liquidationExempt[xAsset] = false;
    }

    /// @dev Exempts an address from blocklock
    /// @param lockAddress The address to exempt
    function exemptFromBlockLock(address lockAddress) external onlyOwner {
        _exemptFromBlockLock(lockAddress);
    }

    /// @dev Removes exemption for an address from blocklock
    /// @param lockAddress The address to remove exemption
    function removeBlockLockExemption(address lockAddress) external onlyOwner {
        _removeBlockLockExemption(lockAddress);
    }

    /// @notice Owners can determine the flash loan fee factor
    /// @param _fee (uint256) FlashLoan fee factor (1e18 means 100%)
    function setFlashLoanFeeFactor(uint256 _fee) external onlyOwner {
        flashLoanFeeFactor = _fee;
    }

    /// @notice Owners add xAsset address to the flashloan whitelist
    /// @param _xAsset (address) The address to whitelist
    function addFlashBorrower(address _xAsset) external onlyOwner {
        flashBorrowers[_xAsset] = true;
    }

    /// @notice Owners remove xAsset address from the flashloan whitelist
    /// @param _xAsset (address) The address not to whitelist
    function removeFlashBorrower(address _xAsset) external onlyOwner {
        flashBorrowers[_xAsset] = false;
    }

    /// @notice Owner function: pause all user actions
    function pauseContract() external onlyOwnerOrManager {
        _pause();
    }

    /// @notice Owner function: unpause
    function unpauseContract() external onlyOwnerOrManager {
        _unpause();
    }

    /// @dev Convert to 18 decimals from stable token defined decimals.
    function convertTo18(uint256 _amount) private view returns (uint256) {
        return _amount.mul(stableCoinDecimalMultiplier);
    }

    /// @dev Convert from 18 decimals to stable token defined decimals.
    function convertFrom18(uint256 _amount) private view returns (uint256) {
        return _amount.div(stableCoinDecimalMultiplier);
    }

    /// @notice Optmial utilization rate
    /// @dev This parameter must be understood as a percentage. Ex 35 is meant to be understood as 35%
    /// @return (uint256) Optimal utilization rate
    function getOptimalUtilizationRate() external view returns (uint256) {
        return optimalUtilizationRate.div(RATIOS);
    }

    /// @notice Base borrow rate
    /// @dev This parameter must be understood as a percentage. Ex 35 is meant to be understood as 35%
    /// @return (uint256) Base borrow rate
    function getBaseBorrowRate() external view returns (uint256) {
        return baseBorrowRate.div(RATIOS);
    }

    /// @notice Slope 1
    /// @dev This parameter must be understood as a percentage. Ex 35 is meant to be understood as 35%
    /// @return (uint256) Slope 1
    function getSlope1() external view returns (uint256) {
        return slope1.div(RATIOS);
    }

    /// @notice Slope 2
    /// @dev This parameter must be understood as a percentage. Ex 35 is meant to be understood as 35%
    /// @return (uint256) Slope 2
    function getSlope2() external view returns (uint256) {
        return slope2.div(RATIOS);
    }

    /// @notice Reserve factor
    /// @dev This parameter must be understood as a percentage. Ex 35 is meant to be understood as 35%
    /// @return (uint256) Reserve factor
    function getReserveFactor() external view returns (uint256) {
        return reserveFactor.div(RATIOS);
    }

    /// @notice Protocol earnings factor
    /// @dev This parameter must be understood as a percentage. Ex 35 is meant to be understood as 35%
    /// @return (uint256) Protocol earnings factor
    function getXtkFeeFactor() external view returns (uint256) {
        return xtkFeeFactor.div(RATIOS);
    }

    /// @notice Flashloan fee factor
    /// @return (uint256) Flashloan fee factor
    function getFlashLoanFeeFactor() external view returns (uint256) {
        return flashLoanFeeFactor;
    }

    /// @notice LPT Base Value
    /// @return (uint256) LPT Base Value
    function getLPTBaseValue() external view returns (uint256) {
        return lptBaseValue;
    }

    /// @notice Gets the updated value of the liquidity pool token based on activity
    /// @return (uint256) Current LPT value(1e18)
    function getLPTValue() public view returns (uint256) {
        uint256 totalSupplyLiquidityPool = convertTo18(IERC20Upgradeable(liquidityPoolToken).totalSupply());
        if (totalSupplyLiquidityPool == 0) return lptBaseValue;
        return
            totalSupplyLiquidityPool.mul(FACTOR).div(currentLiquidity().add(totalBorrows).sub(reserves).sub(xtkEarns));
    }

    /// @notice Minimum Loan Value
    /// @return (uint256) Minimum Loan Value
    function getMinimumLoanValue() external view returns (uint256) {
        return minimumLoanValue;
    }

    /// @notice Liquidation Penalty factor
    /// @dev This parameter must be understood as a percentage. Ex 35 is meant to be understood as 35%
    /// @return (uint256) Liquidation Penalty factor
    function getLiquidationPenaltyFactor() external view returns (uint256) {
        return liquidityPenaltyFactor.div(RATIOS);
    }
}

