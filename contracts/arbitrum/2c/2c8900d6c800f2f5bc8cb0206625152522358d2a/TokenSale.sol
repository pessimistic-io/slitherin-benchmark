// SPDX-License-Identifier: AGPL

pragma solidity ^0.8.13;

import "./Ownable.sol";
import "./Math.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";

/**
 * @title   DSQ TokenSale
 * @notice  Allow users to purchase DSQ tokens with ether
 * @notice  Users can claim tokens at different times based on which tier they bought
 * @notice  Tiers are based on amount of ether already bought
 * @author  HessianX
 * @custom:developer    BowTiedPickle
 * @custom:developer    BowTiedOriole
 */
contract TokenSale is Ownable, ReentrancyGuard {
    using Math for uint256;
    using SafeERC20 for IERC20;

    // ----- Events -----

    event SaleStarted(uint256 tokensPerWei, uint128 startTime, uint128 endTime, uint128 tier2ClaimTime, uint128 tier3ClaimTime);

    event Purchase(address indexed purchaser, uint256 quantity, uint256 amountPaid);
    event Refund(address indexed beneficiary, uint256 quantity);
    event Claim(address indexed purchaser, uint256 quantity);

    event Withdrawal(uint256 amount);
    event Retrieve(uint256 amount);

    // ----- State Variables -----

    IERC20 public immutable DSQ;

    uint128 public startTime;
    uint128 public endTime;
    uint128 public tier2ClaimTime;
    uint128 public tier3ClaimTime;
    uint128 public constant CLAIM_PERIOD = 30 days;

    uint256 public tokensPerWei;

    uint256 public constant MAX_TIER1_CONTRIBUTIONS = 69 ether;
    uint256 public constant MAX_TIER2_CUMULATIVE_CONTRIBUTIONS = MAX_TIER1_CONTRIBUTIONS + 138 ether;
    uint256 public constant MAX_RAISE = MAX_TIER2_CUMULATIVE_CONTRIBUTIONS + 276 ether;

    mapping(address => uint256) public contributed;
    mapping(address => uint256) public tier1Pending;
    mapping(address => uint256) public tier2Pending;
    mapping(address => uint256) public tier3Pending;

    uint256 public totalContribution;

    // ----- Construction and Initialization -----

    /**
     * @param _DSQ      DSQ Token address
     * @param _owner    Owner address
     */
    constructor(IERC20 _DSQ, address _owner) {
        require(address(_DSQ) != address(0) && _owner != address(0), "zeroAddr");
        DSQ = _DSQ;
        _transferOwnership(_owner);
    }

    /**
     * @notice  Start the token sale process
     * @dev     Make sure the contract is funded before _endTime or people won't be able to claim
     * @param   _tokensPerWei   Wei of DSQ to mint per wei of Ether contributed during sale
     * @param   _startTime      Sale start timestamp in Unix epoch seconds
     * @param   _endTime        Sale end timestamp in Unix epoch seconds
     */
    function startSale(
        uint256 _tokensPerWei,
        uint128 _startTime,
        uint128 _endTime
    ) external onlyOwner {
        require(startTime == 0, "Started");
        require(_endTime > _startTime && _startTime > block.timestamp, "Dates");

        tokensPerWei = _tokensPerWei;

        startTime = _startTime;
        endTime = _endTime;
        tier2ClaimTime = _endTime + CLAIM_PERIOD;
        tier3ClaimTime = _endTime + 2 * CLAIM_PERIOD;

        emit SaleStarted(_tokensPerWei, _startTime, _endTime, tier2ClaimTime, tier3ClaimTime);
    }

    // ----- Public Functions -----

    /**
     * @notice  Purchase tokens during the sale
     * @notice  Purchase amount is allocated into tiers based on how many tokens have been already purchased
     * @dev     Will purchase the desired amount OR all the remaining tokens if there are less than _amount left in the sale.
     *          Will refund any excess value transferred in the above case.
     * @dev     Only callable by EOA
     * @return  Actual amount of tokens purchased
     */
    function purchase() external payable nonReentrant returns (uint256) {
        require(msg.sender == tx.origin, "!EOA");
        require(block.timestamp > startTime && startTime > 0, "Not Started");
        require(block.timestamp < endTime, "Sale Over");
        require(msg.value > 0, "Amount");
        // Cache
        uint256 _totalContribution = totalContribution;
        require(_totalContribution < MAX_RAISE, "Sale Max");
        uint256 _tokensPerWei = tokensPerWei;

        uint256 purchaseWeiAmount = (_totalContribution + msg.value > MAX_RAISE) ? MAX_RAISE - _totalContribution : msg.value;
        uint256 tokensToPurchase = purchaseWeiAmount * _tokensPerWei;

        uint256 tier1Amount = (_totalContribution >= MAX_TIER1_CONTRIBUTIONS)
            ? 0
            : Math.min(purchaseWeiAmount, MAX_TIER1_CONTRIBUTIONS - _totalContribution);
        uint256 tier2Amount = (_totalContribution >= MAX_TIER2_CUMULATIVE_CONTRIBUTIONS)
            ? 0
            : Math.min(purchaseWeiAmount - tier1Amount, MAX_TIER2_CUMULATIVE_CONTRIBUTIONS - _totalContribution - tier1Amount);
        uint256 tier3Amount = purchaseWeiAmount - tier1Amount - tier2Amount;

        tier1Pending[msg.sender] += (tier1Amount * _tokensPerWei);
        tier2Pending[msg.sender] += (tier2Amount * _tokensPerWei);
        tier3Pending[msg.sender] += (tier3Amount * _tokensPerWei);
        contributed[msg.sender] += purchaseWeiAmount;
        totalContribution += purchaseWeiAmount;
        uint256 refund = msg.value - purchaseWeiAmount;

        if (refund > 0) {
            payable(msg.sender).transfer(refund);
            emit Refund(msg.sender, refund);
        }

        emit Purchase(msg.sender, tokensToPurchase, purchaseWeiAmount);
        return tokensToPurchase;
    }

    /**
     * @notice  Claim tokens purchased during the sale
     * @notice  Will claim tokens in currently available tier and previous tiers
     * @return  The amount of tokens claimed
     */
    function claim() external nonReentrant returns (uint256) {
        uint256 pendingTokens;
        if (block.timestamp > tier3ClaimTime) {
            pendingTokens = tier1Pending[msg.sender] + tier2Pending[msg.sender] + tier3Pending[msg.sender];
            tier1Pending[msg.sender] = 0;
            tier2Pending[msg.sender] = 0;
            tier3Pending[msg.sender] = 0;
        } else if (block.timestamp > tier2ClaimTime) {
            pendingTokens = tier1Pending[msg.sender] + tier2Pending[msg.sender];
            tier1Pending[msg.sender] = 0;
            tier2Pending[msg.sender] = 0;
        } else if (block.timestamp > endTime) {
            pendingTokens = tier1Pending[msg.sender];
            tier1Pending[msg.sender] = 0;
        } else {
            revert("Phase");
        }

        require(pendingTokens > 0, "NoPending");

        DSQ.safeTransfer(msg.sender, pendingTokens);
        emit Claim(msg.sender, pendingTokens);

        return pendingTokens;
    }

    // ----- Admin Functions -----

    /**
     * @notice Withdraw sale profits to the owner
     */
    function withdraw() external onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        payable(msg.sender).transfer(balance);
        emit Withdrawal(balance);
    }

    /**
     * @notice Retrieve the remaining sale tokens
     */
    function retrieve() external onlyOwner {
        require(block.timestamp > tier3ClaimTime + CLAIM_PERIOD, "Ongoing");
        uint256 balance = DSQ.balanceOf(address(this));
        DSQ.safeTransfer(msg.sender, balance);
        emit Retrieve(balance);
    }

    /**
     * @notice  Push tokens to a user
     * @param   _users    Users to claim for
     */
    function claimFor(address[] calldata _users) external onlyOwner {
        require(block.timestamp > tier3ClaimTime + CLAIM_PERIOD, "Ongoing");

        uint256 len = _users.length;
        for (uint256 i; i < len; ) {
            uint256 balance = tier1Pending[_users[i]] + tier2Pending[_users[i]] + tier3Pending[_users[i]];
            if (balance > 0) {
                tier1Pending[_users[i]] = 0;
                tier2Pending[_users[i]] = 0;
                tier3Pending[_users[i]] = 0;
                DSQ.safeTransfer(_users[i], balance);
                emit Claim(_users[i], balance);
            }

            unchecked {
                ++i;
            }
        }
    }
}

