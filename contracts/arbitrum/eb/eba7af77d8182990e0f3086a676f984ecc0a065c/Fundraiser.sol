// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./SafeERC20.sol";
import "./Ownable.sol";

import "./AggregatorV3Interface.sol";

import "./Token.sol";

import "./console.sol";

// IMPORTANT: This contract needs to be set as the minter of the DaikokuDAO token

contract Fundraiser is Ownable {
    using SafeERC20 for IERC20;

    uint256 private constant DECIMALS = 1e8;

    // Addresses of tokens
    DaikokuDAO public immutable token;
    IERC20 public immutable usdc;

    // The address of the Chainlink price feed contract for ETH/USD
    AggregatorV3Interface internal immutable priceFeedEth;
    AggregatorV3Interface internal immutable priceFeedUsdc;

    // Treasury wallet
    address public treasury;
    uint256 public totalTokensTreasury;
    uint256 public unclaimedTokensTreasury;

    // Management wallets
    address public management1;
    address public management2;
    uint256 public totalTokensManagement;
    uint256 public unclaimedTokensManagement1;
    uint256 public unclaimedTokensManagement2;

    // Withdrawal
    uint256 private constant CLIFF_DURATION = 365 days;
    uint256 private constant WITHDRAWAL_PERIOD_DURATION = 365 days;
    uint256 public cliffTime;

    mapping(address => uint256) public contributions; // In USDC
    mapping(address => uint256) public allocations; // In DKKU

    uint256 private numFundraises = 0;

    struct Fundraise {
	uint256 tokenPriceUSDC;
	uint256 managementPercentage;
	uint256 treasuryPercentage;
	uint256 earlyDiscountInitPercentage; // Use DECIMALS (7 * DECIMALS / 100 --> 2%)
	uint256 sizeDiscountRateCapPercentage; // Use DECIMALS
	uint256 sizeDiscountContributionCapUsdc; // 6 decimals
        uint256 tokensUserAllocated;
	uint256 startTime;
	uint256 endTime;
    }

    Fundraise[] public fundraises;

    uint256 public tokensClaimed;


    // Events

    /// @dev Emitted when a contribution is received.
    event ContributionReceived(address indexed contributor, uint256 contribution, uint256 allocation);
    /// @dev Emitted when tokens are claimed.
    event TokensClaimed(address indexed claimer, uint256 amount);

    /// @notice Constructs the Fundraiser contract.
    /// @param _token The address of the DaikokuDAO token.
    /// @param _usdc The address of the USDC token.
    /// @param _chainlinkEth The address of the Chainlink ETH/USD price feed contract.
    /// @param _chainlinkUsdc The address of the Chainlink USDC/USD price feed contract.
    /// @param _treasury The address of the treasury wallet.
    /// @param _management1 The address of the first management wallet.
    /// @param _management2 The address of the second management wallet.
    constructor(
        DaikokuDAO _token,
	IERC20 _usdc,
	address _chainlinkEth,
	address _chainlinkUsdc,
	address _treasury,
        address _management1,
        address _management2
    ) {
	require(address(_token) != address(0), "Token address is zero");
	require(address(_usdc) != address(0), "USDC address is zero");
	require(_chainlinkEth != address(0), "Chainlink ETH address == 0");
	require(_chainlinkUsdc != address(0), "Chainlink USDC address == 0");
	require(_treasury != address(0), "Treasury address is zero");
	require(_management1 != address(0), "Management1 address is zero");
	require(_management2 != address(0), "Management2 address is zero");

        token = _token;
	usdc = _usdc;
	// Set the address of the Chainlink price feed contract for ETH/USD
        priceFeedEth = AggregatorV3Interface(_chainlinkEth);
	priceFeedUsdc = AggregatorV3Interface(_chainlinkUsdc);

	treasury = _treasury;
        management1 = _management1;
        management2 = _management2;
    }

    /// @notice Sets treasury and management addresses
    /// @param _treasury The address of the new treasury wallet.
    /// @param _management1 The address of the new first management wallet.
    /// @param _management2 The address of the new second management wallet.
    function setAddresses(address _treasury, address _management1, address _management2) external onlyOwner {
	require(_treasury != address(0), "New treasury address is zero");
	require(_management1 != address(0), "New management1 address is zero");
	require(_management2 != address(0), "New management2 address is zero");

	treasury = _treasury;
	management1 = _management1;
	management2 = _management2;
    }

    //
    // Fundraise
    //

    /// @notice Function to start a fundraise
    /// @param tokenPriceUSDC The price of the token of USDC during this fundraise. USES 8 DECIMALS.
    /// @param managementPercentage The percentage of funds to be allocated to management.
    /// @param treasuryPercentage The percentage of funds to be allocated to treasury.
    /// @param earlyDiscountInitPercentage The initial discount percentage for early contributions (decays over time).
    /// @param sizeDiscountRateCapPercentage The cap on discount rate for the size of contribution.
    /// @param sizeDiscountContributionCapUsdc The cap on the size of contribution for the discount.
    function start(uint256 tokenPriceUSDC,
		   uint256 managementPercentage,
		   uint256 treasuryPercentage,
		   uint256 earlyDiscountInitPercentage,
		   uint256 sizeDiscountRateCapPercentage,
		   uint256 sizeDiscountContributionCapUsdc,
		   uint256 fundraiseDuration) external onlyOwner {
	require(tokenPriceUSDC > 0, "Price must be greater than 0");
	require(managementPercentage <= 15 * DECIMALS / 100, "Management % exceeds limit");
	require(treasuryPercentage <= 45 * DECIMALS / 100, "Treasury % exceeds limit");
	require(fundraiseDuration >= 1 hours && fundraiseDuration <= 2 weeks, "Should last < 1hour && > 2week");
	require(earlyDiscountInitPercentage <= 30 * DECIMALS / 100, "Early discount > 30%");
	require(sizeDiscountRateCapPercentage <= 30 * DECIMALS / 100, "Size discount > 30%");
	require(numFundraises < 4, "Max fundraises exceeded");

	Fundraise memory fundraise;
	if (fundraises.length > 0) {
	    require(block.timestamp > fundraises[fundraises.length - 1].endTime, "There is an active fundraise");
	}
	fundraise = Fundraise(tokenPriceUSDC,
			      managementPercentage,
			      treasuryPercentage,
			      earlyDiscountInitPercentage,
			      sizeDiscountRateCapPercentage,
			      sizeDiscountContributionCapUsdc,
			      0,
			      block.timestamp,
			      block.timestamp + fundraiseDuration);
	fundraises.push(fundraise);

	if (cliffTime == 0) {
	    cliffTime = block.timestamp + CLIFF_DURATION;
	}
	++numFundraises;
    }

    /// @dev Internal function to retrieve the active fundraise.
    /// This function requires there to be at least one active fundraise.
    /// @return activeFundraise The active fundraise.
    function getActiveInternal() internal view returns (Fundraise storage) {
	require(fundraises.length > 0, "No active fundraise");
	Fundraise storage activeFundraise = fundraises[fundraises.length - 1];
	require(activeFundraise.endTime > block.timestamp, "No active fundraise");
	return activeFundraise;
    }

    /// @notice Function to retrieve the active fundraise.
    /// This function returns a copy of the active fundraise.
    /// @return activeFundraiseCopy A copy of the active fundraise.
    function getActive() public view returns (Fundraise memory) {
	Fundraise storage activeFundraise = getActiveInternal();
	Fundraise memory activeFundraiseCopy = Fundraise({
	    tokenPriceUSDC: activeFundraise.tokenPriceUSDC,
	    managementPercentage: activeFundraise.managementPercentage,
	    treasuryPercentage: activeFundraise.treasuryPercentage,
	    earlyDiscountInitPercentage: activeFundraise.earlyDiscountInitPercentage,
	    sizeDiscountRateCapPercentage: activeFundraise.sizeDiscountRateCapPercentage,
	    sizeDiscountContributionCapUsdc: activeFundraise.sizeDiscountContributionCapUsdc,
	    tokensUserAllocated: activeFundraise.tokensUserAllocated,
	    startTime: activeFundraise.startTime,
	    endTime: activeFundraise.endTime
	    });
	return activeFundraiseCopy;
    }

    /// @notice Function to get the status of the current fundraise and the time left.
    /// @return status The status of the fundraise, and timeLeft The remaining time for the fundraise.
    function getStatus() public view returns (string memory status, uint256 timeLeft) {
	if (fundraises.length == 0) {
            status = "NOT ACTIVE";
	    return (status, timeLeft);
	}

	Fundraise storage fundraise = fundraises[fundraises.length - 1];

        if (block.timestamp >= fundraise.endTime) {
            status = "NOT ACTIVE";
        } else {
            status = "ACTIVE";
            timeLeft = fundraise.endTime - block.timestamp;
        }
    }

    /// @notice Function to get the price per token amount.
    /// @param amountUSDC6d The USDC amount. USES 6 DECIMALS.
    /// @return price The price per token amount. USES 8 DECIMALS.
    function getPricePerTokenAmount(uint256 amountUSDC6d) public view returns (uint256) {
	Fundraise storage fundraise = getActiveInternal();

	uint256 timePassedSinceInit = block.timestamp - fundraise.startTime;

	// Calculate the early discount
	uint256 fundraiseDuration = fundraise.endTime - fundraise.startTime;
	uint256 fundraiseProgress = DECIMALS - (timePassedSinceInit * DECIMALS / fundraiseDuration); // Progress since beginning
	uint256 earlyDiscount = fundraise.earlyDiscountInitPercentage  * fundraiseProgress / DECIMALS;

	// Calculate the size discount
	uint256 sizeDiscount = 0;
	if (contributions[msg.sender] + amountUSDC6d <= fundraise.sizeDiscountContributionCapUsdc) {
	    uint256 sizePercent = (contributions[msg.sender] + amountUSDC6d) * DECIMALS / fundraise.sizeDiscountContributionCapUsdc;
	    sizeDiscount = sizePercent * fundraise.sizeDiscountRateCapPercentage / DECIMALS;
	} else {
	    sizeDiscount = fundraise.sizeDiscountRateCapPercentage; // Cap to size discount
	}

	// Calculate the price
	uint256 price = fundraise.tokenPriceUSDC * (DECIMALS - earlyDiscount - sizeDiscount) / DECIMALS;
	/* console.log("Discount %s", DECIMALS - earlyDiscount - sizeDiscount); */
	/* console.log("Discounts (with 8 decimals): %s %s:", sizeDiscount , earlyDiscount); */
	/* console.log("Price %s", price); */

	return price;
    }

    /// @notice Function to deposit ETH into the contract.
    /// An error is thrown if the sender does not include any ETH in the transaction.
    function depositETH() external payable {
	require(msg.value > 0, "Must send ETH");
	Fundraise storage fundraise = getActiveInternal();

        // Get the latest round data from the price feed
	(uint80 roundID, int price,, uint256 timestamp, uint80 answeredInRound) = priceFeedEth.latestRoundData();
	require(price >= 100*1e8 && price <= 200000*1e8, "ETH price out of bounds"); // Price of ETH must be between 100 USDC and 200k USD
	require(answeredInRound >= roundID, "Stale price");
	require(timestamp != 0, "Round not complete");

        // Convert the price to a uint256 and the ETH amount to USD
        uint256 usdPrice = uint256(price);
        uint256 usdAmount6d = msg.value * usdPrice / 1e20; // 18 + 8 - *20* = 6 decimals

	// console.log("RECEIVED ETH %s", msg.value);

	allocateDeposit(fundraise, usdAmount6d);
    }

    /// @notice Function to deposit USDC into the contract.
    /// An error is thrown if the USDC amount is 0.
    /// @param usdcAmount6d The amount of USDC to deposit.
    function depositUSDC(uint256 usdcAmount6d) external {
	require(usdcAmount6d > 0, "Must send USDC");
	Fundraise storage fundraise = getActiveInternal();

	// console.log("RECEIVED USD %s", usdcAmount6d);
	(uint80 roundID, int price,, uint256 timestamp, uint80 answeredInRound) = priceFeedUsdc.latestRoundData();
	require(price >= 99*1e6 && price <= 101*1e6, "USDC price out of bounds");
	require(answeredInRound >= roundID, "Stale price");
	require(timestamp != 0, "Round not complete");

	// Convert the price to a uint256 and the USDC amount to USD
        uint256 usdPrice = uint256(price);
        uint256 usdAmount6d = usdcAmount6d * usdPrice / 1e8; // 6 + 8 - *8* = 6 decimals

        // Transfer the USDC from the sender to this contract. Needs approval.
        usdc.safeTransferFrom(msg.sender, address(this), usdAmount6d);

	allocateDeposit(fundraise, usdAmount6d);
    }

    /// @notice Function to allocate a deposit.
    /// The deposit is allocated among the user, the treasury, and management.
    /// @param fundraise The active fundraise.
    /// @param usdAmount6d The amount of USD to allocate. USES 6 DECIMALS (but is not USDC!)
    function allocateDeposit(Fundraise storage fundraise, uint256 usdAmount6d) private {
	uint256 userAllocation = (usdAmount6d * DECIMALS / getPricePerTokenAmount(usdAmount6d)) * 1e12; // Scale the units to 18 decimals

	// console.log("Price per token: %s", getPricePerTokenAmount(usdcAmount6d));

	contributions[msg.sender] += usdAmount6d;
	allocations[msg.sender] += userAllocation;

	uint256 treasuryAllocation = (userAllocation * fundraise.treasuryPercentage) / DECIMALS;
	totalTokensTreasury += treasuryAllocation;
	unclaimedTokensTreasury += treasuryAllocation;

	uint256 managementAllocation = (userAllocation * fundraise.managementPercentage) / DECIMALS;
	uint256 totalPerManagementAddress = managementAllocation / 2;
	// Make sure this way that is divisible by two
	totalTokensManagement += totalPerManagementAddress * 2;
	unclaimedTokensManagement1 += totalPerManagementAddress;
	unclaimedTokensManagement2 += totalPerManagementAddress;

	uint256 totalAllocation = userAllocation + treasuryAllocation + managementAllocation;
	fundraise.tokensUserAllocated += userAllocation;

	// Mint to this contract, since tokens are locked but we want to account for them
	token.mint(address(this), totalAllocation);

	// console.log("Allocations: %s %s %s", userAllocation, managementAllocation, treasuryAllocation);

	emit ContributionReceived(msg.sender, usdAmount6d, userAllocation);
    }

    //
    // Post-fundraise operations
    //

    /// @notice Function to claim tokens when there is no active fundraise.
    /// The sender must have a non-zero token allocation and no fundraise can be active.
    function claim() external {
        require(allocations[msg.sender] > 0, "No tokens available to claim");
	Fundraise storage activeFundraise = fundraises[fundraises.length - 1];
	require(block.timestamp > activeFundraise.endTime, "Cannot claim during fundraise");

	uint256 allocated = allocations[msg.sender];
	tokensClaimed += allocated;
	allocations[msg.sender] = 0; // Mark as claimed
        token.transferWithoutTax(address(this), msg.sender, allocated);

	emit TokensClaimed(msg.sender, allocated);
    }

    /// @notice Function for the treasury to claim its tokens after the fundraise.
    /// The treasury claims its allocation of ETH, USDC, and DKKU tokens.
    function claimTreasury() external onlyOwner {
        // Send ETH to the treasury
        uint256 ethBalance = address(this).balance;
	if (ethBalance > 0) {
	    (bool success1, ) = treasury.call{value: ethBalance}("");
	    require(success1, "ETH transfer failed");
	}

        // Send USDC to the treasury
        uint256 usdcBalance = usdc.balanceOf(address(this));
	if (usdcBalance > 0) {
	    usdc.safeTransfer(treasury, usdcBalance);
	}

        // Send DKKU to the treasury
	if (unclaimedTokensTreasury > 0) {
	    token.transferWithoutTax(address(this), treasury, unclaimedTokensTreasury);
	    unclaimedTokensTreasury = 0;
	}
    }

    /// @notice Function to get the available management tokens for a management address.
    /// The management address must be a valid management address.
    /// @param managementAddress The address of the management wallet.
    /// @return availableTokensToWithdraw The number of tokens the management address can claim.
    function getAvailableManagementTokens(address managementAddress) public view returns (uint256) {
	require(managementAddress == management1 || managementAddress == management2, "Invalid management address");

	uint256 timePassedSinceCliff = block.timestamp > cliffTime ? block.timestamp - cliffTime : 0;

	if (timePassedSinceCliff == 0) {
	    return 0; // No withdrawal available if cliff time not reached
	}

	uint256 timeRatio = timePassedSinceCliff * 1e18 / WITHDRAWAL_PERIOD_DURATION;

	if (timeRatio > 1e18) {
	    timeRatio = 1e18; // Cap the ratio at 100% if more than 2 years have passed
	}

	uint256 remainingTokens = managementAddress == management1 ? unclaimedTokensManagement1 : unclaimedTokensManagement2;

	uint256 totalPerManagementAddress = totalTokensManagement / 2;
	uint256 allowedTokensToWithdraw = totalPerManagementAddress * timeRatio / 1e18;
	uint256 alreadyWithdrawnTokens = totalPerManagementAddress - remainingTokens;
	uint256 availableTokensToWithdraw = allowedTokensToWithdraw > alreadyWithdrawnTokens ? allowedTokensToWithdraw - alreadyWithdrawnTokens : 0;

	return availableTokensToWithdraw;
    }

    /// @notice Function for a management address to claim its tokens when there is no active fundraise.
    /// The sender must be a valid management address and the cliff time must have passed.
    function claimManagement() external {
	require(msg.sender == management1 || msg.sender == management2, "Only for management addresses");
	require(cliffTime > 0 && block.timestamp >= cliffTime, "Cliff time not reached yet");

	uint256 availableTokensToClaim = getAvailableManagementTokens(msg.sender);
	require(availableTokensToClaim > 0, "No tokens available to claim");

	if (msg.sender == management1) {
	    unclaimedTokensManagement1 -= availableTokensToClaim;
	} else {
	    unclaimedTokensManagement2 -= availableTokensToClaim;
	}

	token.transferWithoutTax(address(this), msg.sender, availableTokensToClaim);
    }

    receive() external payable {}
}

