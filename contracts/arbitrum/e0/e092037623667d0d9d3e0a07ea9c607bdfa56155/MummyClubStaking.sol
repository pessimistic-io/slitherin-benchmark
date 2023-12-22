// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "./IERC20.sol";
import "./SafeERC20.sol";


import "./ReentrancyGuard.sol";
import "./Ownable.sol";
import "./EpochRewardDistributor.sol";
import "./IERC721.sol";
import "./ERC721Enumerable.sol";

import "./IMummyClubNFT.sol";
import "./IEpochRewardDistributor.sol";

contract MummyClubStaking is IERC721Receiver, Ownable, ReentrancyGuard
{
    using SafeERC20 for IERC20;
    struct Memberseat {
        uint256 lastSnapshotIndex;
        uint256 rewardEarned;
    }

    struct BoardroomSnapshot {
        uint256 time;
        uint256 rewardReceived;
        uint256 rewardPerShare;
    }

    /* ========== STATE VARIABLES ========== */
    bool public isInitialized;
    uint256 public totalPower;
    uint256 public totalSupply;
    uint256 public totalRewardDistributed;
    mapping(address => uint256) public balances;
    mapping(address => uint256[]) public depositedNFT;
    mapping(uint256 => address) public stakerOfNFT;

    // epoch
    uint256 public lastEpochTime;
    uint256 public epoch = 0;
    uint256 public epochLength = 0;

    // reward
    uint256 public epochReward;

    address public nft;
    address public reward; // USDC

    address public distributor;

    mapping(address => Memberseat) public members;
    BoardroomSnapshot[] public boardroomHistory;

    mapping(address => bool) public keeper;

    /* ========== EVENTS ========== */

    event Staked(address indexed user, uint256 tokenId, uint256 weight);
    event Withdrawn(address indexed user, uint256 tokenId, uint256 weight);
    event EmergencyWithdraw(
        address indexed user,
        uint256 tokenId
    );
    event RewardPaid(address indexed user, uint256 earned);
    event RewardTaxed(address indexed user, uint256 taxed);
    event RewardAdded(address indexed user, uint256 amount);
    event OnERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes data
    );

    /* ========== Modifiers =============== */

    modifier checkEpoch() {
        uint256 _nextEpochPoint = nextEpochPoint();
        require(block.timestamp >= _nextEpochPoint, "!opened");

        _;

        lastEpochTime = _nextEpochPoint;
        epoch += 1;
    }

    modifier onlyKeeper() {
        require(keeper[msg.sender], "!keeper");
        _;
    }

    modifier memberExists() {
        require(balances[msg.sender] > 0, "The member does not exist");
        _;
    }


    modifier updateReward(address member) {
        if (member != address(0)) {
            _updateReward(member);
        }
        _;
    }

    function _updateReward(address member) internal {
        Memberseat memory seat = members[member];
        seat.rewardEarned = earned(member);
        seat.lastSnapshotIndex = latestSnapshotIndex();
        members[member] = seat;
    }


    /* ========== GOVERNANCE ========== */

    constructor(
        address _nft,
        address _reward,
        uint256 _startTime,
        uint256 _epochLength,
        uint256 _epochReward
    )  {

        reward = _reward;
        nft = _nft;
        BoardroomSnapshot memory genesisSnapshot = BoardroomSnapshot({
        time : block.number,
        rewardReceived : 0,
        rewardPerShare : 0
        });
        boardroomHistory.push(genesisSnapshot);

        epochLength = _epochLength;
        lastEpochTime = _startTime - epochLength;

        epochReward = _epochReward;
        keeper[msg.sender] = true;
    }

    function initialize(
        address _distributor
    ) external onlyOwner {
        require(!isInitialized, "RewardTracker: already initialized");
        isInitialized = true;
        distributor = _distributor;
    }


    function setNextEpochPoint(uint256 _nextEpochPoint) external onlyKeeper {
        require(
            _nextEpochPoint >= block.timestamp,
            "nextEpochPoint could not be the past"
        );
        lastEpochTime = _nextEpochPoint - epochLength;
    }


    function setEpochReward(uint256 _epochReward) external onlyKeeper {
        epochReward = _epochReward;
    }


    function setKeeper(address _address, bool _on) external onlyOwner {
        keeper[_address] = _on;
    }


    function nextEpochPoint() public view returns (uint256) {
        return lastEpochTime + epochLength;
    }


    function latestSnapshotIndex() public view returns (uint256) {
        return boardroomHistory.length - 1;
    }

    function getLatestSnapshot() internal view returns (BoardroomSnapshot memory){
        return boardroomHistory[latestSnapshotIndex()];
    }

    function getLastSnapshotIndexOf(address member) public view returns (uint256)
    {
        return members[member].lastSnapshotIndex;
    }

    function getLastSnapshotOf(address member) internal view returns (BoardroomSnapshot memory){
        return boardroomHistory[getLastSnapshotIndexOf(member)];
    }

    function rewardPerShare() public view returns (uint256) {
        return getLatestSnapshot().rewardPerShare;
    }

    function balanceOf(address _account) public view returns (uint256) {
        uint256[] memory tokenIds = depositedNFT[_account];
        return tokenIds.length;
    }

    function earned(address member) public view returns (uint256) {
        uint256 latestRPS = getLatestSnapshot().rewardPerShare;
        uint256 storedRPS = getLastSnapshotOf(member).rewardPerShare;

        return (balances[member] * (latestRPS - storedRPS)) / 1e18 + members[member].rewardEarned;
    }

    function _stake(address _account, uint256 _tokenId) internal virtual {
        uint256 _power = uint256(IMummyClubNFT(nft).getTokenPower(_tokenId));
        require(_power > 0, "invalid power");
        totalPower += _power;
        totalSupply += 1;
        balances[_account] += _power;
        depositedNFT[_account].push(_tokenId);
        stakerOfNFT[_tokenId] = _account;
        IERC721(nft).safeTransferFrom(_account, address(this), _tokenId);
        emit Staked(_account, _tokenId, _power);
    }

    function tokenOfOwnerByIndex(address _account, uint256 index) external view returns (uint256){
        return depositedNFT[_account][index];
    }

    function _removeUserCard(address _account, uint256 _tokenId) internal returns (bool){
        uint256[] storage tokenIds = depositedNFT[_account];
        uint256 _numCards = tokenIds.length;
        for (uint256 i = 0; i < _numCards; i++) {
            if (tokenIds[i] == _tokenId) {
                if (i < _numCards - 1) {
                    tokenIds[i] = tokenIds[_numCards - 1];
                }
                delete tokenIds[_numCards - 1];
                tokenIds.pop();
                return true;
            }
        }
        return false;
    }

    function _withdraw(address _account, uint256 _tokenId) internal virtual {
        uint256 _power = uint256(IMummyClubNFT(nft).getTokenPower(_tokenId));
        totalPower -= _power;
        totalSupply -= 1;
        balances[msg.sender] -= _power;
        stakerOfNFT[_tokenId] = address(0);
        require(
            _removeUserCard(_account, _tokenId),
            "Can not remove tokenId"
        );
        IERC721(nft).safeTransferFrom(address(this), _account, _tokenId);
        emit Withdrawn(_account, _tokenId, _power);
    }

    function stake(uint256[] memory _tokenIds) external nonReentrant updateReward(msg.sender)
    {
        if (members[msg.sender].rewardEarned > 0) {
            claimReward();
        }
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            _stake(msg.sender, _tokenIds[i]);
        }
    }

    function withdraw(uint256[] memory _tokenIds) external nonReentrant memberExists updateReward(msg.sender)
    {
        if (members[msg.sender].rewardEarned > 0) {
            claimReward();
        }
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            _withdraw(msg.sender, _tokenIds[i]);
        }
    }


    function claimReward() public updateReward(msg.sender) {
        uint256 _earned = members[msg.sender].rewardEarned;
        if (_earned > 0) {
            members[msg.sender].rewardEarned = 0;
            _safeRewardTransfer(msg.sender, _earned);
            emit RewardPaid(msg.sender, _earned);
        }
    }

    function _safeRewardTransfer(address _to, uint256 _amount) internal returns (uint256) {
        IERC20 _reward = IERC20(reward);
        uint256 _rewardBal = _reward.balanceOf(address(this));
        if (_rewardBal > 0) {
            if (_amount > _rewardBal) {
                _reward.safeTransfer(_to, _rewardBal);
                return _rewardBal;
            } else {
                _reward.safeTransfer(_to, _amount);
                return _amount;
            }
        }
        return 0;
    }


    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external override returns (bytes4) {
        emit OnERC721Received(operator, from, tokenId, data);
        return this.onERC721Received.selector;
    }


    function allocateReward() external {
        allocateRewardManually(epochReward);
    }

    function allocateRewardManually(uint256 _rewardAmount) public nonReentrant checkEpoch onlyKeeper
    {

        uint256 _amount = totalPower == 0 ? 0 : _rewardAmount;
        epochReward = _amount;

        // Create & add new snapshot
        uint256 prevRPS = getLatestSnapshot().rewardPerShare;
        uint256 nextRPS = _amount == 0 ? 0 : prevRPS + ((_amount * 1e18) / totalPower);

        BoardroomSnapshot memory newSnapshot = BoardroomSnapshot({
        time : block.number,
        rewardReceived : _amount,
        rewardPerShare : nextRPS
        });
        boardroomHistory.push(newSnapshot);

        IEpochRewardDistributor(distributor).distribute(reward, _amount);
        totalRewardDistributed += _amount;
        emit RewardAdded(msg.sender, _amount);
    }


}

