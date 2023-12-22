// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "./IERC20.sol";
import "./IERC721.sol";
import "./SafeERC20.sol";
import "./IERC721Receiver.sol";
import "./ReentrancyGuard.sol";
import "./Math.sol";

interface IGBT {
    function mustStayGBT(address account) external view returns (uint256);
    function getArtist() external view returns (address);
}

contract XGBT is ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant DURATION = 7 days;

    /* ========== STATE VARIABLES ========== */

    struct Reward {
        uint256 periodFinish;
        uint256 rewardRate;
        uint256 lastUpdateTime;
        uint256 rewardPerTokenStored;
    }

    IERC20 public immutable stakingToken;
    IERC721 public immutable stakingNFT;
    address public immutable factory;
    mapping(address => Reward) public rewardData;
    mapping(address => bool) public isRewardToken;
    address[] public rewardTokens;

    // user -> reward token -> amount
    mapping(address => mapping(address => uint256)) public userRewardPerTokenPaid;
    mapping(address => mapping(address => uint256)) public rewards;

    uint256 private _totalSupply; 
    mapping(address => uint256) private _balances;

    mapping(address => uint256) public balanceToken; // Accounts deposited GBTs
    mapping(address => uint256[]) public balanceNFT; // Accounts deposited NFTs

    uint256 private _totalToken;
    uint256 private _totalNFT;

    /* ========== CONSTRUCTOR ========== */

    constructor(
        address _factory,
        address _stakingToken,
        address _stakingNFT
    ) {
        factory = _factory;
        stakingToken = IERC20(_stakingToken);
        stakingNFT = IERC721(_stakingNFT);
    }

    function addReward(address _rewardsToken) external {
        require(msg.sender == factory || msg.sender == IGBT(address(stakingToken)).getArtist(), "!AUTH");
        require(!isRewardToken[_rewardsToken], "Reward token already exists");
        rewardTokens.push(_rewardsToken);
        isRewardToken[_rewardsToken] = true;
        emit RewardAdded(_rewardsToken);
    } 

    /* ========== VIEWS ========== */

    function balanceOfNFT(address user) external view returns (uint256 length, uint256[] memory arr) {
        return (balanceNFT[user].length, balanceNFT[user]);
    }

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function getRewardTokens() external view returns (address[] memory) {
        return rewardTokens;
    }

    function lastTimeRewardApplicable(address _rewardsToken) public view returns (uint256) {
        return Math.min(block.timestamp, rewardData[_rewardsToken].periodFinish);
    }

    function rewardPerToken(address _rewardsToken) public view returns (uint256) {
        if (_totalSupply == 0) {
            return rewardData[_rewardsToken].rewardPerTokenStored;
        }
        return
            rewardData[_rewardsToken].rewardPerTokenStored + ((lastTimeRewardApplicable(_rewardsToken) - rewardData[_rewardsToken].lastUpdateTime) * rewardData[_rewardsToken].rewardRate * 1e18 / _totalSupply);
    }

    function earned(address account, address _rewardsToken) public view returns (uint256) {
        return (_balances[account] * (rewardPerToken(_rewardsToken) - userRewardPerTokenPaid[account][_rewardsToken]) / 1e18) + rewards[account][_rewardsToken];
    }

    function getRewardForDuration(address _rewardsToken) external view returns (uint256) {
        return rewardData[_rewardsToken].rewardRate * DURATION;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data) public view returns (bytes4) {
        return IERC721Receiver(address(this)).onERC721Received.selector;
    }

    function depositToken(uint256 amount) external nonReentrant updateReward(msg.sender) {
        address account = msg.sender;
        require(amount > 0, "Cannot deposit 0");
        _totalToken += amount;
        _totalSupply += amount;
        
        balanceToken[account] = balanceToken[account] + amount;
        _balances[account] = _balances[account] + amount;
        stakingToken.safeTransferFrom(account, address(this), amount);
        emit Deposited(account, amount);
    }

    function withdrawToken(uint256 amount) external nonReentrant updateReward(msg.sender) {
        address account = msg.sender;
        require(amount > 0, "Cannot withdraw 0");
        require(amount <= balanceToken[account], "Insufficient balance"); 
        _totalToken -= amount;
        _totalSupply -= amount;
        
        balanceToken[account] = balanceToken[account] - amount;
        _balances[account] = _balances[account] - amount;
        require(_balances[account] >= IGBT(address(stakingToken)).mustStayGBT(account), "Borrow debt");
        stakingToken.safeTransfer(msg.sender, amount);
        emit Withdrawn(account, amount);
    }

        /** @dev Stake Gumball(s) NFTs to receive rewards
      * @param _id is an array of Gumballs desired for staking
    */
    function depositNFT(uint256[] calldata _id) external nonReentrant updateReward(msg.sender) {
        address account = msg.sender;
        require(_id.length > 0, "Cannot deposit 0");
        uint256 amount = _id.length * 1e18;
        _totalNFT += amount;
        _totalSupply += amount;
        _balances[account] = _balances[account] + amount;

        for (uint256 i = 0; i < _id.length; i++) {
            balanceNFT[account].push(_id[i]);
            IERC721(stakingNFT).transferFrom(account, address(this), _id[i]);
        }

        emit DepositNFT(msg.sender, address(stakingNFT), _id);
    }

    /** @dev Remove Gumball(s) from the contract and leave staking
      * @param _id is an array of Gumballs desired for unstaking
    */
    function withdrawNFT(uint256[] calldata _id) external nonReentrant updateReward(msg.sender) {
        address account = msg.sender;
        require(balanceNFT[account].length >= _id.length, "Withdrawal underflow");
        uint256 amount = _id.length * 1e18;

        for (uint256 i = 0; i < _id.length; i++) {
            uint256 ind = findNFT(account, _id[i]);
            _pop(account, ind);
        }

        _totalNFT -= amount;
        _totalSupply -= amount;
        _balances[account] = _balances[account] - amount;
        require(_balances[account] >= IGBT(address(stakingToken)).mustStayGBT(account), "Borrow debt");

        for (uint256 i = 0; i <_id.length; i++) {
            IERC721(stakingNFT).transferFrom(address(this), account, _id[i]);
        }

        emit WithdrawNFT(msg.sender, address(stakingNFT), _id);
    }

    function getReward(address account) external nonReentrant updateReward(account) {
        for (uint i; i < rewardTokens.length; i++) {
            address _rewardsToken = rewardTokens[i];
            uint256 reward = rewards[account][_rewardsToken];
            if (reward > 0) {
                rewards[account][_rewardsToken] = 0;
                IERC20(_rewardsToken).safeTransfer(account, reward);
                emit RewardPaid(account, _rewardsToken, reward);
            }
        }
        require(IERC20(stakingToken).balanceOf(address(this)) >= _totalToken);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function notifyRewardAmount(address _rewardsToken, uint256 reward) external updateReward(address(0)) {
        // handle the transfer of reward tokens via `transferFrom` to reduce the number
        // of transactions required and ensure correctness of the reward amount
        require(reward > DURATION, "<DURATION");
        IERC20(_rewardsToken).safeTransferFrom(msg.sender, address(this), reward);

        if (block.timestamp >= rewardData[_rewardsToken].periodFinish) {
            rewardData[_rewardsToken].rewardRate = reward / DURATION;
        } else {
            uint256 remaining = rewardData[_rewardsToken].periodFinish - block.timestamp;
            uint256 leftover = remaining * rewardData[_rewardsToken].rewardRate;
            rewardData[_rewardsToken].rewardRate = (reward + leftover) / DURATION;
        }

        rewardData[_rewardsToken].lastUpdateTime = block.timestamp;
        rewardData[_rewardsToken].periodFinish = block.timestamp + DURATION;
        emit RewardNotified(reward);
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    /** @dev Locates gumball in an array */
    function findNFT(address user, uint256 _id) internal view returns (uint256 _index) {

        uint256 index;
        bool found = false;
        
        for (uint256 i = 0; i < balanceNFT[user].length; i++) {
            if (balanceNFT[user][i] == _id) {
                index = i;
                found = true;
                break;
            } 
        }

        if (!found) {
            revert ("!Found");
        } else {
            return index;
        }
    }

    /** @dev Removes an index from an array */
    function _pop(address user, uint256 _index) internal {
        uint256 tempID;
        uint256 swapID;

        tempID = balanceNFT[user][_index];
        swapID = balanceNFT[user][balanceNFT[user].length - 1];
        balanceNFT[user][_index] = swapID;
        balanceNFT[user][balanceNFT[user].length - 1] = tempID;

        balanceNFT[user].pop();
    }

    /* ========== MODIFIERS ========== */

    modifier updateReward(address account) {
        for (uint i; i < rewardTokens.length; i++) {
            address token = rewardTokens[i];
            rewardData[token].rewardPerTokenStored = rewardPerToken(token);
            rewardData[token].lastUpdateTime = lastTimeRewardApplicable(token);
            if (account != address(0)) {
                rewards[account][token] = earned(account, token);
                userRewardPerTokenPaid[account][token] = rewardData[token].rewardPerTokenStored;
            }
        }
        _;
    }

    /* ========== EVENTS ========== */

    event RewardNotified(uint256 reward);
    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event DepositNFT(address indexed user, address colleciton, uint256[] id);
    event WithdrawNFT(address indexed user, address collection, uint256[] id);
    event RewardPaid(address indexed user, address indexed rewardsToken, uint256 reward);
    event RewardAdded(address reward);
}

contract XGBTFactory {
    address public factory;
    address public lastXGBT;

    event FactorySet(address indexed _factory);

    constructor() {
        factory = msg.sender;
    }

    function setFactory(address _factory) external OnlyFactory {
        factory = _factory;
        emit FactorySet(_factory);
    }

    function createXGBT(
        address _owner,
        address _stakingToken,
        address _stakingNFT
    ) external OnlyFactory returns (address) {
        XGBT newXGBT = new XGBT(_owner, _stakingToken, _stakingNFT);
        lastXGBT = address(newXGBT);
        return lastXGBT;
    }

    modifier OnlyFactory() {
        require(msg.sender == factory, "!AUTH");
        _;
    }
}
