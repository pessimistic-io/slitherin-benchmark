// SPDX-License-Identifier: AGPL

pragma solidity ^0.8.13;

import "./Ownable.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";
import "./MerkleProof.sol";

/**
 * @title   DSQ TokenSale Phase 4
 * @notice  Allow users to purchase DSQ tokens with ether in a whitelist sale and a public sale
 * @author  HessianX
 * @custom:developer    BowTiedPickle
 * @custom:developer    BowTiedOriole
 */
contract TokenSalePhase4 is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ----- Events -----

    event SaleStarted(uint256 tokensPerWei, uint128 whitelistStartTime, uint128 publicStartTime, uint128 endTime, bytes32 merkleRoot);
    event NewMerkleRoot(bytes32 oldRoot, bytes32 newRoot);

    event PurchaseWhitelist(address indexed purchaser, uint256 quantity, uint256 amountPaid);
    event PurchasePublic(address indexed purchaser, uint256 quantity, uint256 amountPaid);
    event Refund(address indexed beneficiary, uint256 quantity);
    event Claim(address indexed purchaser, uint256 quantity);

    event Withdrawal(uint256 amount);
    event Retrieve(uint256 amount);

    // ----- State Variables -----

    IERC20 public immutable DSQ;

    uint128 public whitelistStartTime;
    uint128 public publicStartTime;
    uint128 public endTime;
    uint128 public constant LOCK_PERIOD = 90 days;
    uint128 public constant CLAIM_PERIOD = 30 days;

    bytes32 public merkleRoot;

    uint256 public tokensPerWei;

    uint256 public constant MAX_CONTRIBUTION_PER_USER = 1 ether;
    uint256 public constant MAX_RAISE = 483 ether;

    mapping(address => uint256) public pending;

    mapping(address => uint256) public contributionPerUser;

    uint256 public totalContribution;

    // ----- Construction and Initialization -----

    /**
     * @param   _DSQ    DSQ Token address
     * @param   _owner  Owner address
     */
    constructor(IERC20 _DSQ, address _owner) {
        require(address(_DSQ) != address(0) && _owner != address(0), "zeroAddr");
        DSQ = _DSQ;
        _transferOwnership(_owner);
    }

    /**
     * @notice  Start the token sale process
     * @dev     Make sure the contract is funded before _endTime or people won't be able to claim
     * @param   _tokensPerWei           Wei of DSQ to mint per wei of Ether contributed during sale
     * @param   _whitelistStartTime     Whitelist sale start timestamp in Unix epoch seconds
     * @param   _publicStartTime        Public sale start timestamp in Unix epoch seconds
     * @param   _endTime                Sale end timestamp in Unix epoch seconds
     * @param   _merkleRoot             Whitelist merkle root
     */
    function startSale(
        uint256 _tokensPerWei,
        uint128 _whitelistStartTime,
        uint128 _publicStartTime,
        uint128 _endTime,
        bytes32 _merkleRoot
    ) external onlyOwner {
        require(whitelistStartTime == 0, "Started");
        require(_endTime > _publicStartTime && _publicStartTime > _whitelistStartTime && _whitelistStartTime > block.timestamp, "Dates");

        tokensPerWei = _tokensPerWei;
        whitelistStartTime = _whitelistStartTime;
        publicStartTime = _publicStartTime;
        endTime = _endTime;
        merkleRoot = _merkleRoot;

        emit SaleStarted(_tokensPerWei, _whitelistStartTime, _publicStartTime, _endTime, _merkleRoot);
    }

    // ----- Public Functions -----

    /**
     * @notice  Purchase tokens during the whitelist sale
     * @dev     Will purchase the desired amount OR all the remaining tokens if there are less than _amount left in the sale.
     *          Will refund any excess value transferred in the above case.
     * @dev     Only callable by EOA
     * @dev     Enforces a maximum contribution per user
     * @param   _proof  Merkle proof for whitelist
     * @return  Actual amount of tokens purchased
     */
    function purchaseWhitelist(bytes32[] calldata _proof) external payable nonReentrant returns (uint256) {
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender));
        require(MerkleProof.verifyCalldata(_proof, merkleRoot, leaf), "!Whitelisted");
        require(msg.sender == tx.origin, "!EOA");
        require(block.timestamp >= whitelistStartTime && whitelistStartTime > 0, "Not Started");
        require(block.timestamp < publicStartTime, "Whitelist Sale Over");
        require(msg.value > 0, "Amount");

        // Cache
        uint256 _totalContribution = totalContribution;
        require(_totalContribution < MAX_RAISE, "Sale Max");

        uint256 purchaseWeiAmount = (_totalContribution + msg.value > MAX_RAISE) ? MAX_RAISE - _totalContribution : msg.value;
        require(contributionPerUser[msg.sender] + purchaseWeiAmount <= MAX_CONTRIBUTION_PER_USER, "User Cap Exceeded");

        uint256 tokensToPurchase = purchaseWeiAmount * tokensPerWei;
        pending[msg.sender] += tokensToPurchase;

        totalContribution += purchaseWeiAmount;
        contributionPerUser[msg.sender] += purchaseWeiAmount;

        uint256 refund = msg.value - purchaseWeiAmount;
        if (refund > 0) {
            payable(msg.sender).transfer(refund);
            emit Refund(msg.sender, refund);
        }

        emit PurchaseWhitelist(msg.sender, tokensToPurchase, purchaseWeiAmount);
        return tokensToPurchase;
    }

    /**
     * @notice  Purchase tokens during the public sale
     * @dev     Will purchase the desired amount OR all the remaining tokens if there are less than _amount left in the sale.
     *          Will refund any excess value transferred in the above case.
     * @dev     Only callable by EOA
     * @return  Actual amount of tokens purchased
     */
    function purchasePublic() external payable nonReentrant returns (uint256) {
        require(msg.sender == tx.origin, "!EOA");
        require(block.timestamp >= publicStartTime && publicStartTime > 0, "Not Started");
        require(block.timestamp < endTime, "Public Sale Over");
        require(msg.value > 0, "Amount");

        // Cache
        uint256 _totalContribution = totalContribution;
        require(_totalContribution < MAX_RAISE, "Sale Max");

        uint256 purchaseWeiAmount = (_totalContribution + msg.value > MAX_RAISE) ? MAX_RAISE - _totalContribution : msg.value;

        uint256 tokensToPurchase = purchaseWeiAmount * tokensPerWei;
        pending[msg.sender] += tokensToPurchase;

        totalContribution += purchaseWeiAmount;
        contributionPerUser[msg.sender] += purchaseWeiAmount;

        uint256 refund = msg.value - purchaseWeiAmount;
        if (refund > 0) {
            payable(msg.sender).transfer(refund);
            emit Refund(msg.sender, refund);
        }

        emit PurchasePublic(msg.sender, tokensToPurchase, purchaseWeiAmount);
        return tokensToPurchase;
    }

    /**
     * @notice  Claim tokens purchased during the sale
     * @return  The amount of tokens claimed
     */
    function claim() external nonReentrant returns (uint256) {
        require(block.timestamp >= endTime + LOCK_PERIOD, "Claim Not Active");
        uint256 pendingTokens = pending[msg.sender];
        require(pendingTokens > 0, "NoPending");
        pending[msg.sender] = 0;

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
        require(block.timestamp > endTime + LOCK_PERIOD + CLAIM_PERIOD, "Ongoing");
        uint256 balance = DSQ.balanceOf(address(this));
        DSQ.safeTransfer(msg.sender, balance);
        emit Retrieve(balance);
    }

    /**
     * @notice  Push tokens to a user
     * @param   _users    Users to claim for
     */
    function claimFor(address[] calldata _users) external onlyOwner {
        require(block.timestamp > endTime + LOCK_PERIOD + CLAIM_PERIOD, "Ongoing");

        uint256 len = _users.length;
        for (uint256 i; i < len; ) {
            uint256 balance = pending[_users[i]];
            if (balance > 0) {
                pending[_users[i]] = 0;
                DSQ.safeTransfer(_users[i], balance);
                emit Claim(_users[i], balance);
            }

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice  Set merkle root
     * @param   _newRoot    New whitelist Merkle root
     */
    function setMerkleRoot(bytes32 _newRoot) external onlyOwner {
        emit NewMerkleRoot(merkleRoot, _newRoot);
        merkleRoot = _newRoot;
    }
}

