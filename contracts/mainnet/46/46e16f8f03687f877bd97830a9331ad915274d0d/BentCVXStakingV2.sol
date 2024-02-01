// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.4;

import "./Ownable.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";

import "./Errors.sol";
import "./IBentCVX.sol";
import "./IBentCVXStaking.sol";
import "./IBentCVXRewarder.sol";

contract BentCVXStakingV2 is Ownable, ReentrancyGuard, IBentCVXStaking {
    using SafeERC20 for IERC20;

    event AddRewarder(address indexed rewarder);
    event RemoveRewarder(address indexed rewarder);
    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event ClaimAll(address indexed user);
    event Claim(address indexed user, uint256[][] indexes);
    event OnReward();

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;

    IERC20 public CVX;
    IERC20 public bentCVX;
    IBentCVXRewarder[] public rewarders;
    mapping(address => bool) public isRewarder;

    constructor(address _CVX, address _bentCVX) {
        CVX = IERC20(_CVX);
        bentCVX = IERC20(_bentCVX);
    }

    function mintAndStake(uint256 _amount) external nonReentrant {
        require(_amount != 0, Errors.ZERO_AMOUNT);
        CVX.safeTransferFrom(msg.sender, address(this), _amount);
        CVX.safeApprove(address(bentCVX), _amount);
        IBentCVX(address(bentCVX)).deposit(_amount);

        _mint(msg.sender, _amount);

        for (uint256 i = 0; i < rewarders.length; ++i) {
            if (address(rewarders[i]) == address(0)) {
                continue;
            }

            rewarders[i].deposit(msg.sender, _amount);
        }

        emit Deposit(msg.sender, _amount);
    }

    function addRewarder(address _rewarder) external onlyOwner {
        require(isRewarder[_rewarder] == false, Errors.INVALID_REQUEST);

        rewarders.push(IBentCVXRewarder(_rewarder));
        isRewarder[_rewarder] = true;

        emit AddRewarder(_rewarder);
    }

    function removeRewarder(uint256 _index) external onlyOwner {
        require(
            _index < rewarders.length && isRewarder[address(rewarders[_index])],
            Errors.INVALID_INDEX
        );

        emit RemoveRewarder(address(rewarders[_index]));

        isRewarder[address(rewarders[_index])] = false;
        rewarders[_index] = IBentCVXRewarder(address(0));
    }

    function deposit(uint256 _amount) external {
        depositFor(msg.sender, _amount);
    }

    function depositFor(address _user, uint256 _amount)
        public
        override
        nonReentrant
    {
        require(_amount != 0, Errors.ZERO_AMOUNT);

        bentCVX.safeTransferFrom(msg.sender, address(this), _amount);

        _mint(_user, _amount);

        for (uint256 i = 0; i < rewarders.length; ++i) {
            if (address(rewarders[i]) == address(0)) {
                continue;
            }

            rewarders[i].deposit(_user, _amount);
        }

        emit Deposit(_user, _amount);
    }

    function withdraw(uint256 _amount) external {
        withdrawTo(msg.sender, _amount);
    }

    function withdrawTo(address _recipient, uint256 _amount)
        public
        override
        nonReentrant
    {
        require(
            balanceOf[msg.sender] >= _amount && _amount != 0,
            Errors.INVALID_AMOUNT
        );

        for (uint256 i = 0; i < rewarders.length; ++i) {
            if (address(rewarders[i]) == address(0)) {
                continue;
            }

            rewarders[i].withdraw(msg.sender, _amount);
        }

        _burn(msg.sender, _amount);

        // transfer to _recipient
        bentCVX.safeTransfer(_recipient, _amount);

        emit Withdraw(msg.sender, _amount);
    }

    function claimAll() external virtual {
        claimAllFor(msg.sender);
    }

    function claimAllFor(address _user) public virtual override nonReentrant {
        bool claimed = false;

        for (uint256 i = 0; i < rewarders.length; ++i) {
            if (address(rewarders[i]) == address(0)) {
                continue;
            }

            if (rewarders[i].claimAll(_user)) {
                claimed = true;
            }
        }

        require(claimed, Errors.NO_PENDING_REWARD);

        emit ClaimAll(_user);
    }

    function claim(uint256[][] memory _indexes) external {
        claimFor(msg.sender, _indexes);
    }

    function claimFor(address _user, uint256[][] memory _indexes)
        public
        nonReentrant
    {
        require(_indexes.length == rewarders.length, Errors.INVALID_INDEX);

        bool claimed = false;
        for (uint256 i = 0; i < _indexes.length; ++i) {
            if (address(rewarders[i]) == address(0)) {
                continue;
            }

            if (rewarders[i].claim(_user, _indexes[i])) {
                claimed = true;
            }
        }
        require(claimed, Errors.NO_PENDING_REWARD);

        emit Claim(_user, _indexes);
    }

    function _mint(address _user, uint256 _amount) internal {
        balanceOf[_user] += _amount;
        totalSupply += _amount;
    }

    function _burn(address _user, uint256 _amount) internal {
        balanceOf[_user] -= _amount;
        totalSupply -= _amount;
    }
}

