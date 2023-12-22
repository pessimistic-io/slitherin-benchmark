// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.18;

import { ERC20 } from "./ERC20.sol";
import { IERC20 } from "./IERC20.sol";
import { IERC20Tax } from "./IERC20Tax.sol";
import { ERC20TaxReferenced } from "./ERC20TaxReferenced.sol";


contract FireDogeStakingPool is ERC20TaxReferenced {

    struct UserPosition {
        uint256 depositedTokenAmount;
        uint256 rewardsPerShareX18WhenDeposited;
    }

    mapping(address => UserPosition) public positions;

    uint256 public rewardsPerShareX18;
    uint256 public totalDeposited;

    IERC20 public immutable WETH;

    event Deposit(
        address user,
        uint256 amount
    );

    event Withdrawal(
        address user,
        uint256 amount
    );

    event Claim(
        address user,
        uint256 wethReward
    );

    constructor(IERC20 _weth) {
        WETH = _weth;
    }

    function injectRewards(uint256 _amount) public {
        if (totalDeposited != 0) {
            rewardsPerShareX18 += 1e18 * _amount / totalDeposited;
        }
        WETH.transferFrom(
            msg.sender,
            address(this),
            _amount
        );
        // And otherwise nobody earnes fees at this moment
    }

    function deposit(uint256 _amount) public {
        totalDeposited += _amount;
        positions[msg.sender] = UserPosition({
            depositedTokenAmount: _amount,
            rewardsPerShareX18WhenDeposited: rewardsPerShareX18
        });

        TOKEN.transferFromWithoutFee(
            msg.sender,
            address(this),
            _amount
        );

        emit Deposit(
            msg.sender,
            _amount
        );
    }

    function withdraw() public {
        UserPosition storage _userPosition = positions[msg.sender];
        require(_userPosition.depositedTokenAmount > 0, "Nothing to withdraw");

        _claim(msg.sender);

        totalDeposited -= _userPosition.depositedTokenAmount;

        TOKEN.transferWithoutFee(
            msg.sender,
            _userPosition.depositedTokenAmount
        );
        _userPosition.depositedTokenAmount = 0;

        emit Withdrawal(
            msg.sender,
            _userPosition.depositedTokenAmount
        );
    }

    function claim() public {
        _claim(msg.sender);
    }

    function _claim(address _user) private {
        UserPosition storage _userPosition = positions[_user];

        uint256 _earnedRewardsPerShareX18 = rewardsPerShareX18 - _userPosition.rewardsPerShareX18WhenDeposited;
        uint256 _earnedRewards = _earnedRewardsPerShareX18 * _userPosition.depositedTokenAmount / 1e18;

        _userPosition.rewardsPerShareX18WhenDeposited = rewardsPerShareX18;

        WETH.transfer(_user, _earnedRewards);
        emit Claim(
            msg.sender,
            _earnedRewards
        );
    }
}


