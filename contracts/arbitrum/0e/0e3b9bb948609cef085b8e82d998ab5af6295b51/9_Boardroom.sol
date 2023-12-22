// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./Address.sol";
import "./SafeMath.sol";
import "./IERC165.sol";
import "./SafeERC20.sol";
import "./IERC721.sol";
import "./ContractGuard.sol";
import "./ITreasury.sol";
import "./Operator.sol";

interface ILKEY {
    function walletOfOwner(address owner) external view returns (uint256[] memory);
}

contract ShareWrapper {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IERC721 public LKEY;

    mapping (address => uint256[]) public stakedIds;

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address _account) public view returns (uint256) {
        return _balances[_account];
    }

    function stake(uint256 amount) public virtual {
        uint256[] memory tokenId = ILKEY(address(LKEY)).walletOfOwner(msg.sender);
        if(tokenId.length >= amount) {
            for(uint256 i; i < amount; i++) {
                LKEY.transferFrom(address(msg.sender), address(this), tokenId[i]);
                stakedIds[msg.sender].push(tokenId[i]);
            }
            _balances[msg.sender] = _balances[msg.sender].add(amount);
            _totalSupply = _totalSupply.add(amount);
        }        
        
    }

    function withdraw(uint256 amount) public virtual {
        uint256 boardroomShare = _balances[msg.sender];
        uint256[] storage tokenIds = stakedIds[msg.sender];
        require(boardroomShare >= amount, "Boardroom: withdraw request greater than staked amount");
        for(uint256 i; i < amount; i++) {
            LKEY.transferFrom(address(this), address(msg.sender), tokenIds[tokenIds.length - 1]);
            tokenIds.pop();
        }
        _totalSupply = _totalSupply.sub(amount);
        _balances[msg.sender] = boardroomShare.sub(amount);
        stakedIds[msg.sender] = tokenIds;
    }

    function getStakedIds(address account) public view returns(uint256[] memory) {
        uint256[] memory tokenIds = stakedIds[account];
        return tokenIds;
    }

    function getArrayIds(address account) public view returns(uint256[] memory) {
        uint256 len = stakedIds[account].length;
        uint256[] memory tokenIds = new uint256[](len);
        for(uint256 i = 0; i < len; i++) {
            tokenIds[i] = stakedIds[account][i];
        }
        return tokenIds;
    }

}

contract Boardroom is ShareWrapper, ContractGuard, Operator {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    /* ========== DATA STRUCTURES ========== */

    struct Memberseat {
        uint256 lastSnapshotIndex;
        uint256 rewardEarned;
        uint256 epochTimerStart;
    }

    struct BoardroomSnapshot {
        uint256 time;
        uint256 rewardReceived;
        uint256 rewardPerShare;
    }

    /* ========== STATE VARIABLES ========== */

    // flags
    bool public initialized = false;

    IERC20 public PETH;
    ITreasury public treasury;

    mapping(address => Memberseat) public members;
    BoardroomSnapshot[] public boardroomHistory;

    uint256 public withdrawLockupEpochs;
    uint256 public rewardLockupEpochs;

    /* ========== EVENTS ========== */

    event Initialized(address indexed executor, uint256 at);
    event TreasuryUpdated(address indexed treasury);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardAdded(address indexed user, uint256 reward);

    /* ========== Modifiers =============== */

    modifier memberExists() {
        require(balanceOf(msg.sender) > 0, "The member does not exist");
        _;
    }

    modifier updateReward(address _member) {
        if (_member != address(0)) {
            Memberseat memory seat = members[_member];
            seat.rewardEarned = earned(_member);
            seat.lastSnapshotIndex = latestSnapshotIndex();
            members[_member] = seat;
        }
        _;
    }

    modifier notInitialized() {
        require(!initialized, "already initialized");
        _;
    }

    /* ========== GOVERNANCE ========== */

    function initialize(
        IERC20 _PETH,
        IERC721 _LKEY,
        ITreasury _treasury
    ) public notInitialized {
        PETH = _PETH;
        LKEY = _LKEY;
        treasury = _treasury;

        BoardroomSnapshot memory genesisSnapshot = BoardroomSnapshot({time: block.number, rewardReceived: 0, rewardPerShare: 0});
        boardroomHistory.push(genesisSnapshot);

        withdrawLockupEpochs = 6; // Lock for 4 epochs (48h) before release withdraw
        rewardLockupEpochs = 3; // Lock for 3 epochs (24h) before release claimReward

        initialized = true;
        emit Initialized(msg.sender, block.number);
    }

    function setLockUp(uint256 _withdrawLockupEpochs, uint256 _rewardLockupEpochs) external onlyOperator {
        require(_withdrawLockupEpochs >= _rewardLockupEpochs && _withdrawLockupEpochs <= 56, "_withdrawLockupEpochs: out of range"); // <= 2 week
        withdrawLockupEpochs = _withdrawLockupEpochs;
        rewardLockupEpochs = _rewardLockupEpochs;
    }

    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "Treasury should be non-zero address");
        treasury = ITreasury(_treasury);
        emit TreasuryUpdated(_treasury);
    }

    /* ========== VIEW FUNCTIONS ========== */

    // =========== Snapshot getters

    function latestSnapshotIndex() public view returns (uint256) {
        return boardroomHistory.length.sub(1);
    }

    function getLatestSnapshot() internal view returns (BoardroomSnapshot memory) {
        return boardroomHistory[latestSnapshotIndex()];
    }

    function getLastSnapshotIndexOf(address _member) public view returns (uint256) {
        return members[_member].lastSnapshotIndex;
    }

    function getLastSnapshotOf(address _member) internal view returns (BoardroomSnapshot memory) {
        return boardroomHistory[getLastSnapshotIndexOf(_member)];
    }

    function canWithdraw(address _member) external view returns (bool) {
        return members[_member].epochTimerStart.add(withdrawLockupEpochs) <= treasury.epoch();
    }

    function canClaimReward(address _member) external view returns (bool) {
        return members[_member].epochTimerStart.add(rewardLockupEpochs) <= treasury.epoch();
    }

    function epoch() external view returns (uint256) {
        return treasury.epoch();
    }

    function nextEpochPoint() external view returns (uint256) {
        return treasury.nextEpochPoint();
    }

    function getPETHPrice() external view returns (uint256) {
        return treasury.getPETHPrice();
    }

    // =========== Member getters

    function rewardPerShare() public view returns (uint256) {
        return getLatestSnapshot().rewardPerShare;
    }

    function earned(address _member) public view returns (uint256) {
        uint256 latestRPS = getLatestSnapshot().rewardPerShare;
        uint256 storedRPS = getLastSnapshotOf(_member).rewardPerShare;

        return balanceOf(_member).mul(latestRPS.sub(storedRPS)).div(1e18).add(members[_member].rewardEarned);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function stake(uint256 _amount) public override onlyOneBlock updateReward(msg.sender) {
        require(_amount > 0, "Stake amount should be bigger than 0");
        super.stake(_amount);
        members[msg.sender].epochTimerStart = treasury.epoch(); // reset timer
        emit Staked(msg.sender, _amount);
    }

    function withdraw(uint256 _amount) public override onlyOneBlock memberExists updateReward(msg.sender) {
        require(_amount > 0, "Withdraw amount should be bigger than 0");
        require(members[msg.sender].epochTimerStart.add(withdrawLockupEpochs) <= treasury.epoch(), "Withdraw is still locked");
        claimReward();
        super.withdraw(_amount);
        emit Withdrawn(msg.sender, _amount);
    }

    function exit() external {
        withdraw(balanceOf(msg.sender));
    }

    function claimReward() public updateReward(msg.sender) {
        uint256 reward = members[msg.sender].rewardEarned;
        if (reward > 0) {
            require(members[msg.sender].epochTimerStart.add(rewardLockupEpochs) <= treasury.epoch(), "still in reward lockup");
            members[msg.sender].epochTimerStart = treasury.epoch(); // reset timer
            members[msg.sender].rewardEarned = 0;
            PETH.safeTransfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    function allocateSeigniorage(uint256 _amount) external onlyOneBlock onlyOperator {
        require(_amount > 0, "Allocate amount should be bigger than 0");
        require(totalSupply() > 0, "Cannot allocate when totalSupply is 0");

        // Create & add new snapshot
        uint256 prevRPS = getLatestSnapshot().rewardPerShare;
        uint256 nextRPS = prevRPS.add(_amount.mul(1e18).div(totalSupply()));

        BoardroomSnapshot memory newSnapshot = BoardroomSnapshot({time: block.number, rewardReceived: _amount, rewardPerShare: nextRPS});
        boardroomHistory.push(newSnapshot);

        PETH.safeTransferFrom(msg.sender, address(this), _amount);
        emit RewardAdded(msg.sender, _amount);
    }

    function governanceRecoverUnsupported(
        IERC20 _token,
        uint256 _amount,
        address _to
    ) external onlyOperator {
        // do not allow to drain core tokens
        require(address(_token) != address(PETH), "Shouldn't drain $PETH from ARK");
        require(address(_token) != address(LKEY), "Shouldn't drain $AKA NFT from ARK");
        _token.safeTransfer(_to, _amount);
    }
}
