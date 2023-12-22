// SPDX-License-Identifier: GPL-3.0

// Importing required contracts from OpenZeppelin library
import "./IERC20.sol";
import "./Ownable.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";

pragma solidity 0.8.18;

///#invariant unchecked_sum(balances) <= presaleCap;
///#invariant totalSold <= presaleCap;

/**
 * @title SolidSignalPresale
 * @dev Presale fair launch contract for SolidSignalPresale token
 */
contract SolidSignalPresale is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    // Maximum number of tokens to be sold in presale
    uint256 public immutable presaleCap;

    uint256 public minimumPurchaseAmount; //in usdc 6 decimals

    // Price of each token in usdcToken during presale
    uint256 public immutable presalePrice; //18 decimals

    // Total number of tokens sold in signal
    uint256 public totalSold;

    //usdc amount raised
    uint256 public usdcRaised;

    // Flags to indicate if presale is open or closed
    bool public isOpen;
    bool public isClosed;

    // Address of treasury account to receive funds from presale
    address public treasury;

    // Mapping to keep track of token balances for each account during presale
    mapping(address => uint256) balances;

    // usdcToken token contract used for payment during presale
    IERC20 public immutable usdcToken;

    // Event emitted when a successful purchase is made during presale
    event Sell(address _buyer, uint256 _amount);
    event MinimumPurchaseAmountChanged(uint256 _amount);
    event SetTreasury(address _treasury);
    event Start(address startedBy);
    event End(address endedBy);
    event Withdraw(address withdrawnBy, uint256 amount);

    /**
     * @dev Constructor function to initialize contract with required parameters.
     * @param _presaleCap Maximum number of tokens to be sold in presale.
     * @param _usdcToken Address of usdcToken token contract.
     * @param price Price of each token in usdcToken during presale.
     * @param _treasury Address of treasury account to receive funds from presale.
     */
    constructor(
        uint256 _presaleCap,
        uint256 _minimumPurchaseAmount,
        uint256 price,
        address _usdcToken,
        address _treasury
    ) {
        require(
            _treasury != address(0),
            "SolidSignalPresale: Requires a non zero address"
        );
        presaleCap = _presaleCap;
        usdcToken = IERC20(_usdcToken);
        presalePrice = price;
        treasury = _treasury;
        minimumPurchaseAmount = _minimumPurchaseAmount;
    }

    /**
     * @dev Function to buy tokens during presale for self.
     * @param amount Number of tokens to buy.
     */

    /// #if_succeeds {:msg "The buyer has suffient tokens} old(usdcToken.balanceOf[msg.sender] >= amount);
    function buy(uint256 amount) external nonReentrant {
        _buy(amount, msg.sender);
    }

    /**
     * @dev Function to buy tokens during presale for another account.
     * @param amount Number of tokens to buy.
     * @param account Address of account to receive tokens.
     */
    function buyFor(uint256 amount, address account) external nonReentrant {
        _buy(amount, account);
    }

    /**
     * @dev Returns the balance of the caller's account.
     * @param account The address to query the balance of address
     * @return A uint256 representing the amount owned by the caller.
     */
    function myBalance(address account) external view returns (uint256) {
        return balances[account];
    }

    /**
     * @dev Sets the minimum purchase amount for the contract @1e6
     * @param amount The new minimum purchase amount in wei.
     */
    function setMinimumAmount(uint256 amount) external onlyOwner {
        minimumPurchaseAmount = amount;
        emit MinimumPurchaseAmountChanged(amount);
    }

    /**
     * @dev Sets the treasury address for the contract
     * @param newTreasury The new treasury address.
     */
    function setTreasury(address newTreasury) external onlyOwner {
        treasury = newTreasury;
        emit SetTreasury(newTreasury);
    }

    /**
     * @dev Internal function to handle token purchase during presale.
     * @param amount of usdc to exchange for signal.
     * @param account Address of account to receive tokens.
     */

    function _buy(uint256 amount, address account) internal {
        // Check if presale is open and not closed
        require(isOpen, "SolidSignalPresale: Presale is not open");
        require(!isClosed, "SolidSignalPresale: Presale is closed");
        require(
            amount >= minimumPurchaseAmount,
            "SolidSignalPresale: Amount is low"
        );

        //the signalValue of future signal tokens to claim
        uint256 signalValue = ((amount * 1e18) / presalePrice) * 1e12;

        // Check if enough tokens are left for sale
        require(
            (totalSold + signalValue) <= presaleCap,
            "SolidSignalPresale: Not enough tokens left for sale"
        );

        balances[account] += signalValue;
        totalSold += signalValue;
        usdcRaised += amount;

        bool transfered = usdcToken.transferFrom(
            msg.sender,
            address(this),
            amount
        );
        require(transfered);

        emit Sell(account, amount);
    }

    //admin only
    /**
     * @dev Function to start the presale.
     */
    function start() external onlyOwner {
        // Check if presale is not already open
        require(!isOpen, "SolidSignalPresale: sale is already open");
        // Set presale status to open
        isOpen = true;
        emit Start(msg.sender);
    }

    /**
     * @dev Function to end the presale.
     */
    function endSale() external onlyOwner {
        // Check if presale is not already closed
        require(!isClosed, "SolidSignalPresale: sale is closed");
        // Set presale status to closed
        isClosed = true;
        emit End(msg.sender);
    }

    /**
     * @dev Function to withdraw usdcToken from contract.
     */
    function withdraw() external onlyOwner nonReentrant {
        // Get balance of usdcToken held by contract
        uint256 balance = usdcToken.balanceOf(address(this));
        // Check if balance is greater than zero
        require(balance > 0, "SolidSignalPresale: balance withdrawn");
        // Calculate amount to transfer to treasury and owner
        uint256 treasuryAmount = (2000 * balance) / 1e4; //20% of usdc raise to treasury
        uint256 ownerAmount = balance - treasuryAmount;
        // Transfer usdcToken to treasury and owner
        usdcToken.safeTransfer(treasury, treasuryAmount);
        usdcToken.safeTransfer(msg.sender, ownerAmount);
        emit Withdraw(msg.sender, (ownerAmount + treasuryAmount));
    }
}

