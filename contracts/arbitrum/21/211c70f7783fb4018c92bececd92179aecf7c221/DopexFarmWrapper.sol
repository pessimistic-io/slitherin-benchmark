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

/// Interfaces
import {IERC20} from "./IERC20.sol";
import {IDPXSingleStaking} from "./IDPXSingleStaking.sol";

/// @title A Dopex single stake farm wrapper library
/// @author Jones DAO
/// @notice Adds a few utility functions to Dopex single stake farms
library DopexFarmWrapper {
    /**
     * @notice Stakes an amount of assets
     * @param _amount a parameter just like in doxygen (must be followed by parameter name)
     */
    function addSingleStakeAsset(IDPXSingleStaking self, uint256 _amount)
        external
        returns (bool)
    {
        self.stake(_amount);

        return true;
    }

    /**
     * @notice Stakes the complete balance if the caller is whitelisted
     * @param _caller The address to check whitelist and get the staking token balance
     */
    function depositAllIfWhitelisted(IDPXSingleStaking self, address _caller)
        external
        returns (bool)
    {
        if (self.whitelistedContracts(_caller)) {
            uint256 amount = IERC20(self.stakingToken()).balanceOf(_caller);

            self.stake(amount);
        }

        return true;
    }

    /**
     * @notice Removes an amount from staking with an option to claim rewards
     * @param _amount the amount to withdraw from staking
     * @param _getRewards if true the function will claim rewards
     */
    function removeSingleStakeAsset(
        IDPXSingleStaking self,
        uint256 _amount,
        bool _getRewards
    ) public returns (bool) {
        if (_getRewards) {
            self.getReward(2);
        }

        if (_amount > 0) {
            self.withdraw(_amount);
        }

        return true;
    }

    /**
     * @notice Removes the complete position from staking
     * @param _caller The address to get the deposited balance
     */
    function removeAll(IDPXSingleStaking self, address _caller)
        external
        returns (bool)
    {
        uint256 amount = self.balanceOf(_caller);

        removeSingleStakeAsset(self, amount, false);

        return true;
    }

    /**
     * @notice Claim all rewards
     */
    function claimRewards(IDPXSingleStaking self) external returns (bool) {
        return removeSingleStakeAsset(self, 0, true);
    }

    /**
     * @notice Removes all assets from the farm and claim all rewards
     */
    function exitSingleStakeAsset(IDPXSingleStaking self)
        external
        returns (bool)
    {
        self.exit();

        return true;
    }

    /**
     * @notice Removes all assets from the farm and claim rewards only if the caller has assets staked
     * @param _caller the address used to check if it has staked assets on the farm
     */
    function exitIfPossible(IDPXSingleStaking self, address _caller)
        external
        returns (bool)
    {
        if (self.balanceOf(_caller) > 0) {
            self.exit();
        }

        return true;
    }

    /**
     * @notice Obtain the amount of DPX earned on the farm
     * @param _caller the address used to check if it has rewards
     */
    function earnedDPX(IDPXSingleStaking self, address _caller)
        public
        view
        returns (uint256)
    {
        (uint256 reward, ) = self.earned(_caller);

        return reward;
    }

    /**
     * @notice Obtain the amount of rDPX earned on the farm
     * @param _caller the address used to check if it has rewards
     */
    function earnedRDPX(IDPXSingleStaking self, address _caller)
        external
        view
        returns (uint256)
    {
        (, uint256 reward) = self.earned(_caller);

        return reward;
    }

    /**
     * @notice Compound Single stake rewards
     */
    function compoundRewards(IDPXSingleStaking self) external returns (bool) {
        self.compound();
        return true;
    }
}

