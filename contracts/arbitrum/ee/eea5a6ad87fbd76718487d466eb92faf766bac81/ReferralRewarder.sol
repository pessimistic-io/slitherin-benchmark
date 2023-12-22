// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {MerkleProof} from "./MerkleProof.sol";
import {TransparentUpgradeableProxy as Proxy} from "./TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "./ProxyAdmin.sol";
import {Initializable} from "./Initializable.sol";
import {OwnableUpgradeable} from "./OwnableUpgradeable.sol";

contract ReferralRewarder is Initializable, OwnableUpgradeable {
    using SafeERC20 for IERC20;

    struct EpochInfo {
        bytes32 merkleRoot;
        bytes32 ipfsHash;
        uint256 totalRewards;
        uint256 totalClaimed;
        uint64 startVestingTime;
        uint64 endVestingTime;
    }

    address public constant LVL = 0xB64E280e9D1B5DbEc4AcceDb2257A87b400DB149;
    address public constant PRE_LVL = 0x964d582dA16B37F8d16DF3A66e6BF0E7fd44ac3a;
    uint64 public constant VESTING_DURATION = 7 days;
    uint256 public constant START_EPOCH_USING_PRE_LVL = 32;

    uint256 public CHAIN_ID;
    address public controller;

    // Epoch => user => amount
    mapping(uint256 => mapping(address => uint256)) public rewardReceived;
    // Epoch => info
    mapping(uint256 => EpochInfo) public epoches;

    constructor() {
        _disableInitializers();
    }

    function initialize(address _controller) external initializer {
        require(_controller != address(0), "invalid address");
        __Ownable_init();
        controller = _controller;

        uint256 chainId;
        assembly {
            chainId := chainid()
        }
        CHAIN_ID = chainId;
    }

    function addEpoch(uint256 _epoch, bytes32 _merkleRoot, bytes32 _ipfsHash, uint256 _totalRewards) external {
        require(msg.sender == owner() || msg.sender == controller, "unauthorized");
        require(epoches[_epoch].merkleRoot == bytes32(0), "epoch exists");
        uint64 _startVestingTime = uint64(block.timestamp);
        uint64 _endVestingTime =
            _epoch >= START_EPOCH_USING_PRE_LVL ? _startVestingTime : (_startVestingTime + VESTING_DURATION);

        epoches[_epoch] = EpochInfo({
            merkleRoot: _merkleRoot,
            ipfsHash: _ipfsHash,
            totalRewards: _totalRewards,
            totalClaimed: 0,
            startVestingTime: _startVestingTime,
            endVestingTime: _endVestingTime
        });

        emit EpochCreated(_epoch, _totalRewards, _merkleRoot, _ipfsHash, _startVestingTime, _endVestingTime);
    }
    /*=================================== VIEWS ============================== */

    function claimableRewards(
        uint256 _epoch,
        uint256 _index,
        address _user,
        uint256 _rewards,
        bytes32[] memory _merkleProof
    ) external view returns (uint256) {
        (, uint256 _claimableRewards) = _getClaimableRewards(_epoch, _index, _user, _rewards, _merkleProof);
        return _claimableRewards;
    }
    /*=================================== MULTATIVE ============================== */

    function claimRewards(uint256 _epoch, address _to, uint256 _index, uint256 _rewards, bytes32[] memory _merkleProof)
        external
    {
        (bool _isValid, uint256 _claimableRewards) =
            _getClaimableRewards(_epoch, _index, msg.sender, _rewards, _merkleProof);
        require(_isValid, "incorrect merkle proof");
        require(_claimableRewards > 0, "rewards = 0");
        uint256 totalClaimed = epoches[_epoch].totalClaimed + _claimableRewards;
        require(totalClaimed <= epoches[_epoch].totalRewards, "overclaimed");
        rewardReceived[_epoch][msg.sender] += _claimableRewards;
        epoches[_epoch].totalClaimed = totalClaimed;
        if (_epoch >= START_EPOCH_USING_PRE_LVL) {
            IERC20(PRE_LVL).safeTransfer(_to, _claimableRewards);
        } else {
            IERC20(LVL).safeTransfer(_to, _claimableRewards);
        }
        emit Claimed(msg.sender, _to, _epoch, _claimableRewards);
    }

    /*=================================== ADMIN ============================== */

    function setController(address _newController) external onlyOwner {
        require(_newController != address(0), "invalid address");
        controller = _newController;
        emit ControllerSet(_newController);
    }

    function recoverFund(address _receiver, uint256 _amount) external onlyOwner {
        require(_receiver != address(0), "invalid address");
        IERC20(LVL).safeTransfer(_receiver, _amount);
        emit FundRecovered(_amount, _receiver);
    }

    /*=================================== INTERNAL ============================== */
    function _getClaimableRewards(
        uint256 _epoch,
        uint256 _index,
        address _user,
        uint256 _rewards,
        bytes32[] memory _merkleProof
    ) internal view returns (bool _isValid, uint256 _claimableRewards) {
        EpochInfo memory _epochInfo = epoches[_epoch];
        if (_epochInfo.merkleRoot != bytes32(0)) {
            bytes32 node = keccak256(bytes.concat(keccak256(abi.encode(_index, _user, _rewards, CHAIN_ID))));
            _isValid = MerkleProof.verify(_merkleProof, _epochInfo.merkleRoot, node);
            if (_isValid) {
                if (block.timestamp >= _epochInfo.endVestingTime) {
                    _claimableRewards = _rewards - rewardReceived[_epoch][_user];
                } else {
                    uint256 _time = block.timestamp < uint256(_epochInfo.startVestingTime)
                        ? 0
                        : block.timestamp - uint256(_epochInfo.startVestingTime);
                    uint256 _rewardDuration = uint256(_epochInfo.endVestingTime) - uint256(_epochInfo.startVestingTime);

                    _claimableRewards = (_time * _rewards / _rewardDuration) - rewardReceived[_epoch][_user];
                }
            }
        }
    }
    /*=================================== EVENTS ============================== */

    event EpochCreated(
        uint256 _epoch,
        uint256 _totalRewards,
        bytes32 _merkleRoot,
        bytes32 _ipfsHash,
        uint64 _startTime,
        uint64 _endTime
    );
    event Claimed(address indexed _sender, address indexed _to, uint256 _epoch, uint256 _rewards);
    event FundRecovered(uint256 _amount, address _receiver);
    event ControllerSet(address _newAdmin);
}

