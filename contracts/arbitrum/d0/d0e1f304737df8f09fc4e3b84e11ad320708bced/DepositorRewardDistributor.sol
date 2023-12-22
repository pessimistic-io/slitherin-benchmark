// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

import { Initializable } from "./Initializable.sol";
import { IERC20Upgradeable } from "./IERC20Upgradeable.sol";
import { SafeERC20Upgradeable } from "./SafeERC20Upgradeable.sol";
import { ReentrancyGuardUpgradeable } from "./ReentrancyGuardUpgradeable.sol";
import { OwnableUpgradeable } from "./OwnableUpgradeable.sol";
import { AddressUpgradeable } from "./AddressUpgradeable.sol";

import { IBaseReward } from "./IBaseReward.sol";
import { IDepositorRewardDistributor } from "./IDepositorRewardDistributor.sol";

contract DepositorRewardDistributor is Initializable, ReentrancyGuardUpgradeable, OwnableUpgradeable, IDepositorRewardDistributor {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using AddressUpgradeable for address;

    uint256 private constant PRECISION = 1e18;
    uint256 private constant MAX_EXTRA_REWARDS_SIZE = 8; // WETH, USDT, USDC, WBTC, DAI, LINK, UNI, FRAX

    address public stakingToken;
    address public rewardToken;
    address[] public extraRewards;

    mapping(address => bool) private distributors;

    modifier onlyDistributors() {
        require(isDistributor(msg.sender), "DepositorRewardDistributor: Caller is not the distributor");
        _;
    }

    // @custom:oz-upgrades-unsafe-allow constructor
    // solhint-disable-next-line no-empty-blocks
    constructor() initializer {}

    function initialize(address _rewardToken, address _stakingToken) external initializer {
        require(_rewardToken != address(0), "DepositorRewardDistributor: _rewardToken cannot be 0x0");
        require(_stakingToken != address(0), "DepositorRewardDistributor: _stakingToken cannot be 0x0");

        require(_rewardToken.isContract(), "DepositorRewardDistributor: _rewardToken is not a contract");
        require(_stakingToken.isContract(), "DepositorRewardDistributor: _stakingToken is not a contract");

        __ReentrancyGuard_init();
        __Ownable_init();

        rewardToken = _rewardToken;
        stakingToken = _stakingToken;
    }

    function extraRewardsLength() external view returns (uint256) {
        return extraRewards.length;
    }

    function addExtraReward(address _reward) external onlyOwner returns (bool) {
        require(_reward != address(0), "DepositorRewardDistributor: Address cannot be 0");
        require(IBaseReward(_reward).stakingToken() == stakingToken, "DepositorRewardDistributor: Mismatched staking token");
        require(IBaseReward(_reward).rewardToken() == rewardToken, "DepositorRewardDistributor: Mismatched reward token");
        require(extraRewards.length <= MAX_EXTRA_REWARDS_SIZE, "DepositorRewardDistributor: Maximum limit exceeded");

        extraRewards.push(_reward);

        emit AddExtraReward(_reward);

        return true;
    }

    function clearExtraRewards() external onlyOwner {
        delete extraRewards;

        emit ClearExtraRewards();
    }

    function addDistributor(address _distributor) public onlyOwner {
        require(_distributor != address(0), "DepositorRewardDistributor: _distributor cannot be 0");
        require(!isDistributor(_distributor), "DepositorRewardDistributor: _distributor is already distributor");

        distributors[_distributor] = true;

        emit NewDistributor(msg.sender, _distributor);
    }

    function addDistributors(address[] calldata _distributors) external onlyOwner {
        for (uint256 i = 0; i < _distributors.length; i++) {
            addDistributor(_distributors[i]);
        }
    }

    function removeDistributor(address _distributor) external onlyOwner {
        require(_distributor != address(0), "DepositorRewardDistributor: _distributor cannot be 0");
        require(isDistributor(_distributor), "DepositorRewardDistributor: _distributor is not the distributor");

        distributors[_distributor] = false;

        emit RemoveDistributor(msg.sender, _distributor);
    }

    function isDistributor(address _distributor) public view returns (bool) {
        return distributors[_distributor];
    }

    function distribute(uint256 _rewards) external override nonReentrant onlyDistributors {
        if (_rewards > 0) {
            IERC20Upgradeable(rewardToken).safeTransferFrom(msg.sender, address(this), _rewards);

            _rewards = IERC20Upgradeable(rewardToken).balanceOf(address(this));

            for (uint256 i = 0; i < extraRewards.length; i++) {
                uint256 totalSupply = IERC20Upgradeable(stakingToken).totalSupply();
                uint256 balance = IERC20Upgradeable(stakingToken).balanceOf(extraRewards[i]);
                uint256 ratio = (balance * PRECISION) / totalSupply;
                uint256 amounts = (_rewards * ratio) / PRECISION;

                _approve(rewardToken, extraRewards[i], amounts);

                IBaseReward(extraRewards[i]).distribute(amounts);

                emit Distribute(extraRewards[i], _rewards);
            }
        }
    }

    function _approve(
        address _token,
        address _spender,
        uint256 _amount
    ) internal {
        IERC20Upgradeable(_token).safeApprove(_spender, 0);
        IERC20Upgradeable(_token).safeApprove(_spender, _amount);
    }
}

