// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./Ownable.sol";
import "./IInsuranceFund.sol";

contract InsuranceFund is IInsuranceFund, Ownable {
    mapping(address => bool) public rewardTrackers;
    event RewardTrackerModified(
        address indexed _address,
        bool _isRewardTracker
    );

    modifier onlyRewardTrackers() {
        require(
            rewardTrackers[msg.sender],
            "InsuranceFund: only reward tracker contract"
        );
        _;
    }

    function withdraw(
        uint256 _amount,
        address _user,
        address _token
    ) external override onlyRewardTrackers {
        IERC20(_token).transfer(_user, _amount);
    }

    function deposit(
        uint256 _amount,
        address _user,
        address _token
    ) external override onlyRewardTrackers {
        IERC20(_token).transferFrom(_user, address(this), _amount);
    }

    function addRewardTracker(
        address _address,
        bool _isRewardTracker
    ) external onlyOwner {
        emit RewardTrackerModified(_address, _isRewardTracker);
        rewardTrackers[_address] = _isRewardTracker;
    }

    function ownerWithdraw(
        address _token,
        address _to,
        uint256 _amount
    ) external onlyOwner {
        IERC20(_token).transfer(_to, _amount);
    }
}

