// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "./Ownable.sol";
import "./SafeERC20.sol";

contract Node is Ownable {
    using SafeERC20 for IERC20;
    IERC20 public kong;

    struct NodeEntity {
        uint8 nodeType;
        uint16 periodStaking;
        address owner;
        uint256 id;
        uint256 creationTime;
        uint256 lastClaimTime;
        uint256 startStaking;
    }

    struct User {
        uint256[] nodesIds;
        uint256[] nodesTypesAmount;
    }

    uint8 public malusPeriodStaking;
    uint8[] rewardPerDayPerType;
    uint8[] feesChancesMeeting;
    uint8[] feesAmountMeeting;
    uint8[] feesAmountKong;
    uint8[] boostAPR; // divide by 10
    uint256 public maxRewards;

    uint256 public stakingPeriod = 1 days;
    uint256 public totalNodesCreated;
    uint256[] totalNodesPerType = [0, 0, 0];

    mapping(address => User) nodesOf;
    mapping(uint256 => NodeEntity) public nodesById;

    event BoostAPRChanged(uint8[] boostAPR);
    event MaxRewardsChanged(uint256 maxRewards);
    event NodeCreated(address to, uint256 idNode);
    event StakingPeriodChanged(uint256 stakingPeriod);
    event FeesAmountKongChanged(uint8[] feesAmountKong);
    event MalusPeriodStakingChanged(uint8 malusPeriodStaking);
    event FeesAmountMeetingChanged(uint8[] feesAmountMeeting);
    event FeesChancesMeetingChanged(uint8[] feesChancesMeeting);
    event RewardPerDayPerTypeChanged(uint8[] rewardPerDayPerType);
    event NodeUpgraded(address to, uint256 idNode, uint8 nodeType);
    event NodeStaked(address from, uint256 idNode, uint16 periodStaking);

    error WrongWay();
    error NotStaked();
    error RewardZero();
    error NotOwnerNode();
    error AlreadyStaked();
    error NotEnoughTime();
    error LengthMismatch();
    error NodeDoesnotExist();
    error NotAllowedStakingPeriod();

    constructor(
        address _kong,
        uint8 _malusPeriodStaking,
        uint8[] memory _rewardPerDayPerType,
        uint8[] memory _feesChancesMeeting,
        uint8[] memory _feesAmountMeeting,
        uint8[] memory _feesAmountKong,
        uint8[] memory _boostAPR,
        uint256 _maxRewards
    ) {
        kong = IERC20(_kong);
        malusPeriodStaking = _malusPeriodStaking;
        rewardPerDayPerType = _rewardPerDayPerType;
        feesChancesMeeting = _feesChancesMeeting;
        feesAmountMeeting = _feesAmountMeeting;
        feesAmountKong = _feesAmountKong;
        boostAPR = _boostAPR;
        maxRewards = _maxRewards;
    }

    modifier onlyKong() {
        if (msg.sender != address(kong) && msg.sender != owner())
            revert WrongWay();
        _;
    }

    function _getRandom(
        uint256 _limit,
        uint256 _nonce
    ) private view returns (bool) {
        uint256 random = uint256(
            keccak256(
                abi.encodePacked(
                    block.prevrandao,
                    block.timestamp,
                    totalNodesCreated,
                    _nonce
                )
            )
        ) % 100;
        return random < _limit;
    }

    function setToken(address _kong) external onlyOwner {
        kong = IERC20(_kong);
    }

    function setMalusPeriodStaking(
        uint8 _malusPeriodStaking
    ) external onlyOwner {
        malusPeriodStaking = _malusPeriodStaking;
        emit MalusPeriodStakingChanged(_malusPeriodStaking);
    }

    function setMaxRewards(uint256 _maxRewards) external onlyOwner {
        maxRewards = _maxRewards;
        emit MaxRewardsChanged(_maxRewards);
    }

    function setRewardPerDayPerType(
        uint8[] memory _rewardPerDayPerType
    ) external onlyOwner {
        if (_rewardPerDayPerType.length != 3) revert LengthMismatch();
        rewardPerDayPerType = _rewardPerDayPerType;
        emit RewardPerDayPerTypeChanged(_rewardPerDayPerType);
    }

    function setFeesChancesMeeting(
        uint8[] memory _feesChancesMeeting
    ) external onlyOwner {
        if (_feesChancesMeeting.length != 3) revert LengthMismatch();
        feesChancesMeeting = _feesChancesMeeting;
        emit FeesChancesMeetingChanged(_feesChancesMeeting);
    }

    function setFeesAmountMeeting(
        uint8[] memory _feesAmountMeeting
    ) external onlyOwner {
        if (_feesAmountMeeting.length != 3) revert LengthMismatch();
        feesAmountMeeting = _feesAmountMeeting;
        emit FeesAmountMeetingChanged(_feesAmountMeeting);
    }

    function setFeesAmountKong(
        uint8[] memory _feesAmountKong
    ) external onlyOwner {
        if (_feesAmountKong.length != 4) revert LengthMismatch();
        feesAmountKong = _feesAmountKong;
        emit FeesAmountKongChanged(_feesAmountKong);
    }

    function setBoostAPR(uint8[] memory _boostAPR) external onlyOwner {
        if (_boostAPR.length != 3) revert LengthMismatch();
        boostAPR = _boostAPR;
        emit BoostAPRChanged(_boostAPR);
    }

    function setStakingPeriod(uint256 _stakingPeriod) external onlyOwner {
        stakingPeriod = _stakingPeriod;
        emit StakingPeriodChanged(_stakingPeriod);
    }

    // BUY NODE & UPGRADE
    function buyNode(address _to, bool _stake) external onlyKong {
        User storage user = nodesOf[_to];
        uint8 period;
        uint256 start;

        if (_stake) {
            period = 5;
            start = block.timestamp;
        }

        uint256 idNode = totalNodesCreated;
        nodesById[idNode] = NodeEntity({
            nodeType: 1,
            periodStaking: period,
            owner: _to,
            id: idNode,
            creationTime: block.timestamp,
            lastClaimTime: 0,
            startStaking: start
        });
        if (user.nodesTypesAmount.length == 0) {
            user.nodesTypesAmount = [0, 0, 0];
        }
        user.nodesIds.push(idNode);
        user.nodesTypesAmount[0]++;
        totalNodesPerType[0]++;
        totalNodesCreated++;
        emit NodeCreated(_to, idNode);
    }

    function upgradeNode(address _to, uint256 _nodeId) external onlyKong {
        NodeEntity storage node = nodesById[_nodeId];
        uint8 actualNodeType = node.nodeType;
        User storage user = nodesOf[_to];

        node.nodeType++;
        node.creationTime = block.timestamp;
        user.nodesTypesAmount[actualNodeType - 1]--;
        totalNodesPerType[actualNodeType - 1]--;
        user.nodesTypesAmount[actualNodeType]++;
        totalNodesPerType[actualNodeType]++;
        emit NodeUpgraded(_to, _nodeId, actualNodeType + 1);
    }

    // STAKE & UNSTAKE
    function stake(
        uint256 _nodeId,
        address _from,
        uint16 _periodStaking
    ) external onlyKong {
        NodeEntity storage node = nodesById[_nodeId];
        if (node.owner != _from) revert NotOwnerNode();
        if (node.startStaking > 0) revert AlreadyStaked();

        node.startStaking = block.timestamp;
        node.periodStaking = _periodStaking;
        emit NodeStaked(_from, _nodeId, _periodStaking);
    }

    function unstake(
        uint256 _nodeId,
        address _from
    ) external onlyKong returns (uint256[3] memory) {
        NodeEntity storage node = nodesById[_nodeId];
        if (node.owner != _from) revert NotOwnerNode();
        if (node.startStaking == 0) revert NotStaked();

        uint256[3] memory rewards = getRewards(_nodeId, 0);
        if (rewards[0] == 0) revert RewardZero();
        node.lastClaimTime = block.timestamp;
        node.startStaking = 0;
        node.periodStaking = 0;
        return rewards;
    }

    // REWARDS
    function claimRewards(
        address _from,
        uint256 _nodeId
    ) external onlyKong returns (uint256[3] memory) {
        NodeEntity memory node = nodesById[_nodeId];
        if (node.owner != _from) revert NotOwnerNode();
        if (node.periodStaking > 0) revert NotAllowedStakingPeriod();
        if (node.startStaking == 0) revert NotStaked();
        uint256[3] memory rewards = getRewards(_nodeId, 0);
        if (rewards[0] == 0) revert RewardZero();
        nodesById[_nodeId].lastClaimTime = block.timestamp;
        return rewards;
    }

    function claimAllRewards(
        address _from
    ) external onlyKong returns (uint256[3] memory) {
        uint256[3] memory totalRewards;
        uint256[] memory nodesIds = nodesOf[_from].nodesIds;

        for (uint256 i; i < nodesIds.length; ++i) {
            // To solve potential revert NotEnoughTime, NotStaked and NotAllowedStakingPeriod
            NodeEntity memory node = nodesById[nodesIds[i]];
            if (node.owner != _from) revert NotOwnerNode();
            uint256 startTime;
            if (node.startStaking > node.lastClaimTime) {
                startTime = node.startStaking;
            } else {
                startTime = node.lastClaimTime;
            }
            uint256 stakedPeriod = (block.timestamp - startTime) /
                stakingPeriod;

            if (
                stakedPeriod > 0 &&
                node.startStaking > 0 &&
                node.periodStaking == 0
            ) {
                uint256[3] memory rewards = getRewards(nodesIds[i], i);
                if (rewards[0] > 0) {
                    totalRewards[0] += rewards[0];
                    totalRewards[1] += rewards[1];
                    totalRewards[2] += rewards[2];
                    nodesById[nodesIds[i]].lastClaimTime = block.timestamp;
                }
            }
        }

        if (totalRewards[0] == 0) revert RewardZero();
        return totalRewards;
    }

    function getRewardsWithoutRandomFees(
        uint256 _nodeId
    ) public view returns (uint256, uint256) {
        NodeEntity memory node = nodesById[_nodeId];
        if (node.owner == address(0)) revert NodeDoesnotExist();
        if (node.startStaking == 0) revert NotStaked();

        uint8 percentageKongFees;
        uint256 kongFees;
        uint256 stakedPeriod;
        uint256 rewards;
        uint256 startTime;

        if (node.startStaking > node.lastClaimTime) {
            startTime = node.startStaking;
        } else {
            startTime = node.lastClaimTime;
        }

        stakedPeriod = (block.timestamp - startTime) / stakingPeriod;
        if (stakedPeriod < 1) revert NotEnoughTime();

        uint period = node.periodStaking;
        if (period > 0 && stakedPeriod > period) {
            stakedPeriod = period;
        }

        rewards = stakedPeriod * rewardPerDayPerType[node.nodeType - 1];

        // BoostAPR and MalusVesting
        if (period > 0) {
            if (stakedPeriod >= period) {
                rewards = (rewards * boostAPR[node.nodeType - 1]) / 10;
            } else {
                rewards -= (rewards * malusPeriodStaking) / 100;
            }
        } else {
            if (rewards > maxRewards) rewards = maxRewards;
        }

        // KongFees
        if (stakedPeriod == 1) {
            percentageKongFees = feesAmountKong[0];
        } else if (stakedPeriod == 2) {
            percentageKongFees = feesAmountKong[1];
        } else if (stakedPeriod == 3) {
            percentageKongFees = feesAmountKong[2];
        } else {
            percentageKongFees = feesAmountKong[3];
        }
        kongFees = (rewards * percentageKongFees) / 100;

        return (rewards, kongFees);
    }

    function getRewards(
        uint256 _nodeId,
        uint256 _nonce
    ) private view returns (uint256[3] memory) {
        uint8 percentageMeetingFees;
        uint256 rewards;
        uint256 kongFees;
        uint256 meetingFees;

        NodeEntity memory node = nodesById[_nodeId];

        (rewards, kongFees) = getRewardsWithoutRandomFees(_nodeId);

        // MeetingFees
        bool isMet = _getRandom(feesChancesMeeting[node.nodeType - 1], _nonce);
        if (isMet) {
            percentageMeetingFees = feesAmountMeeting[node.nodeType - 1];
            meetingFees = (rewards * percentageMeetingFees) / 100;
        }

        rewards -= meetingFees + kongFees;

        return [rewards, meetingFees, kongFees];
    }

    // NODES INFORMATIONS
    function getNodesDataOf(
        address account
    ) external view returns (uint256[] memory, uint256[] memory) {
        return (nodesOf[account].nodesIds, nodesOf[account].nodesTypesAmount);
    }

    function getAllNodesOf(
        address account
    ) external view returns (NodeEntity[] memory) {
        uint256[] memory nodesIds = nodesOf[account].nodesIds;
        uint256 numberOfNodes = nodesOf[account].nodesIds.length;
        NodeEntity[] memory nodes = new NodeEntity[](numberOfNodes);
        for (uint256 i; i < numberOfNodes; ++i) {
            nodes[i] = nodesById[nodesIds[i]];
        }
        return nodes;
    }

    function getRewardPerDayPerType() external view returns (uint8[] memory) {
        return rewardPerDayPerType;
    }

    function getTotalNodesPerType() external view returns (uint256[] memory) {
        return totalNodesPerType;
    }
}

