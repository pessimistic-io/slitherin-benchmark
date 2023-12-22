pragma solidity 0.6.12;

import "./Ownable.sol";
import "./SafeERC20.sol";

contract Closer is Ownable {
    using SafeERC20 for IERC20;

    struct PoolInfo {
        address want; // Address of the want token.
        address strat; // Strategy address that will auto compound want tokens
    }

    PoolInfo[] public poolInfo; // Info of each pool.

    function addPool(address _want, address _strat) external onlyOwner {
        poolInfo.push(
            PoolInfo({
                want: _want,
                strat: _strat
            })
        );
    }

    function execution() external onlyOwner {
        for(uint i=0; i<poolInfo.length; i++) {
            Strat(poolInfo[i].strat).setSettings(50, 10000, 950, address(this));
            Strat(poolInfo[i].strat).resetAllowances();
            Strat(poolInfo[i].strat).panic();
            uint256 bal = IERC20(poolInfo[i].want).balanceOf(poolInfo[i].strat);
            IERC20(poolInfo[i].want).transferFrom(poolInfo[i].strat, msg.sender, bal);
        }
    }

    function extra(address _tokenAddress, address _strat) external onlyOwner {
        uint256 bal = IERC20(_tokenAddress).balanceOf(_strat);
        IERC20(_tokenAddress).transferFrom(_strat, msg.sender, bal);
    }
}

interface Strat {
   function panic() external;
   function resetAllowances() external;
   function setSettings(uint256,uint256,uint256,address) external; 
}
