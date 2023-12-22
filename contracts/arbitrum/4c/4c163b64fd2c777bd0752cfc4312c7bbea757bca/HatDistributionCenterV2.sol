// SPDX-License-Identifier: GPL-3.0
/*                            ******@@@@@@@@@**@*                               
                        ***@@@@@@@@@@@@@@@@@@@@@@**                             
                     *@@@@@@**@@@@@@@@@@@@@@@@@*@@@*                            
                  *@@@@@@@@@@@@@@@@@@@*@@@@@@@@@@@*@**                          
                 *@@@@@@@@@@@@@@@@@@*@@@@@@@@@@@@@@@@@*                         
                **@@@@@@@@@@@@@@@@@*@@@@@@@@@@@@@@@@@@@**                       
                **@@@@@@@@@@@@@@@*@@@@@@@@@@@@@@@@@@@@@@@*                      
                **@@@@@@@@@@@@@@@@*************************                    
                **@@@@@@@@***********************************                   
                 *@@@***********************&@@@@@@@@@@@@@@@****,    ******@@@@*
           *********************@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@************* 
      ***@@@@@@@@@@@@@@@*****@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@****@@*********      
   **@@@@@**********************@@@@*****************#@@@@**********            
  *@@******************************************************                     
 *@************************************                                         
 @*******************************                                               
 *@*************************                                                    
   ********************* 
   
    /$$$$$                                               /$$$$$$$   /$$$$$$   /$$$$$$ 
   |__  $$                                              | $$__  $$ /$$__  $$ /$$__  $$
      | $$  /$$$$$$  /$$$$$$$   /$$$$$$   /$$$$$$$      | $$  \ $$| $$  \ $$| $$  \ $$
      | $$ /$$__  $$| $$__  $$ /$$__  $$ /$$_____/      | $$  | $$| $$$$$$$$| $$  | $$
 /$$  | $$| $$  \ $$| $$  \ $$| $$$$$$$$|  $$$$$$       | $$  | $$| $$__  $$| $$  | $$
| $$  | $$| $$  | $$| $$  | $$| $$_____/ \____  $$      | $$  | $$| $$  | $$| $$  | $$
|  $$$$$$/|  $$$$$$/| $$  | $$|  $$$$$$$ /$$$$$$$/      | $$$$$$$/| $$  | $$|  $$$$$$/
 \______/  \______/ |__/  |__/ \_______/|_______/       |_______/ |__/  |__/ \______/                                      
*/

pragma solidity ^0.8.2;

// Libraries
import {SafeERC20} from "./SafeERC20.sol";
import {Ownable} from "./Ownable.sol";

// Interfaces
import "./IERC20.sol";

interface IMilliner {
    struct PoolInfo {
        IERC20 lpToken;
        uint256 allocPoint;
        uint256 lastRewardSecond;
        uint256 accJonesPerShare;
        uint256 currentDeposit;
    }

    function poolInfo(uint256 _pid) external returns (PoolInfo memory);
}

/* Reponsible for the distribution of hats produced by the Milliner */
contract HatDistributionCenterV2 is Ownable {
    using SafeERC20 for IERC20;

    address public milliner;
    IERC20 public rewardToken;
    uint256 public singleStakePid;

    constructor(
        address _rewardToken,
        address _milliner,
        uint256 _singleStakePid
    ) {
        rewardToken = IERC20(_rewardToken);
        milliner = _milliner;
        singleStakePid = _singleStakePid;
    }

    // ============================== Milliner Functions ==============================

    function sendRewards(uint256 _amount, address _user) public onlyMilliner {
        address millinerAddress = milliner;
        uint256 farmTokenBalance = rewardToken.balanceOf(millinerAddress);
        uint256 farmTokenDeposit = IMilliner(millinerAddress)
            .poolInfo(singleStakePid)
            .currentDeposit;

        if (farmTokenBalance < farmTokenDeposit) {
            rewardToken.safeTransfer(
                millinerAddress,
                farmTokenDeposit - farmTokenBalance
            );
        }

        rewardToken.safeTransfer(_user, _amount);
        emit Shipped(_user, _amount);
    }

    // ============================== Admin Functions ==============================

    function updateMilliner(address _milliner) public onlyOwner {
        milliner = _milliner;
    }

    function updateSingleStakePid(uint256 _pid) public onlyOwner {
        singleStakePid = _pid;
    }

    function withdrawRewards(uint256 _amount, address _destination)
        public
        onlyOwner
    {
        rewardToken.safeTransfer(_destination, _amount);
    }

    // ============================== Modifiers ==============================

    modifier onlyMilliner() {
        if (msg.sender != milliner) {
            revert Only_Milliner();
        }
        _;
    }

    // ============================== Erors ==============================

    error Only_Milliner(); // Only milliner
    error Zero_Address(); // Zero address

    // ============================== Events ==============================

    event Shipped(address user, uint256 amount);
}

