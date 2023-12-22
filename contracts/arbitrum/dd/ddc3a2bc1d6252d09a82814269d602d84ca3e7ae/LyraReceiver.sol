// SPDX-License-Identifier: MIT
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";
import "./Ownable.sol";

pragma solidity ^0.8.4;

interface IRewardRouterV2 {
    function mintAndStakeGlp(address _token, uint256 _amount, uint256 _minUsdg, uint256 _minGlp) external returns (uint256);
}

interface IStakedGlp {
    function transfer(address _recipient, uint256 _amount) external returns (bool);
    function approve(address _spender, uint256 _amount) external returns (bool);
}

contract SocketGMXGlp is Ownable, ReentrancyGuard {
    // VARIABLES
    using SafeERC20 for IERC20;
    address public rewardRouterV2;
    address public stakedGlp;
    address public glpManager;

    constructor (address _rewardRouterV2, address _stakedGlp, address _glpManager) Ownable() {
        rewardRouterV2 = _rewardRouterV2;
        stakedGlp = _stakedGlp;
        glpManager = _glpManager;
    }
    
    function buyGlp(address _receiver, address _token, uint256 _minUsdg, uint256 _minGlp) external nonReentrant {
        uint256 amount = IERC20(_token).allowance(msg.sender, address(this));
        IERC20(_token).safeTransferFrom(msg.sender, address(this), amount);
        IERC20(_token).safeApprove(glpManager, amount);
        try IRewardRouterV2(rewardRouterV2).mintAndStakeGlp(_token, amount, _minUsdg, _minGlp) returns (uint256 glpAmount) {
            IStakedGlp(stakedGlp).transfer(_receiver, glpAmount);
        } catch {
            IERC20(_token).safeTransfer(_receiver, amount);
            IERC20(_token).safeDecreaseAllowance(glpManager, amount);
        }
    }

    function rescueFunds(
        address _token,
        address _userAddress,
        uint256 _amount
    ) external onlyOwner {
        IERC20(_token).safeTransfer(_userAddress, _amount);
    }
}
