// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./Ownable.sol";
import "./SafeERC20.sol";
import "./MerkleProof.sol";

import "./IRebateHandler.sol";

/**
 * @dev Contract that distributes rewards to users based on a merkle proof
 * that is computed offchain and updated on a regular basis by the admin.
 *
 * The contract assumes that rebateToken balance will be transferred directly by the program creator.
 *
 * The merkle root can be updated by the admin only if block.timestamp >= _timeElapsedForUpdate.
 *
 * Rewards will be claimed on a first cum first serve basis until the total amount claimed
 * is less than the cap set for the ongoing epoch.
 *
 * There is also a cap on the total number of users that can claim tokens in a given epoch.
 * This is done because of gas limitation while resetting the addressExists variable.
 *
 * Admin can reclaim unused rewards after a certain amount of inactivity
 */
contract RebateHandler is IRebateHandler, Ownable {
    using SafeERC20 for IERC20;

    /// @notice This mapping is used to check if an address has already claimed amount.
    mapping(address => bool) public addressExists;
    /// @notice Address of the token used to give rebates.
    IERC20 public immutable rebateToken;
    /// @notice Address that can update the merkel root
    address public merkleRootAdmin;
    /// @notice List of addresses that have already claimed rebate for a given epoch.
    address[] public claimedAddresses;
    /// @notice The merkle root of the distribution for the current epoch.
    bytes32 public merkleRoot;
    /// @notice The time when the merkleRoot was updated.
    uint256 public lastUpdated;
    /// @notice The maximum number of users that can claim rebates in a given epoch.
    uint256 public maxUsersToClaim;
    /// @notice The time after which the merkle root can be updated.
    uint256 public timeElapsedForUpdate;
    /// @notice The maximum amount of tokens that can be claimed in a given epoch.
    uint256 public maxAmountToClaim;
    /// @notice the number of tokens claimed in a given epoch.
    uint256 public amountClaimed;
    /// @notice the time after which an admin claim unused rewards.
    uint256 public timeToReclaimRewards;

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyMerkleRootAdmin() {
        require(
            merkleRootAdmin == _msgSender(),
            "caller can't update merkle root"
        );
        _;
    }

    /// @param rebateTokenAddress address of the token that will be used to pay rebates.
    /// @param owner address of the owner.
    /// @param _maxUsersToClaim Maximum numbers of users that can claim fees during an epoch.
    /// @param _timeElapsedForUpdate The time after which the next distribution can be updated.
    /// @param _timeToReclaimRewards The time after which an admin can claim unused rewards.
    constructor(
        address rebateTokenAddress,
        address owner,
        address _merkleRootAdmin,
        uint256 _maxUsersToClaim,
        uint256 _timeElapsedForUpdate,
        uint256 _timeToReclaimRewards
    ) {
        require(
            _timeToReclaimRewards > _timeElapsedForUpdate,
            "_timeToReclaimRewards less than timeElapsedForUpdate"
        );
        rebateToken = IERC20(rebateTokenAddress);
        merkleRootAdmin = _merkleRootAdmin;
        maxUsersToClaim = _maxUsersToClaim;
        timeElapsedForUpdate = _timeElapsedForUpdate;
        timeToReclaimRewards = _timeToReclaimRewards;
        transferOwnership(owner);
    }

    /// @inheritdoc IRebateHandler
    function updateMerkleRoot(
        bytes32 _merkleRoot,
        uint256 _maxAmountToClaim
    ) external onlyMerkleRootAdmin {
        require(
            (block.timestamp - lastUpdated >= timeElapsedForUpdate) ||
                (lastUpdated == uint256(0)),
            "Cannot update before timeElapsedForUpdate"
        );
        require(
            rebateToken.balanceOf(address(this)) >= _maxAmountToClaim,
            "Balance less than maxAmountToClaim"
        );
        lastUpdated = block.timestamp;
        _resetAddressExists();
        delete claimedAddresses;
        amountClaimed = 0;
        maxAmountToClaim = _maxAmountToClaim;
        merkleRoot = _merkleRoot;
        emit MerkleRootUpdated(_merkleRoot, _maxAmountToClaim);
    }

    /// @inheritdoc IRebateHandler
    function claimReward(bytes32[] memory proof, uint256 amount) external {
        require(merkleRoot != bytes32(0), "Empty Merkle Root");
        require(!addressExists[msg.sender], "Rebate already claimed");
        uint256 amountLeftToClaim = maxAmountToClaim - amountClaimed;
        require(amountLeftToClaim > 0, "All rebates have been Claimed");
        require(_verifyProof(proof, msg.sender, amount), "Invalid Proof");
        addressExists[msg.sender] = true;
        claimedAddresses.push(msg.sender);
        require(
            claimedAddresses.length <= maxUsersToClaim,
            "Exceeded Max number claims"
        );
        uint256 ClaimableAmount = amount < amountLeftToClaim
            ? amount
            : amountLeftToClaim;
        amountClaimed += ClaimableAmount;
        // Follows checks effects pattern. So there should be no re-entrancy exploit
        rebateToken.safeTransfer(msg.sender, ClaimableAmount);
        emit RewardPaid(msg.sender, ClaimableAmount);
    }

    /// @inheritdoc IRebateHandler
    function reclaimUnusedReward(address account) external onlyOwner {
        require(
            (block.timestamp - lastUpdated >= timeToReclaimRewards),
            "time less than timeToReclaimRewards"
        );
        rebateToken.safeTransfer(account, rebateToken.balanceOf(address(this)));
    }

    /// @notice allows admin to update merkleRootAdmin variable
    /// @param _merkleRootAdmin new merkleRootAdmin value.
    function updateMerkleRootAdmin(
        address _merkleRootAdmin
    ) external onlyOwner {
        require(_merkleRootAdmin != address(0), "_merkleRootAdmin can't be zero");
        require(_merkleRootAdmin != owner(), "_merkleRootAdmin can't be same as Owner");
        merkleRootAdmin = _merkleRootAdmin;
    }

    /// @notice allows admin to update maxUsersToClaim variable.
    /// @param _maxUsersToClaim new maxUsersToClaim value.
    function updateMaxUsersToClaim(
        uint256 _maxUsersToClaim
    ) external onlyOwner {
        require(_maxUsersToClaim != 0, "_maxUsersToClaim can't be 0");
        maxUsersToClaim = _maxUsersToClaim;
    }

    /// @notice allows admin to update timeElapsedForUpdate variable
    /// @param _timeElapsedForUpdate new timeElapsedForUpdate value.
    function updateTimeElapsedForUpdate(
        uint256 _timeElapsedForUpdate
    ) external onlyOwner {
        require(_timeElapsedForUpdate != 0, "_timeElapsedForUpdate can't be 0");
        timeElapsedForUpdate = _timeElapsedForUpdate;
    }

    /// @notice allows admin to update timeToReclaimRewards variable
    /// @param _timeToReclaimRewards new timeToReclaimRewards value.
    function updateTimeToReclaimRewards(
        uint256 _timeToReclaimRewards
    ) external onlyOwner {
        require(_timeToReclaimRewards != 0, "_timeToReclaimRewards can't be 0");
        require(
            _timeToReclaimRewards > timeElapsedForUpdate,
            "value less than timeElapsedForUpdate"
        );
        timeToReclaimRewards = _timeToReclaimRewards;
    }

    function _resetAddressExists() internal {
        uint256 length = claimedAddresses.length;
        for (uint256 i = 0; i < length; i++) {
            delete addressExists[claimedAddresses[i]];
        }
    }

    function _verifyProof(
        bytes32[] memory proof,
        address account,
        uint256 amount
    ) internal view returns (bool) {
        bytes32 leaf = keccak256(
            bytes.concat(keccak256(abi.encode(account, amount)))
        );
        return MerkleProof.verify(proof, merkleRoot, leaf);
    }
}

