// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// 使用SafeMath和SafeERC20库进行数值计算和转账操作
// 使用Initializable和OwnableUpgradeable实现可升级的智能合约功能
import "./Math.sol";
import "./SafeMathUpgradeable.sol";
import "./Initializable.sol";
import "./OwnableUpgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./IERC20Upgradeable.sol";

contract TokenAirdrop is Initializable, OwnableUpgradeable {
    using SafeMathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    // 空投代币
    address public rewardToken;
    // 账户余额：用户当前空投代币的数量
    mapping(address => uint256) private _balances;
    // 总空投量
    uint256 public reward = 0;
    // 剩余空头量
    uint256 public remainingReward = 0;
    // 结束时间
    uint256 public endTime;

    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event InitializedEvent(
        address rewardToken,
        uint256 endTime,
        address owner,
        uint256 reward
    );
    event RewardNotified(
        uint256 reward,
        address[] recipients,
        uint256[] values
    );

    // 检查空投是否已经结束
    modifier checkEndOwner() {
        require(block.timestamp >= endTime, "TokenAirdrop: not end");
        _;
    }

    // 检查空投是否已经结束，用户视角
    modifier checkEndUser() {
        require(block.timestamp < endTime, "TokenAirdrop: already end");
        _;
    }

    // 更新用户空投数据
    modifier updateReward(address account) {
        _;

        uint256 userReward = balanceOf(account);

        if (userReward > 0) {
            // 将当前用户余额置空
            _balances[account] = 0;
            // 剩余空头量减去当前用户空投量
            remainingReward = remainingReward.sub(userReward);

            emit RewardPaid(account, userReward);
        }
    }

    // 检查remainingReward是否大于0
    modifier checkRemainingReward() {
        require(remainingReward > 0, "TokenAirdrop: no remaining reward");
        _;
    }

    // 初始化函数，由升级合约调用
    function initialize(
        address _rewardToken,
        uint256 _endTime,
        address _owner,
        uint256 _reward,
        address[] memory _recipients,
        uint256[] memory _values
    ) external initializer {
        // 调用父合约的初始化函数
        super.__Ownable_init();

        // 初始化各个参数
        rewardToken = _rewardToken;
        endTime = _endTime;

        // 改，2023.03.09，新增
        notifyRewardAmount(_reward, _recipients, _values);

        // 改，2023.03.09，改变该函数位置，之前在super.__Ownable_init();后面
        // 转移所有权
        transferOwnership(_owner);

        emit InitializedEvent(_rewardToken, _endTime, _owner, _reward);
    }

    // 查询用户空投代币余额
    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    // 创建者在项目结束后取出剩余空投
    function withdraw() public onlyOwner checkEndOwner checkRemainingReward {
        // 将剩余空投量转移给创建者
        IERC20Upgradeable(rewardToken).safeTransfer(
            msg.sender,
            remainingReward
        );

        remainingReward = 0;

        emit Withdrawn(msg.sender, remainingReward);
    }

    // 领取空投函数
    function getReward() public checkEndUser updateReward(msg.sender) {
        uint256 userReward = balanceOf(msg.sender);

        if (userReward > 0) {
            IERC20Upgradeable(rewardToken).safeTransfer(msg.sender, userReward);
        }
    }

    // 改，2023.03.09，external ==> public
    // 设置空投数量、空投接收者和空投数量
    function notifyRewardAmount(
        uint256 _reward,
        address[] memory _recipients,
        uint256[] memory _values
    ) public onlyOwner {
        require(
            _recipients.length == _values.length,
            "TokenAirdrop: recipients and values length mismatch"
        );

        reward = _reward;
        remainingReward = _reward;

        // 将_recipients中的每个地址和空投数量添加到_balances中
        for (uint256 i = 0; i < _recipients.length; i++) {
            _balances[_recipients[i]] = _values[i];
        }

        emit RewardNotified(_reward, _recipients, _values);
    }
}

