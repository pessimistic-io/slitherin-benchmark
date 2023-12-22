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

/* Reponsible for the distribution of hats produced by the Milliner */
contract HatDistributionCenter is Ownable {
    using SafeERC20 for IERC20;

    address public milliner;
    IERC20 public rewardToken;

    constructor(address _rewardToken) {
        rewardToken = IERC20(_rewardToken);
    }

    // ============================== Milliner Functions ==============================

    function sendRewards(uint256 _amount, address _user) public onlyMilliner {
        rewardToken.safeTransfer(_user, _amount);
        emit Shipped(_user, _amount);
    }

    // ============================== Admin Functions ==============================

    function updateMilliner(address _milliner) public onlyOwner {
        milliner = _milliner;
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

