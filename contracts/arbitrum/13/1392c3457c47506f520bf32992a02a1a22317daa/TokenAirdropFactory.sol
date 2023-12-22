// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// 引入开源的 Ownable 合约，它允许只有合约的所有者（即部署者）可以调用某些方法
import "./Ownable.sol";
// 引入开源的 Clones 合约，它允许通过复制现有合约来创建新的合约实例
import "./Clones.sol";
// 引入开源的 IERC20 合约和 SafeERC20 库，它们提供了安全的 ERC20 代币转账功能
import "./SafeERC20Upgradeable.sol";
import "./IERC20Upgradeable.sol";
import "./TokenAirdrop.sol";

contract TokenAirdropFactory is Ownable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    uint256 public fee;
    address public cloneAddress;

    event CampaignCreated(
        address indexed creator,
        address indexed campaignAddress
    );
    event FeeUpdated(uint256 oldFee, uint256 newFee);
    event FeesWithdrawn(address indexed to, uint256 amount);

    // 保存每个创建者创建的合约地址
    mapping(address => address[]) private creatorToCampaigns;

    // 改，2023.03.15，避免用户过多支付费用
    modifier feePaid() {
        require(msg.value >= fee, "Fee");
        _;
        uint256 excess = msg.value - fee;
        if (excess > 0) {
            payable(msg.sender).transfer(excess);
        }
    }

    constructor(uint256 _fee, address _cloneAddress) {
        fee = _fee;
        cloneAddress = _cloneAddress;
    }

    function createCampaign(
        address _rewardToken,
        uint256 _endTime,
        uint256 _reward,
        address[] memory _recipients,
        uint256[] memory _values
    ) external payable feePaid returns (address campaignAddress) {
        // 使用 Clones 合约复制一个新的 TokenAirdrop 合约实例
        campaignAddress = Clones.clone(cloneAddress);

        // 调用 TokenAirdrop 的初始化函数，对合约进行初始化设置
        TokenAirdrop tokenAirdrop = TokenAirdrop(campaignAddress);
        tokenAirdrop.initialize(
            _rewardToken,
            _endTime,
            msg.sender,
            _reward,
            _recipients,
            _values
        );

        // 从调用者的钱包中转账奖励代币到新创建的 TokenAirdrop 合约实例中
        IERC20Upgradeable(_rewardToken).safeTransferFrom(
            msg.sender,
            campaignAddress,
            _reward
        );

        // 改，2023.03.09，将该函数移至TokenAirdrop内部，不然会出现`Ownable: caller is not the owner`错误
        // msg.sender会在前面步骤中改变
        // tokenAirdrop.notifyRewardAmount(_reward);

        // 将新创建的合约地址存入映射中
        creatorToCampaigns[msg.sender].push(campaignAddress);

        emit CampaignCreated(msg.sender, campaignAddress);

        return campaignAddress;
    }

    function setFee(uint256 newFee) external onlyOwner {
        uint256 oldFee = fee;
        fee = newFee;
        emit FeeUpdated(oldFee, newFee);
    }

    function setCloneAddress(address _cloneAddress) external onlyOwner {
        cloneAddress = _cloneAddress;
    }

    // 获取某个创建者创建的所有合约地址
    function getCampaignsByCreator(address creator)
        external
        view
        returns (address[] memory)
    {
        return creatorToCampaigns[creator];
    }

    // 改，2023.04.29，新增
    // 取走合约中的所有手续费
    function withdrawFees() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No fees available to withdraw");
        payable(msg.sender).transfer(balance);
        emit FeesWithdrawn(msg.sender, balance);
    }
}

