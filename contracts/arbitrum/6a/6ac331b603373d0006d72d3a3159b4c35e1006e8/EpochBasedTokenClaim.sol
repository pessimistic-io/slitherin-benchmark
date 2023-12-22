// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {MerkleProof} from "./MerkleProof.sol";
import {Ownable2Step} from "./Ownable2Step.sol";

import "./IERC20.sol";

contract EpochBasedTokenClaim is Ownable2Step {
    IERC20 public immutable rewardToken;
    address public manager;

    mapping(uint256 => bytes32) public epochRoots; // epoch => root
    mapping(uint256 => string) public epochCids; // epoch => ipfs cid
    mapping(uint256 => mapping(address => bool)) public epochTraderClaimed; // epoch => trader => claimed

    event ManagerUpdated(address newManager);
    event TokensWithdrawn();
    event EpochMerkleRootSet(uint256 indexed epoch, bytes32 root, uint256 totalRewards, string cid);
    event TokensClaimed(uint256 indexed epoch, address indexed user, uint256 rewardAmount);
    event TokensClaimed(uint256[] epochs, address indexed user, uint256 rewardAmount);

    error AddressZero();
    error NotManager();
    error RootAlreadySet();
    error RootZero();
    error RewardsZero();
    error CidZero();
    error InvalidEpochs();
    error ArrayLengthMismatch();
    error EpochNotSet();
    error NotEnoughBalance();
    error AlreadyClaimed();
    error InvalidProof();

    constructor(IERC20 _rewardToken, address _owner, address _manager) {
        if (address(_rewardToken) == address(0) || _owner == address(0) || _manager == address(0)) revert AddressZero();

        rewardToken = _rewardToken;
        manager = _manager;

        _transferOwnership(_owner);
    }

    modifier onlyManager() {
        if (msg.sender != manager) revert NotManager();
        _;
    }

    /**
     * @dev Sets manager address to `_manager`. Only callable by `owner()` (multisig)
     */
    function setManager(address _manager) external onlyOwner {
        if (_manager == address(0)) revert AddressZero();

        manager = _manager;

        emit ManagerUpdated(_manager);
    }

    /**
     * @dev Sets Merkle Tree `_root` and '_cid' for an `_epoch` and transfers `_totalRewards` from the `owner()` (multisig) to this
     * contract. Only callable by `manager`.
     */
    function setRoot(uint256 _epoch, bytes32 _root, uint256 _totalRewards, string memory _cid) external onlyManager {
        if (epochRoots[_epoch] != bytes32(0)) revert RootAlreadySet();
        if (_root == bytes32(0)) revert RootZero();
        if (_totalRewards == 0) revert RewardsZero();
        if (bytes(_cid).length == 0) revert CidZero();

        rewardToken.transferFrom(owner(), address(this), _totalRewards);

        epochRoots[_epoch] = _root;
        epochCids[_epoch] = _cid;

        emit EpochMerkleRootSet(_epoch, _root, _totalRewards, _cid);
    }

    /**
     * @dev Prevents stuck tokens in case of misconfiguration; Only `owner()` (multisig) can claim the tokens back
     */
    function withdrawTokens() external onlyOwner {
        rewardToken.transfer(msg.sender, rewardToken.balanceOf(address(this)));

        emit TokensWithdrawn();
    }

    /**
     * @dev Claims trader rewards for a specific `_epoch`
     */
    function claimRewards(uint256 _epoch, uint256 _rewardAmount, bytes32[] calldata _proof) external {
        address trader = msg.sender;
        _validateClaim(_epoch, trader, _rewardAmount, _proof);

        epochTraderClaimed[_epoch][trader] = true;
        rewardToken.transfer(trader, _rewardAmount);

        emit TokensClaimed(_epoch, trader, _rewardAmount);
    }

    /**
     * @dev Claims trader rewards for multiple `_epochs`
     */
    function claimMultipleRewards(
        uint256[] calldata _epochs,
        uint256[] calldata _rewardAmounts,
        bytes32[][] calldata _proofs
    ) external {
        if (_epochs.length == 0) revert InvalidEpochs();

        if ((_epochs.length != _rewardAmounts.length) || (_rewardAmounts.length != _proofs.length))
            revert ArrayLengthMismatch();

        address trader = msg.sender;
        uint256 totalAmount;

        for (uint256 i; i < _epochs.length; ) {
            _validateClaim(_epochs[i], trader, _rewardAmounts[i], _proofs[i]);

            epochTraderClaimed[_epochs[i]][trader] = true;
            totalAmount += _rewardAmounts[i];

            unchecked {
                ++i;
            }
        }

        rewardToken.transfer(trader, totalAmount);

        emit TokensClaimed(_epochs, trader, totalAmount);
    }

    /**
     * @dev Returns a hashed leaf of `_user` + `_amount`
     */
    function _hashLeaf(address _user, uint256 _amount) internal pure returns (bytes32) {
        return keccak256(bytes.concat(keccak256(abi.encode(_user, _amount))));
    }

    /**
     * @dev Validates that:
     * 1) The `_epoch` merkle tree root is set
     * 2) There are enough token rewards in the contract
     * 3) Rewards for leaf are unclaimed
     * 4) The `leaf` and `_proof` validate against `epochRoot`
     */
    function _validateClaim(
        uint256 _epoch,
        address _trader,
        uint256 _rewardAmount,
        bytes32[] calldata _proof
    ) internal view {
        bytes32 epochRoot = epochRoots[_epoch];
        bytes32 leaf = _hashLeaf(_trader, _rewardAmount);

        if (epochRoot == bytes32(0)) revert EpochNotSet();
        if (_rewardAmount > rewardToken.balanceOf(address(this))) revert NotEnoughBalance();
        if (epochTraderClaimed[_epoch][_trader]) revert AlreadyClaimed();
        if (!MerkleProof.verifyCalldata(_proof, epochRoot, leaf)) revert InvalidProof();
    }
}

