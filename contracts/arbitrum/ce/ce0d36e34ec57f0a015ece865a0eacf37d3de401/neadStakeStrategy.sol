// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./AccessControlEnumerable.sol";
import "./IERC20.sol";
import "./Initializable.sol";

import "./INeadStake.sol";
import "./ISwappoor.sol";

contract neadStakeStrategy is Initializable, AccessControlEnumerable {
    bytes32 public constant TIMELOCK_ROLE = keccak256("TIMELOCK_ROLE");
    bytes32 public constant SETTER_ROLE = keccak256("SETTER_ROLE");

    address public platformFeeReceiver;
    address public vault;
    address public swappoor;
    address public immutable neadStake;
    address public immutable asset;
    address[] rewards;

    uint constant basis = 1000;
    uint public treasuryFee;
    uint public harvestFee;

    event Reinvest(address indexed caller, uint bounty, uint fee, uint amount);
    event RewardAdded(address reward);
    event RewardRemoved(address reward);
    event EmergencyWithdrawn(address indexed to, uint amount);

    constructor(
        address _admin,
        address _timelock,
        address _setter,
        address _neadStake,
        address _asset,
        address _swappoor
    ) {
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(SETTER_ROLE, _setter);
        _grantRole(TIMELOCK_ROLE, _timelock);
        _setRoleAdmin(TIMELOCK_ROLE, TIMELOCK_ROLE);

        platformFeeReceiver = _admin;
        neadStake = _neadStake;
        asset = _asset;
        swappoor = _swappoor;

        IERC20(asset).approve(_neadStake, type(uint).max);

        address[] memory _rewards = INeadStake(neadStake).rewardsList();
        uint len = _rewards.length;
        for (uint i; i < len; ++i) {
            IERC20(_rewards[i]).approve(_swappoor, type(uint).max);
        }
        rewards = _rewards;
        treasuryFee = 10;
    }

    function initialize(address _vault) external initializer {
        vault = _vault;
        IERC20(asset).approve(_vault, type(uint).max);
    }

    function registerStake(uint amount) external {
        require(msg.sender == vault, "!vault");
        INeadStake(neadStake).deposit(amount);
    }

    function unregisterStake(uint amount) external {
        require(msg.sender == vault, "!vault");
        INeadStake(neadStake).withdraw(amount);
    }

    function reinvest(address to) external {
        INeadStake(neadStake).getReward();
        address[] memory _rewards = rewards;
        uint len = _rewards.length;

        uint amount;
        address _asset = asset;

        unchecked {
            for (uint i; i < len; ++i) {
                uint bal = IERC20(_rewards[i]).balanceOf(address(this));
                if (_rewards[i] == _asset) {
                    amount += bal;
                } else {
                    amount += ISwappoor(swappoor).swapTokens(
                        _rewards[i],
                        _asset,
                        bal
                    );
                }
            }
        }

        // calculate fees
        // shit never under/overflows, would also revert if ever...
        uint treasury;
        uint harvest;
        unchecked {
            treasury = (amount * treasuryFee) / basis;
            harvest = (amount * harvestFee) / basis;
        }

        IERC20(asset).transfer(platformFeeReceiver, treasury);
        IERC20(asset).transfer(to, harvest);
        unchecked {
            amount -= (treasury + harvest);
        }

        INeadStake(neadStake).deposit(amount);
        emit Reinvest(msg.sender, harvest, treasury, amount);
    }

    function setFees(
        uint _treasuryFee,
        uint _harvestFee
    ) external onlyRole(SETTER_ROLE) {
        treasuryFee = _treasuryFee;
        harvestFee = _harvestFee;
    }

    function setFeeReceiver(address receiver) external onlyRole(SETTER_ROLE) {
        platformFeeReceiver = receiver;
    }

    function getTotalStaked() external view returns (uint total) {
        total = INeadStake(neadStake).balanceOf(address(this));
    }

    function rewardsList() external view returns (address[] memory _rewards) {
        _rewards = rewards;
    }

    /// @notice manually claims rewards from neadStake and sends to msg.sender. Not expected to be called on a regular basis but leaving as a contingency
    function manualClaimRewards(address token) external onlyRole(SETTER_ROLE) {
        INeadStake(neadStake).getReward(); // neadStake getReward claims all tokens
        if (token != address(0)) {
            // any remaining tokens in the contract will be reinvested in the next reinvest() call
            uint bal = IERC20(token).balanceOf(address(this));
            IERC20(token).transfer(msg.sender, bal);
        } else {
            address[] memory _rewards = rewards;
            uint len = _rewards.length;
            for (uint i; i < len; ++i) {
                uint bal = IERC20(_rewards[i]).balanceOf(address(this));
                if (bal > 0) {
                    IERC20(token).transfer(msg.sender, bal);
                }
            }
        }
    }

    function addReward(address token) external onlyRole(SETTER_ROLE) {
        rewards.push(token);
        IERC20(token).approve(swappoor, type(uint).max);
        emit RewardAdded(token);
    }

    function removeReward(address token) external onlyRole(SETTER_ROLE) {
        address[] memory _rewards = rewards;
        uint len = _rewards.length;
        uint idx;

        // get reward token index
        for (uint i; i < len; ++i) {
            if (_rewards[i] == token) {
                idx = i;
            }
        }

        // remove from rewards list
        for (uint256 i = idx; i < len - 1; ++i) {
            rewards[i] = rewards[i + 1];
        }
        rewards.pop();
        emit RewardRemoved(token);
    }

    /// @notice withdraws the entire balance of the strategy and sends to `_to`, contingency measure just in case something goes wrong. Function is timelocked.
    function emergencyWithdraw(
        address _to,
        uint amount
    ) external onlyRole(TIMELOCK_ROLE) {
        INeadStake(neadStake).withdraw(amount);
        IERC20(asset).transfer(_to, amount);
        emit EmergencyWithdrawn(_to, amount);
    }
}

