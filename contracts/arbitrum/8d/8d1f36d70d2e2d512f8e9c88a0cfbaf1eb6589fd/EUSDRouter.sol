// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./SafeMath.sol";
import "./Address.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";
import "./Ownable.sol";


interface IRRouter {
    function withdrawToEDEPool() external ;
}

contract EUSDRouter is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address payable;

    address public rewardRouter;
    address public eusd;

    address[] public destAddressBuffer;
    uint256[] public destWeightBuffer;
    uint256 public destWeightSum;
    uint256 public totalDestNum;
    
    function withdrawToken(address _token, uint256 _amount, address _dest) external onlyOwner {
        IERC20(_token).safeTransfer(_dest, _amount);
    }

    function setAddress(address _rewardRouter, address _eusd) external onlyOwner{
        rewardRouter = _rewardRouter;
        eusd = _eusd;
    }

    function setDistribution(address[] memory _address, uint256[] memory _weights) external onlyOwner{
        destAddressBuffer = _address;
        destWeightBuffer = _weights;
        destWeightSum = 0;
        totalDestNum = destAddressBuffer.length;
        for (uint256 i = 0; i < totalDestNum; i++){
            destWeightSum = destWeightSum.add(destWeightBuffer[i]);
        }
    }

    function withdrawToEDEPool() external {
        IRRouter(rewardRouter).withdrawToEDEPool();
        uint256 cur_balance = IERC20(eusd).balanceOf(address(this));
        uint256[] memory amounts_dist = new uint256[](totalDestNum);
        for (uint256 i = 0; i < totalDestNum; i++){
            amounts_dist[i] = cur_balance.mul(destWeightBuffer[i]).div(destWeightSum);
            IERC20(eusd).transfer(destAddressBuffer[i], amounts_dist[i]);
        }
        emit DistributeEUSD(cur_balance, destAddressBuffer, amounts_dist);
    }


    event DistributeEUSD(uint256 total_eusd, address[] dist, uint256[] amounts);



}
